# SPARROW auto-updater

A small bash-based update daemon for deployed SPARROW Pis. It polls
`microsoft/SPARROW` every 15 minutes, deploys the newest **tagged release**
matching `v<YYYY>.<MM>.<DD>`, rebuilds and recreates the docker-compose
stack, and **auto-rolls-back** if the new build fails to come up healthy.

Pi-local config (env files, access keys, runtime data, ONNX models, `.git/`)
is never touched.

## Files

| Path | Role |
|---|---|
| `updater/sparrow-update.sh` | The script. Runs as root via systemd. |
| `updater/install.sh` | One-time installer; copies the script to `/usr/local/sbin/`, writes the systemd unit + timer + logrotate config. Idempotent. |
| `/etc/sparrow-update.conf` | Optional overrides (`REPO_OWNER`, `TAG_PATTERN`, `KEEP_BACKUPS`, …). Sourced by the script if present. |
| `/var/lib/sparrow-update/` | Runtime state: `current_tag`, `current_sha`, `staging/`, `backup/`, `log/`, `lock`, and the `STUCK` flag. |

## Bootstrap

From a fresh field-deployed Pi (or any Pi where the repo is already at
`/home/sparrow/Desktop/system/`):

```bash
cd /home/sparrow/Desktop/system
sudo bash updater/install.sh
```

That's it — no prompts, no config. The installer works against the public
`microsoft/SPARROW` repo out of the box.

### Optional: private fork / auth

If you're running your own private fork instead of the upstream repo, pass a
GitHub fine-grained PAT (scoped to *Contents: Read-only*) through to the
installer via env var:

```bash
sudo env UPDATER_GITHUB_TOKEN=github_pat_xxx bash updater/install.sh
```

It lands in `/etc/sparrow-update.conf` (mode 0600) and the updater reads it
on every tick. Also override `REPO_OWNER` / `REPO_NAME` in the same file to
point at your fork.

## Tagging a release

Auto-deploy fires when a tag matches the date-pattern `vYYYY.MM.DD`
(suffixes like `-fix` or `-hotfix1` are allowed). Examples that **do** trigger
a deploy: `v2026.06.10`, `v2026.06.10-hotfix1`. Examples that **don't**:
`main`, `dev`, `release/2026.06.10`.

```bash
# from your dev machine, on the commit you want to ship
git tag v2026.06.10
git push origin v2026.06.10
```

Within 15 minutes (or immediately if you run `sudo systemctl start
sparrow-update.service` on the Pi), the new tag is detected, downloaded,
verified, snapshotted, applied, built, recreated, and health-checked.

## Operator commands

```bash
# What's currently deployed?
sudo cat /var/lib/sparrow-update/current_tag
sudo cat /var/lib/sparrow-update/current_sha

# Force an immediate update tick (still no-op if no new matching tag)
sudo systemctl start sparrow-update.service

# Tail the activity log
sudo journalctl -u sparrow-update.service -f

# Long-term log (rotated weekly, 8 kept)
sudo less /var/lib/sparrow-update/log/sparrow-update.log

# Inspect timer state
systemctl list-timers sparrow-update.timer

# Pause auto-updates (e.g. during field debugging)
sudo systemctl disable --now sparrow-update.timer
# ... resume
sudo systemctl enable --now sparrow-update.timer
```

## The `STUCK` flag

If both the new deploy AND the auto-rollback fail to pass the health check,
the script creates `/var/lib/sparrow-update/STUCK`. The systemd timer will
keep firing, but the script bails immediately when it sees the flag — better
to leave things as-is than to keep churning.

To clear it after diagnosis:

```bash
# 1. Fix the underlying issue (e.g. push a corrected tag)
# 2. Optionally restore from a backup manually:
sudo ls /var/lib/sparrow-update/backup/
# 3. Clear the flag
sudo rm /var/lib/sparrow-update/STUCK
# 4. Trigger a run
sudo systemctl start sparrow-update.service
```

## Behaviour guarantees

- **Single-instance:** `flock` on `/var/lib/sparrow-update/lock` prevents two
  updates ever running at once.
- **Atomic-ish swap:** the snapshot is taken before the rsync, so any failure
  after rsync but before health-check pass triggers a clean rollback.
- **Pi-local preservation:** every rsync (forward and reverse) carries the
  same exclude list, so deployment-specific config and runtime data survive.
- **Bounded history:** only `KEEP_BACKUPS` (default 2) snapshots kept.
  Each is ~10 MB (no logs/Models/runtime data inside).
- **Never touches:** `/boot/firmware/config.txt`, the systemd units themselves,
  `Models/`, `sparrow/{config,logs,images,recordings,static}/`,
  `starlink/{config,logs}/`, `.git/`, or `/usr/local/sbin/sparrow-update.sh`
  (the running script never updates itself).

## Updating the updater

The script at `/usr/local/sbin/sparrow-update.sh` is intentionally **not**
auto-updated. If `updater/sparrow-update.sh` changes in a release tag and
you want it live, re-run the installer manually after that tag is deployed:

```bash
sudo bash /home/sparrow/Desktop/system/updater/install.sh
```

This is the price of keeping the updater immune to its own bugs.
