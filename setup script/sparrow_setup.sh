#!/usr/bin/env bash
###############################################################################
#  SPARROW Setup Script (Raspberry Pi 5 / Debian Trixie)
#  - Uses Docker's official Debian repo for Docker Engine + Compose plugin
#  - Enables I2C (+ optional DS3231 overlay) via boot config
#  - Installs Witty Pi 5 software and configures auto power-on on power restore
#  - Clones a private GitHub repo using a prompted fine-grained PAT
#  - Keeps model/version folder structure, without Triton config.pbtxt files
#  - Shows command output in terminal and logs to /var/log/sparrow_setup.log
###############################################################################
set -euo pipefail
export GTK_A11Y=none

# Survive SSH session drops (e.g. Pi Connect terminal glitches, network blips):
# ignore SIGHUP so the parent shell dying doesn't kill this script mid-install,
# and ignore SIGPIPE so a write to a dead terminal doesn't take us down either.
# Without this, a session drop during a slow apt step (docker-ce download on
# a poor field link is minutes long) silently aborts setup with no error log.
trap '' HUP PIPE

###############################################################################
# 0.  -- GUI HELPERS --
###############################################################################
GUI=true; for a in "$@"; do [[ "$a" == "--no-gui" ]] && GUI=false; done

_install_zenity() {
    $GUI || return
    if ! command -v zenity >/dev/null 2>&1; then
        echo "Installing Zenity..." >&2
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y zenity >/dev/null
    fi
}

_yesno() {
    if $GUI && command -v zenity >/dev/null 2>&1; then
        zenity --question --no-wrap --text="$1" --width=440
    else
        read -rp "$1 (y/n): " _ans
        [[ "${_ans,,}" =~ ^y(es)?$ ]]
    fi
}

_input() {
    if $GUI && command -v zenity >/dev/null 2>&1; then
        local opts=(--entry --text="$1" --width=460)
        [[ "${2:-}" == "hide" ]] && opts+=(--hide-text)
        zenity "${opts[@]}"
    else
        if [[ "${2:-}" == "hide" ]]; then
            read -rsp "$1: " _txt
            echo
            echo "$_txt"
        else
            read -rp "$1: " _txt
            echo "$_txt"
        fi
    fi
}

_info()  { $GUI && command -v zenity >/dev/null 2>&1 && zenity --info  --no-wrap --text="$*" --width=480 || echo -e "$*"; }
_error() { $GUI && command -v zenity >/dev/null 2>&1 && zenity --error --no-wrap --text="$*" --width=480 || { echo -e "ERROR: $*" >&2; } }

_progress() {
    local msg="$1"
    shift

    if $GUI && command -v zenity >/dev/null 2>&1; then
        (
            echo "$msg"
            "$@" 2>&1 | tee /dev/tty
        ) | zenity --progress --pulsate --no-cancel --auto-close --text="$msg" --width=480
    else
        "$@"
    fi
}

###############################################################################
# 1.  -- CONFIGURATION --
###############################################################################
LOG_FILE="/var/log/sparrow_setup.log"
UUID_FILE="/etc/unique_id"

HOTSPOT_SSID="CameraTraps"
HOTSPOT_PASSWORD=""
WIFI_INTERFACE="wlan0"

MODEL_DOWNLOAD_URL="https://zenodo.org/record/14661733/files/MDV6b-yolov9c.onnx?download=1"
MODEL_DIR_NAME="1"
MODEL_FILENAME_TEMP="MDV6b-yolov9c.onnx"
MODEL_FILENAME_FINAL="model.onnx"

AI4G_MODEL_DOWNLOAD_URL="https://zenodo.org/records/15041754/files/AI4GAmazonClassificationV2.onnx?download=1"
AI4G_MODEL_DIR_NAME="1"
AI4G_MODEL_FILENAME_TEMP="AI4GAmazonClassificationV2.onnx"
AI4G_MODEL_FILENAME_FINAL="model.onnx"

AUDIO_BIRDS_MODEL_DOWNLOAD_URL="https://zenodo.org/records/17256803/files/MD_AudioBirds_V1.onnx?download=1"
AUDIO_BIRDS_MODEL_DIR_NAME="1"
AUDIO_BIRDS_MODEL_FILENAME_TEMP="MD_AudioBirds_V1.onnx"
AUDIO_BIRDS_MODEL_FILENAME_FINAL="model.onnx"

REPO_URL="https://github.com/microsoft/SPARROW.git"
CLONE_DIR=""
USE_ROBIN=false
XBEE_FAMILY="${XBEE_FAMILY:-}"

ONBOARDING_URL="https://server.sparrowstudio.azure.com/v1/onboarding"
EMAIL=""

ENV_FILE=""
FTP_PASS=""

I2C_BUS="1"

WP5_URL="https://www.uugear.com/repo/WittyPi5/wp5_latest.deb"
WP5_DEB="/tmp/wp5_latest.deb"
WP5_ADDR="0x51"

###############################################################################
# 2.  -- UTILITY FUNCTIONS --
###############################################################################
log() { echo -e "$(date +"%Y-%m-%d %H:%M:%S") : $*" | tee -a "$LOG_FILE"; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

install_uuidgen() {
    if command_exists uuidgen; then
        log "uuidgen already installed."
        return 0
    fi

    mkdir -p /run/uuidd && chmod 755 /run/uuidd
    apt-get update -y || log "WARN: apt-get update failed; continuing with cached indexes."

    # /usr/bin/uuidgen ships in the uuid-runtime binary package on every
    # current Debian release (Bookworm and Trixie both build it from the
    # util-linux source; util-linux itself does NOT ship uuidgen).
    # Guard the install so set -e doesn't abort before we can log a
    # diagnostic that actually helps the operator.
    if apt-get install -y uuid-runtime; then
        log "Installed uuid-runtime."
    else
        log "ERROR: 'apt install uuid-runtime' failed."
        log "       On Debian, /usr/bin/uuidgen is shipped by the uuid-runtime package."
        log "       If apt reported 'no installation candidate', /etc/apt/sources.list"
        log "       is likely missing the 'main' component, or set to the wrong suite."
        log "       Expected entry for Trixie:"
        log "         deb http://deb.debian.org/debian $(lsb_release -sc 2>/dev/null || echo trixie) main"
        log "       Fix sources.list, run 'sudo apt-get update', then re-run this script."
    fi

    if ! command_exists uuidgen; then
        return 1
    fi
}

generate_unique_id() {
    [[ -s "$UUID_FILE" ]] && { log "UUID exists: $(cat "$UUID_FILE")"; return; }
    local NEW_UUID
    NEW_UUID=$(uuidgen)
    echo "$NEW_UUID" | tee "$UUID_FILE" >/dev/null
    chmod 644 "$UUID_FILE"
    chown root:root "$UUID_FILE"
    log "Generated UUID: $NEW_UUID"
}

get_hardware_id() {
    if [[ ! -f "$UUID_FILE" ]]; then
        log "UUID file not found at $UUID_FILE"
        return 1
    fi

    local uuid
    uuid=$(tr -d '\r\n' <"$UUID_FILE")
    [[ -n "$uuid" ]] || { log "UUID in $UUID_FILE is empty"; return 1; }

    local hwid
    hwid=$(printf '%s' "$uuid" | sha256sum | awk '{print substr($1,1,12)}')
    [[ -n "$hwid" ]] || { log "Failed to derive hardware id from UUID"; return 1; }

    log "Generated Hardware ID for onboarding: $hwid" >/dev/null
    echo "$hwid"
}

install_curl()  { command_exists curl  || { apt-get update -y; apt-get install -y curl;  } }
install_wget()  { command_exists wget  || { apt-get update -y; apt-get install -y wget;  } }
install_git()   { command_exists git   || { apt-get update -y; apt-get install -y git;   } }

###############################################################################
# Docker / Compose
###############################################################################
install_docker_pi_debian() {
    log "Installing Docker Engine + Compose from Docker's official Debian repo..."

    apt-get remove -y docker.io docker-compose docker-doc podman-docker containerd runc || true

    apt-get update -y
    apt-get install -y ca-certificates curl gnupg

    install -m 0755 -d /etc/apt/keyrings

    if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
        curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
    fi

    local arch codename
    arch="$(dpkg --print-architecture)"
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"

    cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${codename} stable
EOF

    apt-get update -y

    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable --now docker

    docker --version
    docker compose version
}

docker_compose_cmd() {
    docker compose "$@"
}

###############################################################################
# NetworkManager
###############################################################################
install_network_manager() {
    command_exists nmcli && return
    apt-get update -y
    apt-get install -y network-manager
    systemctl enable --now NetworkManager
}

# Some fresh Trixie installs ship with wifi soft-blocked (rfkill) or with
# `nmcli radio wifi` off — either state makes the hotspot setup on line 813
# fail with a confusing NetworkManager error and no clear signal to the
# operator. Toggle both on unconditionally; both are idempotent when wifi
# is already enabled.
enable_wifi_radio() {
    log "Ensuring Wi-Fi radio is enabled..."
    rfkill unblock wifi 2>/dev/null || true
    nmcli radio wifi on 2>/dev/null || true
}

###############################################################################
# I2C enablement
###############################################################################
_pi_boot_config_path() {
    if [[ -f /boot/firmware/config.txt ]]; then
        echo "/boot/firmware/config.txt"
    elif [[ -f /boot/config.txt ]]; then
        echo "/boot/config.txt"
    else
        return 1
    fi
}

enable_i2c_pi() {
    local cfg
    cfg=$(_pi_boot_config_path) || { _error "Could not find Pi boot config.txt in /boot/firmware or /boot"; return 1; }

    local changed=false

    if ! grep -qE '^\s*dtparam=i2c_arm=on\s*$' "$cfg"; then
        echo "dtparam=i2c_arm=on" >>"$cfg"
        changed=true
        log "Added dtparam=i2c_arm=on to $cfg"
    fi

    mkdir -p /etc/modules-load.d
    if [[ ! -f /etc/modules-load.d/i2c-dev.conf ]] || ! grep -qE '^\s*i2c-dev\s*$' /etc/modules-load.d/i2c-dev.conf; then
        echo "i2c-dev" >>/etc/modules-load.d/i2c-dev.conf
        changed=true
        log "Ensured i2c-dev loads at boot"
    fi

    apt-get update -y
    apt-get install -y i2c-tools || true
    modprobe i2c-dev || true

    if $changed; then
        _info "I2C has been enabled in firmware config.\n\nA reboot is required before /dev/i2c-1 is guaranteed to appear.\nReboot now, then rerun this script."
        exit 0
    fi
}

enable_ds3231_overlay_pi() {
    local cfg
    cfg=$(_pi_boot_config_path) || { _error "Could not find Pi boot config.txt"; return 1; }

    if ! grep -qE '^\s*dtoverlay=i2c-rtc,ds3231\s*$' "$cfg"; then
        echo "dtoverlay=i2c-rtc,ds3231" >>"$cfg"
        log "Added dtoverlay=i2c-rtc,ds3231 to $cfg"
        _info "DS3231 overlay added.\n\nReboot is required. Reboot, then rerun this script."
        exit 0
    fi
}

###############################################################################
# Witty Pi 5
###############################################################################
install_wittypi5() {
    log "Installing Witty Pi 5 software..."
    apt-get update -y
    apt-get install -y wget i2c-tools ca-certificates
    rm -f "$WP5_DEB"
    wget -O "$WP5_DEB" "$WP5_URL"
    apt-get install -y "$WP5_DEB"
}

detect_wittypi5() {
    log "Checking for Witty Pi 5 on I2C..."
    if ! i2cget -y "$I2C_BUS" "$WP5_ADDR" 0 >/dev/null 2>&1; then
        _error "Witty Pi 5 not detected on I2C bus $I2C_BUS at address $WP5_ADDR.
Check the HAT seating and make sure power goes into the Witty Pi board."
        exit 1
    fi
}

configure_wittypi5_auto_power_on() {
    log "Configuring Witty Pi 5 auto power-on after power restore..."
    i2cset -y "$I2C_BUS" "$WP5_ADDR" 17 0
}

verify_wittypi5_auto_power_on() {
    log "Verifying Witty Pi 5 auto power-on setting..."
    local value
    value="$(i2cget -y "$I2C_BUS" "$WP5_ADDR" 17)"
    log "Witty Pi 5 register 17 = $value"

    if [[ "$value" != "0x00" ]]; then
        _error "Failed to configure Witty Pi 5 auto power-on. Register 17 is $value, expected 0x00."
        exit 1
    fi
}

###############################################################################
# Hotspot
###############################################################################
prompt_hotspot_password() {
    local p1 p2
    while true; do
        p1=$(_input "Enter Wi-Fi Hotspot password for SSID \"$HOTSPOT_SSID\"" hide)
        p2=$(_input "Re-enter the Wi-Fi Hotspot password" hide)

        if [[ -z "${p1:-}" || -z "${p2:-}" ]]; then
            _error "Password cannot be empty."
            continue
        fi
        if [[ "$p1" != "$p2" ]]; then
            _error "Passwords do not match. Please try again."
            continue
        fi
        if (( ${#p1} < 8 || ${#p1} > 63 )); then
            _error "WPA2-PSK password must be between 8 and 63 characters."
            continue
        fi
        HOTSPOT_PASSWORD="$p1"
        break
    done
}

setup_persistent_wifi_hotspot() {
    local ssid="$HOTSPOT_SSID" pw="$HOTSPOT_PASSWORD" iface="$WIFI_INTERFACE"

    if [[ -z "$pw" ]]; then
        _error "Hotspot password is empty. This should have been set earlier."
        return 1
    fi

    if ! command_exists nmcli; then
        _error "nmcli not found. NetworkManager must be installed for hotspot setup."
        return 1
    fi

    if nmcli connection show "$ssid" >/dev/null 2>&1; then
        nmcli connection modify "$ssid" wifi-sec.psk "$pw"
        nmcli -t -f NAME connection show --active | grep -qx "$ssid" || nmcli connection up "$ssid"
    else
        nmcli connection add type wifi ifname "$iface" con-name "$ssid" autoconnect yes ssid "$ssid"
        nmcli connection modify "$ssid" 802-11-wireless.mode ap 802-11-wireless.band bg ipv4.method shared
        nmcli connection modify "$ssid" wifi-sec.key-mgmt wpa-psk
        nmcli connection modify "$ssid" wifi-sec.psk "$pw"
        nmcli connection up "$ssid"
    fi
}

###############################################################################
# Models + repo
###############################################################################
download_model() {
    local dir="$SYSTEM_FOLDER/Models/tritonserver/model_repository/megadetectorv6/$MODEL_DIR_NAME"
    local tmp="$dir/$MODEL_FILENAME_TEMP" fin="$dir/$MODEL_FILENAME_FINAL"
    mkdir -p "$dir"
    while true; do
        if _progress "Downloading Megadetector v6..." wget -q -O "$tmp" "$MODEL_DOWNLOAD_URL"; then
            mv "$tmp" "$fin"
            break
        fi
        _yesno "Megadetector download failed. Retry?" || { _error "Aborted."; exit 1; }
    done
}

download_model_ai4g() {
    local dir="$SYSTEM_FOLDER/Models/tritonserver/model_repository/AI4GAmazonClassification/$AI4G_MODEL_DIR_NAME"
    local tmp="$dir/$AI4G_MODEL_FILENAME_TEMP" fin="$dir/$AI4G_MODEL_FILENAME_FINAL"
    mkdir -p "$dir"
    while true; do
        if _progress "Downloading AI4G model..." wget -q -O "$tmp" "$AI4G_MODEL_DOWNLOAD_URL"; then
            mv "$tmp" "$fin"
            break
        fi
        _yesno "AI4G model download failed. Retry?" || { _error "Aborted."; exit 1; }
    done
}

download_model_audio_birds() {
    local dir="$SYSTEM_FOLDER/Models/tritonserver/model_repository/megadetector_birds_v1/$AUDIO_BIRDS_MODEL_DIR_NAME"
    local tmp="$dir/$AUDIO_BIRDS_MODEL_FILENAME_TEMP" fin="$dir/$AUDIO_BIRDS_MODEL_FILENAME_FINAL"
    mkdir -p "$dir"
    while true; do
        if _progress "Downloading MD Audio Birds v1..." wget -q -O "$tmp" "$AUDIO_BIRDS_MODEL_DOWNLOAD_URL"; then
            mv "$tmp" "$fin"
            break
        fi
        _yesno "Audio Birds model download failed. Retry?" || { _error "Aborted."; exit 1; }
    done
}

clone_repo() {
    CLONE_DIR="$SYSTEM_FOLDER"
    local tmpdir
    tmpdir="$(mktemp -d)"

    log "Cloning $REPO_URL..."

    if ! git clone --depth=1 "$REPO_URL" "$tmpdir"; then
        rm -rf "$tmpdir"
        _error "Failed to clone $REPO_URL. Check network and that the URL is correct."
        exit 1
    fi

    (
      shopt -s dotglob
      cp -a "$tmpdir"/* "$CLONE_DIR"/
    )

    rm -rf "$tmpdir"
    create_additional_directories
}

prompt_robin_usage() {
    if _yesno "Is ROBIN being used?"; then
        USE_ROBIN=true
    else
        USE_ROBIN=false
    fi
}

detect_xbee_port() {
    local port=""

    if [[ -d /dev/serial/by-id ]]; then
        for dev in /dev/serial/by-id/*; do
            [[ -e "$dev" ]] || continue
            port="$(readlink -f "$dev")"
            [[ -n "$port" ]] && break
        done
    fi

    if [[ -z "$port" ]]; then
        for dev in /dev/ttyUSB* /dev/ttyACM*; do
            [[ -e "$dev" ]] || continue
            port="$dev"
            break
        done
    fi

    if [[ -z "$port" ]]; then
        _error "Could not auto-detect XBee serial device."
        return 1
    fi

    echo "$port"
}

prompt_xbee_family() {
    # Honor an env override so headless / repeat runs skip the prompt.
    case "${XBEE_FAMILY:-}" in
        868|900)
            log "XBEE_FAMILY=$XBEE_FAMILY (from env)"
            return 0
            ;;
        "") : ;;
        *)
            log "WARN: XBEE_FAMILY='$XBEE_FAMILY' is invalid; falling back to prompt."
            ;;
    esac

    if _yesno "Is the XBee radio an XBee-PRO 900 (rather than the default XBee SX 868)?"; then
        XBEE_FAMILY=900
    else
        XBEE_FAMILY=868
    fi
    export XBEE_FAMILY
    log "XBEE_FAMILY=$XBEE_FAMILY"
}

run_xbee_configure_if_needed() {
    [[ "${USE_ROBIN:-false}" == "true" ]] || {
        log "ROBIN not in use; skipping xbee_configure.py"
        return 0
    }

    prompt_xbee_family

    local xbee_port
    xbee_port="$(detect_xbee_port)" || exit 1

    log "Running xbee_configure.py for ROBIN on port $xbee_port (family=${XBEE_FAMILY:-868})..."
    (
        cd "$SYSTEM_FOLDER/sparrow"
        python xbee_configure.py \
          --port "$xbee_port" \
          --baud 115200 \
          --api 1 \
          --rf 1 \
          --router 0 \
          --netid 1234 \
          --node SPARROW_MASTER \
          --family "${XBEE_FAMILY:-868}"
    )
}

create_additional_directories() {
    mkdir -p "$SYSTEM_FOLDER/sparrow"/{logs,images,recordings,static/data,static/gallery,config}
    mkdir -p "$SYSTEM_FOLDER/starlink"/{logs,config}
}

# Patch docker-compose.yml + env files so their by-id serial paths match the
# hardware that's actually plugged into THIS Pi. The repo bakes in a specific
# FTDI serial (from the reference deployment) and a generic Victron VE.Direct
# name, but every FTDI adapter has a unique serial and different Victron cable
# variants (e.g. "BV") enumerate under different names. Without this step,
# `docker-compose up` fails on any Pi whose hardware doesn't match those two
# strings verbatim.
detect_and_patch_local_devices() {
    local compose_file="$SYSTEM_FOLDER/docker-compose.yml"
    local sparrow_env="$SYSTEM_FOLDER/sparrow.env"
    local starlink_env="$SYSTEM_FOLDER/starlink.env"

    # ---- FTDI (XBee) — patch docker-compose.yml --------------------------
    local actual_ftdi=""
    if [[ -d /dev/serial/by-id ]]; then
        actual_ftdi=$(find /dev/serial/by-id -maxdepth 1 -iname "usb-FTDI_*-if00-port0" -print -quit 2>/dev/null || true)
    fi

    if [[ -n "$actual_ftdi" ]]; then
        if [[ -f "$compose_file" ]]; then
            # If a previous run (with no FTDI plugged in) commented out the xbee_serial
            # mapping, re-enable it now that an adapter is present. Idempotent: no-op if
            # the line is already uncommented.
            if grep -qE '^[[:space:]]*#[[:space:]]*-[[:space:]]*/dev/serial/by-id/usb-FTDI_.*:/dev/xbee_serial[[:space:]]*$' "$compose_file"; then
                log "Re-enabling previously-disabled XBee device mapping"
                sed -i.bak -E 's|^([[:space:]]*)#[[:space:]]*-[[:space:]]*(/dev/serial/by-id/usb-FTDI_[^:[:space:]]+:/dev/xbee_serial)[[:space:]]*$|\1- \2|' "$compose_file"
            fi
            if ! grep -q "$actual_ftdi" "$compose_file"; then
                log "Patching docker-compose.yml FTDI path -> $actual_ftdi"
                sed -i.bak -E "s|/dev/serial/by-id/usb-FTDI_[^:[:space:]]+|$actual_ftdi|g" "$compose_file"
            else
                log "docker-compose.yml already references local FTDI adapter"
            fi
        fi
    else
        log "WARN: no FTDI adapter found; commenting out the XBee device mapping so containers can still start."
        [[ -f "$compose_file" ]] && sed -i.bak -E '/^[[:space:]]*-[[:space:]]*\/dev\/serial\/by-id\/usb-FTDI_.*:\/dev\/xbee_serial[[:space:]]*$/s/^([[:space:]]*)-/\1# -/' "$compose_file"
    fi

    # ---- Victron VE.Direct — patch sparrow.env + starlink.env ------------
    local victron_dev=""
    if [[ -d /dev/serial/by-id ]]; then
        victron_dev=$(find /dev/serial/by-id -maxdepth 1 -iname "usb-VictronEnergy_*-if00-port0" -print -quit 2>/dev/null || true)
    fi

    if [[ -n "$victron_dev" ]]; then
        log "Found local Victron VE.Direct cable: $victron_dev"
        [[ -f "$sparrow_env" ]]  && set_dotenv_kv "$sparrow_env"  VE_DIRECT_PORT "$victron_dev"
        [[ -f "$starlink_env" ]] && set_dotenv_kv "$starlink_env" VE_DIRECT_PORT "$victron_dev"
    else
        log "No Victron VE.Direct cable found; leaving VE_DIRECT_PORT alone (harmless 'port not open' log until a cable is plugged in)."
    fi
}

create_folders() {
    local uh
    uh=$(eval echo ~"${SUDO_USER:-$USER}")
    SYSTEM_FOLDER="$uh/Desktop/system"

    mkdir -p "$SYSTEM_FOLDER/Models/tritonserver/model_repository/megadetectorv6/$MODEL_DIR_NAME"
    mkdir -p "$SYSTEM_FOLDER/Models/tritonserver/model_repository/AI4GAmazonClassification/$AI4G_MODEL_DIR_NAME"
    mkdir -p "$SYSTEM_FOLDER/Models/tritonserver/model_repository/megadetector_birds_v1/$AUDIO_BIRDS_MODEL_DIR_NAME"

    CLONE_DIR="$SYSTEM_FOLDER"

    download_model
    download_model_ai4g
    download_model_audio_birds
    clone_repo
    prompt_robin_usage
    run_xbee_configure_if_needed
}

install_smbus2() {
    python3 -m pip show smbus2 >/dev/null 2>&1 && return
    command_exists pip3 || { apt-get update -y; apt-get install -y python3-pip; }
    python3 -m pip install smbus2
}

###############################################################################
# FTP_PASS
###############################################################################
prompt_ftp_pass() {
    local p1 p2
    while true; do
        p1=$(_input "Enter FTP password (FTP_PASS)" hide)
        p2=$(_input "Re-enter FTP password" hide)

        if [[ -z "${p1:-}" || -z "${p2:-}" ]]; then
            _error "FTP password cannot be empty."
            continue
        fi
        if [[ "$p1" != "$p2" ]]; then
            _error "Passwords do not match. Please try again."
            continue
        fi
        FTP_PASS="$p1"
        break
    done
}

set_dotenv_kv() {
    local file="$1" key="$2" val="$3"
    mkdir -p "$(dirname "$file")"
    [[ -f "$file" ]] || touch "$file"

    local esc
    esc=$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')

    if grep -qE "^${key}=" "$file"; then
        sed -i "s/^${key}=.*/${key}=${esc}/" "$file"
    else
        printf '\n%s=%s\n' "$key" "$val" >>"$file"
    fi
}

find_env_file() {
    if [[ -f "$SYSTEM_FOLDER/.env" ]]; then
        echo "$SYSTEM_FOLDER/.env"; return 0
    fi
    if [[ -f "$SYSTEM_FOLDER/sparrow.env" ]]; then
        echo "$SYSTEM_FOLDER/sparrow.env"; return 0
    fi

    local f
    for f in "$SYSTEM_FOLDER"/*.env "$SYSTEM_FOLDER"/*env; do
        [[ -f "$f" ]] || continue
        if grep -qE '^(TRITON_SERVER_URL|SERVER_BASE_URL|LOCAL_MODELS_DIR|FTP_USER|FTP_PASS)=' "$f"; then
            echo "$f"; return 0
        fi
    done
    return 1
}

configure_ftp_pass_in_env() {
    if ENV_FILE=$(find_env_file); then
        :
    else
        ENV_FILE="$SYSTEM_FOLDER/sparrow.env"
    fi
    [[ -f "$ENV_FILE" ]] || { _error "Env file not found: $ENV_FILE"; return 1; }

    set_dotenv_kv "$ENV_FILE" "FTP_PASS" "$FTP_PASS"
    log "Set FTP_PASS in env file: $ENV_FILE"
}

configure_access_key() {
    local k1 k2
    while true; do
        k1=$(_input "Enter Sparrow Access Key" hide)
        k2=$(_input "Re-enter Sparrow Access Key" hide)
        [[ "$k1" == "$k2" ]] && break
        _error "Keys do not match - try again."
    done
    mkdir -p "$SYSTEM_FOLDER/sparrow/config" "$SYSTEM_FOLDER/starlink/config"
    echo "$k1" >"$SYSTEM_FOLDER/sparrow/config/access_key.txt"
    echo "$k1" >"$SYSTEM_FOLDER/starlink/config/access_key.txt"

    while true; do
        EMAIL=$(_input "Enter Sparrow Email")
        if [[ -z "$EMAIL" ]]; then
            _error "Email cannot be empty - try again."
            continue
        fi
        break
    done
}

onboard_device() {
    local max_retries=5
    local attempt=1
    local hwid api_key resp status_code body access_key_file json_payload

    access_key_file="$SYSTEM_FOLDER/sparrow/config/access_key.txt"

    [[ -f "$access_key_file" ]] || { log "Access key file not found at $access_key_file"; _error "Cannot onboard: access key not found."; return 1; }

    api_key=$(tr -d '\r\n' <"$access_key_file")
    [[ -n "$api_key" ]] || { _error "Access key file is empty; cannot onboard."; return 1; }
    [[ -n "$EMAIL" ]] || { _error "Email is not set in memory; cannot onboard."; return 1; }

    hwid=$(get_hardware_id) || { _error "Cannot compute hardware id for onboarding."; return 1; }

    json_payload=$(printf '{"unit_id":"%s"}' "$hwid")
    log "Onboarding JSON payload (len=${#json_payload}): $json_payload"

    while (( attempt <= max_retries )); do
        log "Onboarding attempt $attempt/$max_retries for unit_id=$hwid (email=$EMAIL)"

        resp=$(curl -sS -w "%{http_code}" \
            -X POST "$ONBOARDING_URL" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: $api_key" \
            -H "X-Email: $EMAIL" \
            --data-binary "$json_payload" 2>/dev/null || true)

        status_code=${resp: -3}
        body=${resp:: -3}

        if [[ "$status_code" == "200" || "$status_code" == "201" ]]; then
            log "Onboarding successful: HTTP $status_code, body: $body"
            _info "Onboarding successful for hardware ID: $hwid"
            return 0
        fi

        log "Onboarding failed (HTTP $status_code): $body"

        if ! _yesno "Onboarding failed (HTTP $status_code). Retry?"; then
            _error "User aborted onboarding."
            return 1
        fi

        attempt=$((attempt+1))
        sleep 2
    done

    _error "Onboarding failed after $max_retries attempts."
    return 1
}

###############################################################################
# Auto-updater
###############################################################################
install_auto_updater() {
    local installer="$SYSTEM_FOLDER/updater/install.sh"
    if [[ ! -f "$installer" ]]; then
        _error "Auto-updater installer not found at $installer; skipping."
        return 1
    fi
    log "Installing SPARROW auto-updater (systemd timer, every 15 min, tag-based)..."
    if bash "$installer"; then
        log "Auto-updater installed and enabled."
    else
        _error "Auto-updater install failed; continuing setup. Re-run manually: sudo bash $installer"
        return 1
    fi
}

###############################################################################
# MAIN
###############################################################################
[ "$EUID" -eq 0 ] || { _error "Run as root (sudo)."; exit 1; }
_install_zenity
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

_info "Welcome to the SPARROW Setup Wizard (Raspberry Pi 5 / Debian Trixie)!\nThis will install prerequisites, download the required models and start SPARROW."

_yesno "Are you running this on a Raspberry Pi 5 (Debian Trixie) with internet access?" \
    || { _error "Please prepare the Pi OS first, then rerun."; exit 1; }

_info "Checking internet connectivity. Press ok to continue"
ping -c3 8.8.8.8 >/dev/null 2>&1 || { _error "No internet connection."; exit 1; }

enable_i2c_pi
if _yesno "Enable DS3231 device-tree overlay (dtoverlay=i2c-rtc,ds3231) in boot config?"; then
    enable_ds3231_overlay_pi
fi

install_wget
install_git
install_curl
install_network_manager

install_wittypi5
detect_wittypi5
configure_wittypi5_auto_power_on
verify_wittypi5_auto_power_on

create_folders
install_uuidgen
generate_unique_id

if command_exists docker && docker compose version >/dev/null 2>&1; then
    log "Docker Engine and Docker Compose already installed."
else
    _progress "Installing Docker Engine + Compose..." install_docker_pi_debian
fi

enable_wifi_radio
prompt_hotspot_password
setup_persistent_wifi_hotspot

prompt_ftp_pass
configure_ftp_pass_in_env

install_smbus2
configure_access_key
onboard_device || log "Onboarding did not complete successfully; continuing setup."

detect_and_patch_local_devices

log "Building Sparrow containers..."
cd "$SYSTEM_FOLDER"

export COMPOSE_DOCKER_CLI_BUILD=1
export DOCKER_BUILDKIT=1

if $GUI && command -v zenity >/dev/null; then
    log "docker compose build (GUI+console) with BuildKit + no-cache started"
    docker_compose_cmd build --no-cache --progress=plain 2>&1 \
      | tee /dev/tty \
      | zenity --progress --pulsate --no-cancel --auto-close \
               --text="Building Docker images (no cache)…" --width=480
    log "docker compose build (GUI+console) with BuildKit + no-cache completed"
else
    log "docker compose build (CLI) with BuildKit + no-cache started"
    docker_compose_cmd build --no-cache --progress=plain
    log "docker compose build (CLI) with BuildKit + no-cache completed"
fi

if $GUI && command -v zenity >/dev/null; then
    log "docker compose up (GUI+console) started"
    docker_compose_cmd up -d 2>&1 \
      | tee /dev/tty \
      | zenity --text-info \
               --title="Starting Sparrow Containers" \
               --width=800 --height=600 \
               --font="Monospace 10"
    log "docker compose up (GUI+console) completed"
else
    _progress "Starting Sparrow.." docker_compose_cmd up -d
    log "Sparrow containers started"
fi

if _yesno "Enable auto-update from GitHub tags (recommended for field deployments)?"; then
    install_auto_updater || log "Auto-updater install did not complete; continuing."
fi

log "Tailing Sparrow logs (Ctrl-C to exit)..."
if $GUI && command -v zenity >/dev/null; then
    docker_compose_cmd logs --no-color --follow \
      | tee /dev/tty \
      | zenity --text-info \
               --title="Sparrow Container Logs" \
               --width=800 --height=600 \
               --font="Monospace 10"
else
    docker_compose_cmd logs --tail=100 --follow
fi

_info "Setup completed - Sparrow is now running!\n\nTo follow logs:\n  cd $SYSTEM_FOLDER && docker compose logs -f"
exit 0
