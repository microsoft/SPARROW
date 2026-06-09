#!/usr/bin/env bash
###############################################################################
# sparrow-update.sh — automated, safe self-update from GitHub for the SPARROW Pi
#
# Run as root via systemd timer (sparrow-update.timer). Polls GitHub for new
# git tags matching TAG_PATTERN, downloads + validates the tarball, snapshots
# the current deployment, swaps in the new code (preserving Pi-local config),
# rebuilds + recreates the docker-compose stack, runs a health check, and
# auto-rolls-back if anything goes wrong.
#
# See updater/README.md for operator docs.
###############################################################################
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Configuration (override in /etc/sparrow-update.conf)
# ---------------------------------------------------------------------------
REPO_OWNER="Clamps251"
REPO_NAME="sparrow-pi"
DEPLOY_DIR="/home/sparrow/Desktop/system"
STATE_DIR="/var/lib/sparrow-update"
LOG_FILE="$STATE_DIR/log/sparrow-update.log"
LOCK_FILE="$STATE_DIR/lock"
STUCK_FILE="$STATE_DIR/STUCK"
# Default to date-style tags like v2026.06.10; override via /etc/sparrow-update.conf
TAG_PATTERN='^v[0-9]{4}\.[0-9]{2}\.[0-9]{2}(-[A-Za-z0-9._-]+)?$'
KEEP_BACKUPS=2
HEALTH_SLEEP_SECS=60
HTTP_TIMEOUT=30
DOWNLOAD_TIMEOUT=180
USER_AGENT="sparrow-pi-updater"
# GITHUB_TOKEN — required while the repo is private. Set in /etc/sparrow-update.conf.
GITHUB_TOKEN=""

CONFIG_FILE="/etc/sparrow-update.conf"
[[ -r "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Build auth header array used by every curl call.
AUTH_HEADERS=(-H "Accept: application/vnd.github+json" -H "User-Agent: $USER_AGENT")
if [[ -n "$GITHUB_TOKEN" ]]; then
    AUTH_HEADERS+=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

# Resolved paths after config load
STAGING_DIR="$STATE_DIR/staging"
BACKUP_DIR="$STATE_DIR/backup"
CURRENT_TAG_FILE="$STATE_DIR/current_tag"
CURRENT_SHA_FILE="$STATE_DIR/current_sha"

# Paths preserved from the running deployment — applied as rsync excludes both
# when laying down a new release and when restoring a backup.
PRESERVE_EXCLUDES=(
    "--exclude=sparrow.env"
    "--exclude=starlink.env"
    "--exclude=sparrow/config/"
    "--exclude=starlink/config/"
    "--exclude=sparrow/logs/"
    "--exclude=sparrow/images/"
    "--exclude=sparrow/recordings/"
    "--exclude=sparrow/static/"
    "--exclude=starlink/logs/"
    "--exclude=Models/"
    "--exclude=.git/"
)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$LOG_FILE")" "$STAGING_DIR" "$BACKUP_DIR"

log() {
    # Writes to stderr (visible to systemd journal) and appends to the log file.
    # CRITICAL: never writes to stdout, because callers capture function stdout
    # via $() — log lines bleeding into that would corrupt results.
    local level="$1"; shift
    local ts msg
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    msg="$ts $level $*"
    printf '%s\n' "$msg" >&2
    printf '%s\n' "$msg" >> "$LOG_FILE"
}

die() {
    log CRITICAL "$*"
    exit 1
}

on_error() {
    local rc=$?
    log ERROR "Unexpected exit (rc=$rc) at line ${BASH_LINENO[0]}"
    exit "$rc"
}
trap on_error ERR

# ---------------------------------------------------------------------------
# Single-instance guard via flock
# ---------------------------------------------------------------------------
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log INFO "another update in progress; exiting"
    exit 0
fi

if [[ -f "$STUCK_FILE" ]]; then
    log CRITICAL "STUCK flag present at $STUCK_FILE — refusing to run. Operator must clear it after diagnosis."
    exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "required tool missing: $1"
}
require_tool curl
require_tool jq
require_tool tar
require_tool rsync
require_tool sha256sum
require_tool docker-compose
require_tool docker

read_current_tag() {
    [[ -f "$CURRENT_TAG_FILE" ]] && cat "$CURRENT_TAG_FILE" || echo ""
}
read_current_sha() {
    [[ -f "$CURRENT_SHA_FILE" ]] && cat "$CURRENT_SHA_FILE" || echo ""
}

# Clean any leftover staging dirs from prior crashed runs.
clean_stale_staging() {
    if [[ -d "$STAGING_DIR" ]]; then
        find "$STAGING_DIR" -maxdepth 1 -mindepth 1 \( -type d -o -type f -name '*.tar.gz' \) -print0 \
            | xargs -0 -r rm -rf
    fi
}

# Print "<tag>\t<sha>" of the newest tag matching TAG_PATTERN, or empty if none.
fetch_latest_matching_tag() {
    local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/tags?per_page=50"
    local body
    if ! body=$(curl -sf -m "$HTTP_TIMEOUT" "${AUTH_HEADERS[@]}" "$api_url"); then
        log WARN "failed to query $api_url (network or auth issue)"
        return 1
    fi
    # Tags are returned newest-first by the GitHub API. Pick the first matching one.
    # If no match, jq's `first` yields null and string interpolation gives "null\tnull",
    # which the caller treats as "no match".
    jq -r --arg pat "$TAG_PATTERN" \
        '[.[] | select(.name | test($pat))] | first | "\(.name)\t\(.commit.sha)"' \
        <<<"$body"
}

download_tarball() {
    local tag="$1" dest="$2"
    # Use the API endpoint (not codeload) so the Authorization header works for
    # private repos. The API responds with a 302 redirect to the actual tarball.
    local url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/tarball/refs/tags/${tag}"
    log INFO "downloading $url"
    curl -sfL -m "$DOWNLOAD_TIMEOUT" "${AUTH_HEADERS[@]}" -o "$dest" "$url" \
        || die "tarball download failed for tag=$tag"
}

verify_tarball() {
    local tarball="$1" extract_dir="$2"
    local sha
    sha=$(sha256sum "$tarball" | awk '{print $1}')
    log INFO "tarball sha256=$sha"

    tar -tzf "$tarball" >/dev/null || die "tarball is not a valid gzip+tar"

    local need=(docker-compose.yml sparrow/Dockerfile sparrow/requirements.txt starlink/Dockerfile.starlink)
    local listing
    listing=$(tar -tzf "$tarball")
    for f in "${need[@]}"; do
        # Listing entries look like "Clamps251-sparrow-pi-<sha>/path/to/file"
        grep -qE "^[^/]+/${f}\$" <<<"$listing" \
            || die "tarball missing required file: $f"
    done

    mkdir -p "$extract_dir"
    tar -xzf "$tarball" -C "$extract_dir" --strip-components=1 \
        || die "tar extraction failed"
}

# docker compose syntax check against the extracted compose file. We can't run
# the full validation in the staging dir (paths inside docker-compose.yml are
# relative to the project dir), so we just check YAML + Compose schema by piping.
validate_compose() {
    local dir="$1"
    ( cd "$dir" && docker-compose -f docker-compose.yml config >/dev/null ) \
        || die "docker-compose config validation failed in $dir"
}

snapshot_to_backup() {
    local tag="$1"
    local target="$BACKUP_DIR/$tag"
    rm -rf "$target"
    mkdir -p "$target"
    rsync -a --delete "${PRESERVE_EXCLUDES[@]}" "$DEPLOY_DIR/" "$target/"
    log INFO "snapshot saved: $target"
}

apply_release() {
    local src="$1"
    rsync -a --delete "${PRESERVE_EXCLUDES[@]}" "$src/" "$DEPLOY_DIR/"
}

restore_backup() {
    local tag="$1"
    local src="$BACKUP_DIR/$tag"
    [[ -d "$src" ]] || die "no backup to restore at $src"
    rsync -a --delete "${PRESERVE_EXCLUDES[@]}" "$src/" "$DEPLOY_DIR/"
    log INFO "restored backup: $src"
}

compose_build() {
    ( cd "$DEPLOY_DIR" && docker-compose build 2>&1 | tail -20 | sed 's/^/    | /' ) \
        || return 1
    return 0
}

compose_recreate() {
    ( cd "$DEPLOY_DIR" && docker-compose up -d --force-recreate 2>&1 | tail -10 | sed 's/^/    | /' ) \
        || return 1
    return 0
}

# Health check. Returns 0 on pass, non-zero on fail. Logs each sub-check.
health_check() {
    local fail=0

    # 1. Containers running
    for c in sparrow_service starlink_tools_container; do
        local state
        state=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo missing)
        if [[ "$state" != "running" ]]; then
            log ERROR "HEALTH FAIL: $c state=$state (expected running)"
            fail=1
        else
            log INFO "HEALTH OK: $c is running"
        fi
    done

    # 2. No fatal patterns in container logs since the container started
    local since
    for c in sparrow_service starlink_tools_container; do
        since=$(docker inspect -f '{{.State.StartedAt}}' "$c" 2>/dev/null || true)
        if [[ -z "$since" ]]; then
            continue
        fi
        local recent
        recent=$(docker logs --since "$since" "$c" 2>&1 | tail -500 || true)
        local pattern='Traceback \(most recent call last\)|ImportError|ModuleNotFoundError|supervisord: .* exited with non-zero status|CRITICAL.*Cannot proceed'
        if grep -qE "$pattern" <<<"$recent"; then
            log ERROR "HEALTH FAIL: fatal pattern in $c logs since restart"
            fail=1
        else
            log INFO "HEALTH OK: no fatal patterns in $c logs"
        fi
    done

    # 3. Heartbeat logs — files that SHOULD see writes inside the polling interval.
    #    Allow-list approach: only check logs whose owning process polls on a
    #    known schedule; ignore event-driven logs (ftp/smtp/controller) that
    #    legitimately stay quiet for hours.
    local heartbeats=(
        /app/logs/inference.log           # model_settings poll ~60s
        /app/logs/restclient_logs.log     # metrics job every minute
    )
    local now
    now=$(docker exec sparrow_service date +%s 2>/dev/null || echo 0)
    for logf in "${heartbeats[@]}"; do
        local age
        age=$(docker exec sparrow_service stat -c %Y "$logf" 2>/dev/null || echo 0)
        if (( age == 0 )); then
            log ERROR "HEALTH FAIL: heartbeat log missing: $logf"
            fail=1
            continue
        fi
        if (( now - age > 120 )); then
            log ERROR "HEALTH FAIL: heartbeat log stale: $logf (age $((now-age))s)"
            fail=1
        else
            log INFO "HEALTH OK: $logf age=$((now-age))s"
        fi
    done

    return "$fail"
}

prune_backups() {
    local -a backups
    mapfile -t backups < <(ls -1t "$BACKUP_DIR" 2>/dev/null || true)
    if (( ${#backups[@]} > KEEP_BACKUPS )); then
        for old in "${backups[@]:$KEEP_BACKUPS}"; do
            rm -rf "${BACKUP_DIR:?}/$old"
            log INFO "pruned old backup: $old"
        done
    fi
}

# ---------------------------------------------------------------------------
# Rollback
# ---------------------------------------------------------------------------
rollback() {
    local previous_tag="$1" reason="$2"
    log ERROR "ROLLBACK to $previous_tag (reason: $reason)"

    if [[ -z "$previous_tag" || ! -d "$BACKUP_DIR/$previous_tag" ]]; then
        touch "$STUCK_FILE"
        die "no backup available to roll back to; STUCK flag set"
    fi

    restore_backup "$previous_tag"

    if ! compose_build; then
        touch "$STUCK_FILE"
        die "rollback rebuild failed; STUCK flag set"
    fi
    compose_recreate || true

    log INFO "rollback rebuild + recreate complete; waiting ${HEALTH_SLEEP_SECS}s for health check"
    sleep "$HEALTH_SLEEP_SECS"
    if health_check; then
        log INFO "rolled back successfully to $previous_tag"
        return 0
    fi
    touch "$STUCK_FILE"
    die "rollback succeeded structurally but health check still failing; STUCK flag set"
}

# ---------------------------------------------------------------------------
# Main flow
# ---------------------------------------------------------------------------
log INFO "==== sparrow-update tick: deploy_dir=$DEPLOY_DIR state_dir=$STATE_DIR ===="
clean_stale_staging

current_tag=$(read_current_tag)
current_sha=$(read_current_sha)
log INFO "current_tag=${current_tag:-<none>} current_sha=${current_sha:-<none>}"

latest=$(fetch_latest_matching_tag || true)
if [[ -z "$latest" || "$latest" == "null"* ]]; then
    log INFO "no tag matching pattern $TAG_PATTERN; nothing to do"
    exit 0
fi

new_tag=$(cut -f1 <<<"$latest")
new_sha=$(cut -f2 <<<"$latest")
log INFO "latest matching tag: $new_tag ($new_sha)"

if [[ "$new_tag" == "$current_tag" ]]; then
    log INFO "up to date"
    exit 0
fi

# 5-7. Download + verify + extract
tarball="$STAGING_DIR/${new_tag}.tar.gz"
extract_dir="$STAGING_DIR/$new_tag"
download_tarball "$new_tag" "$tarball"
verify_tarball "$tarball" "$extract_dir"
log INFO "tarball extracted to $extract_dir"

# 8. Compose-config validation
validate_compose "$extract_dir"

# 9. Snapshot current deployment for rollback. First-time installs have no
#    current_tag, so we snapshot under a synthetic "preinstall" key.
backup_tag="${current_tag:-preinstall-$(date -u +%Y%m%dT%H%M%SZ)}"
snapshot_to_backup "$backup_tag"

# 10. Apply new release
apply_release "$extract_dir"
log INFO "applied $new_tag to $DEPLOY_DIR"

# 11. Build
if ! compose_build; then
    log ERROR "docker-compose build failed for $new_tag"
    rollback "$backup_tag" "build failed"
    exit 0
fi

# 12. Recreate
compose_recreate || log WARN "compose recreate returned non-zero"

# 13. Sleep then health check
log INFO "waiting ${HEALTH_SLEEP_SECS}s before health check"
sleep "$HEALTH_SLEEP_SECS"

# 14. Health check
if health_check; then
    echo "$new_tag" > "$CURRENT_TAG_FILE"
    echo "$new_sha" > "$CURRENT_SHA_FILE"
    log INFO "SUCCESS: deployed $new_tag ($new_sha)"
    # Cleanup staging
    rm -rf "$extract_dir" "$tarball"
    prune_backups
    exit 0
else
    rollback "$backup_tag" "health check failed"
    # Cleanup staging on failed deploy as well
    rm -rf "$extract_dir" "$tarball"
    exit 0
fi
