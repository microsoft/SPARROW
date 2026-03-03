#!/usr/bin/env bash
###############################################################################
#  SPARROW Setup Script (Raspberry Pi 5 / Debian Trixie)    03-March-2026
#  - Keeps Triton model repository layout exactly as before
#  - Uses Debian Docker packages + Compose v2 plugin (docker compose)
#  - Enables I2C (+ optional DS3231 overlay) via boot config
#  - Removes TeamViewer install
###############################################################################
set -euo pipefail

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

_yesno() {               # returns 0 (true) for Yes / OK
    if $GUI && command -v zenity >/dev/null 2>&1; then
        zenity --question --no-wrap --text="$1" --width=440
    else
        read -rp "$1 (y/n): " _ans; [[ "${_ans,,}" =~ ^y(es)?$ ]]
    fi
}

_input() {               # $1 prompt , $2 = "hide" to mask
    if $GUI && command -v zenity >/dev/null 2>&1; then
        local opts=(--entry --text="$1" --width=460)
        [[ "${2:-}" == "hide" ]] && opts+=(--hide-text)
        zenity "${opts[@]}"
    else
        if [[ "${2:-}" == "hide" ]]; then
            read -rsp "$1: " _txt; echo; echo "$_txt"
        else
            read -rp "$1: " _txt; echo "$_txt"
        fi
    fi
}

_info()  { $GUI && command -v zenity >/dev/null 2>&1 && zenity --info  --no-wrap --text="$*" --width=480 || echo -e "$*"; }
_error() { $GUI && command -v zenity >/dev/null 2>&1 && zenity --error --no-wrap --text="$*" --width=480 || { echo -e "ERROR: $*" >&2; } }

_progress() {            # $1 = message, $2… = command
    if $GUI && command -v zenity >/dev/null 2>&1; then
        ( "${@:2}" ) 2>&1 | zenity --progress --pulsate --no-cancel \
                                    --auto-close --text="$1" --width=480
    else
        "${@:2}"
    fi
}

###############################################################################
# 1.  -- CONFIGURATION --
###############################################################################
LOG_FILE="/var/log/sparrow_setup.log"
UUID_FILE="/etc/unique_id"

HOTSPOT_SSID="CameraTraps"
HOTSPOT_PASSWORD=""        # set interactively via prompt_hotspot_password
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

REPO_URL="https://github.com/microsoft/sparrow-client"
CLONE_DIR=""

ONBOARDING_URL="https://server.sparrow-earth.com/onboarding"
USERNAME=""

# ENV / FTP
ENV_FILE=""
FTP_PASS=""

# I2C / DS3231
I2C_BUS="1"     # Raspberry Pi typically uses /dev/i2c-1
DS3231_ADDR="0x68"

###############################################################################
# 2.  -- UTILITY FUNCTIONS --
###############################################################################
log() { echo -e "$(date +"%Y-%m-%d %H:%M:%S") : $*" | tee -a "$LOG_FILE"; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

install_uuidgen() {
    if command_exists uuidgen; then
        log "uuidgen already installed."
    else
        mkdir -p /run/uuidd && chmod 755 /run/uuidd
        apt-get update -y && apt-get install -y uuid-runtime
    fi
}

generate_unique_id() {
    [[ -s "$UUID_FILE" ]] && { log "UUID exists: $(cat "$UUID_FILE")"; return; }
    local NEW_UUID
    NEW_UUID=$(uuidgen)
    echo "$NEW_UUID" | tee "$UUID_FILE" >/dev/null
    chmod 644 "$UUID_FILE"; chown root:root "$UUID_FILE"
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
# Docker / Compose (Pi / Debian Trixie)
###############################################################################
install_docker_pi_debian() {
    apt-get update -y
    apt-get install -y docker.io docker-compose-plugin
    systemctl enable --now docker
}

docker_compose_cmd() {
    docker compose "$@"
}

###############################################################################
# NetworkManager (for nmcli hotspot)
###############################################################################
install_network_manager() {
    command_exists nmcli && return
    apt-get update -y
    apt-get install -y network-manager
    systemctl enable --now NetworkManager
}

###############################################################################
# I2C enablement (Pi)
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
# Models + repo (Triton layout preserved exactly)
###############################################################################
download_model() {
    local dir="$SYSTEM_FOLDER/Models/tritonserver/model_repository/megadetectorv6/$MODEL_DIR_NAME"
    local tmp="$dir/$MODEL_FILENAME_TEMP" fin="$dir/$MODEL_FILENAME_FINAL"
    mkdir -p "$dir"
    while true; do
        if _progress "Downloading Megadetector v6..." wget -q -O "$tmp" "$MODEL_DOWNLOAD_URL"; then
            mv "$tmp" "$fin"; break
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
            mv "$tmp" "$fin"; break
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
            mv "$tmp" "$fin"; break
        fi
        _yesno "Audio Birds model download failed. Retry?" || { _error "Aborted."; exit 1; }
    done
}

clone_public_repo() {
    CLONE_DIR="$SYSTEM_FOLDER"
    local tmpdir
    tmpdir="$(mktemp -d)"
    _progress "Cloning repo..." git clone "$REPO_URL" "$tmpdir"
    (
      shopt -s dotglob
      cp -a "$tmpdir"/* "$CLONE_DIR"/
    )
    rm -rf "$tmpdir"
    create_additional_directories
}

create_additional_directories() {
    mkdir -p "$SYSTEM_FOLDER/sparrow"/{logs,images,recordings,static/data,static/gallery,config}
    mkdir -p "$SYSTEM_FOLDER/starlink"/{logs,config}
}

create_folders() {
    local uh
    uh=$(eval echo ~"${SUDO_USER:-$USER}")
    SYSTEM_FOLDER="$uh/Desktop/system"
    mkdir -p "$SYSTEM_FOLDER/Models/tritonserver/model_repository/megadetectorv6/$MODEL_DIR_NAME"
    mkdir -p "$SYSTEM_FOLDER/Models/tritonserver/model_repository/AI4GAmazonClassification/$AI4G_MODEL_DIR_NAME"
    mkdir -p "$SYSTEM_FOLDER/Models/tritonserver/model_repository/megadetector_birds_v1/$AUDIO_BIRDS_MODEL_DIR_NAME"
    CLONE_DIR="$SYSTEM_FOLDER"

# config.pbtxt - Megadetector
cat >"$SYSTEM_FOLDER/Models/tritonserver/model_repository/megadetectorv6/config.pbtxt" <<'EOF'
name: "megadetectorv6"
platform: "onnxruntime_onnx"
max_batch_size: 0

input [
  {
    name: "images"
    data_type: TYPE_FP32
    dims: [1, 3, 640, 640]
  }
]

output [
  {
    name: "output0"
    data_type: TYPE_FP32
    dims: [-1, -1, -1]
  }
]

parameters {
  key: "intra_op_num_threads"
  value: { string_value: "2" }
}
parameters {
  key: "inter_op_num_threads"
  value: { string_value: "2" }
}
parameters {
  key: "execution_mode"
  value: { string_value: "1" }   # 1=parallel, 0=sequential
}
parameters {
  key: "enable_cpu_mem_arena"
  value: { string_value: "1" }
}
parameters {
  key: "enable_mem_pattern"
  value: { string_value: "1" }
}

instance_group [
  {
    kind: KIND_GPU
    gpus: [0]
    count: 1
  }
]
EOF

# config.pbtxt - AI4G Amazon Classificaion Model
cat >"$SYSTEM_FOLDER/Models/tritonserver/model_repository/AI4GAmazonClassification/config.pbtxt" <<'EOF'
name: "AI4GAmazonClassification"
platform: "onnxruntime_onnx"
max_batch_size: 0

input [
  {
    name: "input"
    data_type: TYPE_FP32
    dims: [-1, 3, 224, 224]
  }
]

output [
  {
    name: "output"
    data_type: TYPE_FP32
    dims: [-1, 36]
  }
]

parameters {
  key: "intra_op_num_threads"
  value: { string_value: "2" }
}
parameters {
  key: "inter_op_num_threads"
  value: { string_value: "2" }
}
parameters {
  key: "execution_mode"
  value: { string_value: "1" }   # 1=parallel, 0=sequential
}
parameters {
  key: "enable_cpu_mem_arena"
  value: { string_value: "1" }
}
parameters {
  key: "enable_mem_pattern"
  value: { string_value: "1" }
}

instance_group [
  {
    kind: KIND_GPU
    gpus: [0]
    count: 1
  }
]
EOF

# config.pbtxt - MD Audio Birds v1
cat >"$SYSTEM_FOLDER/Models/tritonserver/model_repository/megadetector_birds_v1/config.pbtxt" <<'EOF'
name: "megadetector_birds_v1"
backend: "onnxruntime"
max_batch_size: 32

input [
  {
    name: "input"
    data_type: TYPE_FP32
    dims: [1, 224, -1]
  }
]

output [
  {
    name: "logits"
    data_type: TYPE_FP32
    dims: [1]
  }
]

parameters {
  key: "intra_op_num_threads"
  value: { string_value: "2" }
}
parameters {
  key: "inter_op_num_threads"
  value: { string_value: "2" }
}
parameters {
  key: "execution_mode"
  value: { string_value: "1" }   # 1 = parallel, 0 = sequential
}
parameters {
  key: "enable_cpu_mem_arena"
  value: { string_value: "1" }
}
parameters {
  key: "enable_mem_pattern"
  value: { string_value: "1" }
}

instance_group [
  {
    kind: KIND_GPU
    gpus: [0]
    count: 1
  }
]
EOF

    download_model
    download_model_ai4g
    download_model_audio_birds
    clone_public_repo
}

install_smbus2() {
    python3 -m pip show smbus2 >/dev/null 2>&1 && return
    command_exists pip3 || { apt-get update -y; apt-get install -y python3-pip; }
    python3 -m pip install smbus2
}

###############################################################################
# 2b. -- FTP_PASS PROMPT + .env UPDATE --
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

###############################################################################
# 3.  -- DS3231 RTC SEED --
###############################################################################
seed_ds3231() {
    log "Seeding DS3231 RTC with current UTC time..."
    local max_retries=5
    local attempt=1
    local current_time=""

    while [ $attempt -le $max_retries ]; do
        log "Attempt $attempt/$max_retries: fetching UTC from World Clock API..."
        raw=$(curl -sL http://worldclockapi.com/api/json/utc/now || true)
        current_time=$(echo "${raw:-}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("currentDateTime",""))' 2>/dev/null || true)

        if [ -n "${current_time:-}" ]; then
            current_time=$(echo "$current_time" | sed 's/T/ /; s/Z//'):00
            log "Retrieved UTC time from API: $current_time"
            break
        fi

        log "World Clock API fetch failed on attempt $attempt."
        attempt=$((attempt+1))
        sleep 2
    done

    if [ -z "${current_time:-}" ]; then
        log "World Clock API failed after $max_retries attempts. Falling back to system time (UTC)."
        current_time=$(date -u +"%Y-%m-%d %H:%M:%S")
        log "Using local UTC time: $current_time"
    fi

    local write_attempts=1
    while [ $write_attempts -le $max_retries ]; do
        if python3 - <<EOF
import smbus2
from datetime import datetime

rtc = datetime.strptime("$current_time", "%Y-%m-%d %H:%M:%S")
int_to_bcd = lambda v: ((v // 10) << 4) | (v % 10)

bus = smbus2.SMBus(int("$I2C_BUS"))
DS3231_ADDR = int("$DS3231_ADDR", 16)

data = [
    int_to_bcd(rtc.second),
    int_to_bcd(rtc.minute),
    int_to_bcd(rtc.hour),
    int_to_bcd((rtc.isoweekday() % 7) + 1),
    int_to_bcd(rtc.day),
    int_to_bcd(rtc.month),
    int_to_bcd(rtc.year - 2000)
]
bus.write_i2c_block_data(DS3231_ADDR, 0x00, data)
bus.close()
EOF
        then
            log "DS3231 time set to: $current_time"
            return
        else
            log "DS3231 write failed on attempt $write_attempts."
            if [ $write_attempts -lt $max_retries ]; then
                if _yesno "Seeding failed. Retry write?" ; then
                    :
                else
                    log "User aborted DS3231 seeding during write."
                    echo "Automatic DS3231 RTC Failed!! Please manually seed the DS3231 RTC before running Docker Compose!!"
                    return
                fi
            fi
            write_attempts=$((write_attempts+1))
            sleep 2
        fi
    done

    log "Exceeded maximum retries ($max_retries) for DS3231 seeding."
    echo "Automatic DS3231 RTC Failed!! Please manually seed the DS3231 RTC before running Docker Compose!!"
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
        USERNAME=$(_input "Enter Sparrow Username")
        if [[ -z "$USERNAME" ]]; then
            _error "Username cannot be empty - try again."
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
    [[ -n "$USERNAME" ]] || { _error "Username is not set in memory; cannot onboard."; return 1; }

    hwid=$(get_hardware_id) || { _error "Cannot compute hardware id for onboarding."; return 1; }

    json_payload=$(printf '{"unit_id":"%s"}' "$hwid")
    log "Onboarding JSON payload (len=${#json_payload}): $json_payload"

    while (( attempt <= max_retries )); do
        log "Onboarding attempt $attempt/$max_retries for unit_id=$hwid (username=$USERNAME)"

        resp=$(curl -sS -w "%{http_code}" \
            -X POST "$ONBOARDING_URL" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: $api_key" \
            -H "X-Username: $USERNAME" \
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
# 4.  -- MAIN SCRIPT LOGIC --
###############################################################################
[ "$EUID" -eq 0 ] || { _error "Run as root (sudo)."; exit 1; }
_install_zenity
touch "$LOG_FILE"; chmod 644 "$LOG_FILE"

_info "Welcome to the SPARROW Setup Wizard (Raspberry Pi 5 / Debian Trixie)!\nThis will install prerequisites, download the required models and start SPARROW."

_yesno "Are you running this on a Raspberry Pi 5 (Debian Trixie) with internet access?" \
    || { _error "Please prepare the Pi OS first, then rerun."; exit 1; }

_info "Checking internet connectivity. Press ok to continue"
ping -c3 8.8.8.8 >/dev/null 2>&1 || { _error "No internet connection."; exit 1; }

# Ensure I2C (and optionally DS3231 overlay) is enabled BEFORE smbus use
enable_i2c_pi
if _yesno "Enable DS3231 device-tree overlay (dtoverlay=i2c-rtc,ds3231) in boot config?"; then
    enable_ds3231_overlay_pi
fi

install_wget
install_git
install_curl

# NetworkManager is required for nmcli hotspot approach
install_network_manager

create_folders
install_uuidgen
generate_unique_id

if command_exists docker; then
    log "Docker already installed."
else
    _progress "Installing Docker + Compose (Debian packages)..." install_docker_pi_debian
fi

# prompt for hotspot password before configuring Wi-Fi AP
prompt_hotspot_password
setup_persistent_wifi_hotspot

# prompt for FTP_PASS and write it into the env file before containers run
prompt_ftp_pass
configure_ftp_pass_in_env

install_smbus2
seed_ds3231
configure_access_key
onboard_device || log "Onboarding did not complete successfully; continuing setup."

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

# 1) Start in detached mode
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

# 2) Follow the logs in real time
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