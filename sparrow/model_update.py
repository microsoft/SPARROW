import os
import sys
import time
import shutil
import logging
import requests
from requests.utils import requote_uri
from utils.sparrow_id import get_hardware_id

# Setup Logging & Folders
LOG_DIR = "/app/logs"
os.makedirs(LOG_DIR, exist_ok=True)
LOG_FILE = os.path.join(LOG_DIR, "model_update.log")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.FileHandler(LOG_FILE), logging.StreamHandler()]
)
log = logging.getLogger(__name__)

# Configuration
SERVER_BASE_URL = os.getenv("SERVER_BASE_URL", "https://server.sparrowstudio.azure.com/v1").rstrip("/")
SERVER_URL = f"{SERVER_BASE_URL}/model_update"
BASE_FILE_URL = SERVER_BASE_URL

HTTP_TIMEOUT = 20
DOWNLOAD_TIMEOUT = 60
SYNC_INTERVAL = int(os.getenv("SYNC_INTERVAL", "60"))

REMOVE_MISSING_MODELS = os.getenv("REMOVE_MISSING_MODELS", "true").strip().lower() in ("1", "true", "yes")

AUTH_KEY_PATH = "/app/config/access_key.txt"
try:
    with open(AUTH_KEY_PATH, "r") as f:
        AUTH_KEY = f.read().strip()
        log.info("Loaded AUTH_KEY")
except Exception as e:
    log.error(f"Failed to read auth key from {AUTH_KEY_PATH}: {e}")
    raise SystemExit(1)

try:
    unit_id = get_hardware_id()
    log.info(f"Generated unit_id: {unit_id}")
except Exception:
    log.critical("Cannot proceed without a valid unit_id.")
    sys.exit(1)

LOCAL_MODELS_DIR = os.environ.get(
    "LOCAL_MODELS_DIR",
    os.path.join(os.path.expanduser("~"), "Desktop", "system", "Models")
)
log.info(f"Local models directory: {LOCAL_MODELS_DIR}")
os.makedirs(LOCAL_MODELS_DIR, exist_ok=True)


def robust_download_file(file_url: str, local_file_path: str):
    """Download to temp file then atomically replace."""
    temp_file_path = local_file_path + ".tmp"
    try:
        os.makedirs(os.path.dirname(local_file_path), exist_ok=True)
        with requests.get(file_url, stream=True, timeout=DOWNLOAD_TIMEOUT) as r:
            r.raise_for_status()
            with open(temp_file_path, "wb") as f:
                for chunk in r.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
        os.replace(temp_file_path, local_file_path)
        log.info(f"Downloaded {file_url} -> {local_file_path}")
    except Exception:
        if os.path.exists(temp_file_path):
            try:
                os.remove(temp_file_path)
            except OSError:
                # Best-effort cleanup of partial download; original exception is re-raised below.
                pass
        raise


def get_model_update():
    payload = {
        "auth_key": AUTH_KEY,
        "unit_id": unit_id,
    }
    try:
        r = requests.post(SERVER_URL, json=payload, timeout=HTTP_TIMEOUT)
        r.raise_for_status()
        data = r.json()
        log.info("Model update data received.")
        return data
    except requests.RequestException as e:
        log.error(f"model_update request failed: {e}")
        return None


def _clean_server_filename(name: str) -> str:
    return name.replace("@SynoEAStream", "")


def _build_server_versions(server_model_details: dict, model: str) -> dict:
    """
    Returns:
        {
            "1": [ {file_info}, {file_info}, ... ],
            "2": [ ... ]
        }
    Only numeric version folders are included.
    """
    versions = {}
    for sub, files in server_model_details.get(model, {}).items():
        if not sub.isdigit():
            continue
        cleaned_files = []
        for file_info in files:
            orig = file_info.get("file_name")
            if not orig:
                continue
            if "Zone.Identifier" in orig:
                continue
            cleaned_files.append(file_info)
        versions[sub] = cleaned_files
    return versions


def sync_models(model_data: dict):
    """
    Mirror the server model structure locally, without Triton.
    Expected local structure:
        LOCAL_MODELS_DIR/<model>/<version>/<files>
    No config.pbtxt is downloaded or managed.
    """
    server_models = set(model_data.get("models", []))
    server_model_details = model_data.get("model_details", {})

    # Sync models listed by server
    for model in server_models:
        local_model_dir = os.path.join(LOCAL_MODELS_DIR, model)
        os.makedirs(local_model_dir, exist_ok=True)

        server_versions = _build_server_versions(server_model_details, model)
        server_version_names = set(server_versions.keys())

        local_version_names = set()
        if os.path.isdir(local_model_dir):
            local_version_names = {
                d for d in os.listdir(local_model_dir)
                if os.path.isdir(os.path.join(local_model_dir, d)) and d.isdigit()
            }

        # Remove version folders not on server
        for version in (local_version_names - server_version_names):
            version_path = os.path.join(local_model_dir, version)
            log.info(f"Removing extra local version: {version_path}")
            shutil.rmtree(version_path, ignore_errors=True)

        # Ensure server versions exist and sync files
        for version, file_infos in server_versions.items():
            local_version_dir = os.path.join(local_model_dir, version)
            os.makedirs(local_version_dir, exist_ok=True)

            server_file_map = {}
            for file_info in file_infos:
                orig = file_info.get("file_name")
                if not orig:
                    continue
                clean_name = _clean_server_filename(orig)
                server_file_map[clean_name] = file_info

            server_file_names = set(server_file_map.keys())

            local_file_names = {
                f for f in os.listdir(local_version_dir)
                if os.path.isfile(os.path.join(local_version_dir, f))
            }

            # Remove extra local files
            for fname in (local_file_names - server_file_names):
                fpath = os.path.join(local_version_dir, fname)
                try:
                    os.remove(fpath)
                    log.info(f"Removed extra file: {fpath}")
                except FileNotFoundError:
                    # File already gone (races with a concurrent cleanup); OK.
                    pass
                except Exception as e:
                    log.warning(f"Failed to remove {fpath}: {e}")

            # Download missing files only
            for fname in (server_file_names - local_file_names):
                file_info = server_file_map[fname]
                furl = file_info.get("url", "")
                if not furl:
                    log.warning(f"Missing URL for {model}/{version}/{fname}")
                    continue

                if not furl.startswith("http"):
                    furl = BASE_FILE_URL + furl

                furl = requote_uri(furl)
                fpath = os.path.join(local_version_dir, fname)

                try:
                    log.info(f"Downloading {model}/{version}/{fname}")
                    robust_download_file(furl, fpath)
                except Exception as e:
                    log.error(f"Failed to download {model}/{version}/{fname}: {e}")

    # Optionally remove local models not listed by server
    if REMOVE_MISSING_MODELS:
        local_models = {
            d for d in os.listdir(LOCAL_MODELS_DIR)
            if os.path.isdir(os.path.join(LOCAL_MODELS_DIR, d))
        }

        for model in (local_models - server_models):
            model_path = os.path.join(LOCAL_MODELS_DIR, model)
            log.info(f"Removing local model not listed by server: {model_path}")
            shutil.rmtree(model_path, ignore_errors=True)


def main_loop():
    while True:
        log.info("Checking server for model updates...")
        data = get_model_update()
        if data:
            try:
                sync_models(data)
            except Exception as e:
                log.error(f"Error during sync: {e}", exc_info=True)
        else:
            log.info("Server unreachable or empty response.")

        log.info(f"Sleeping {SYNC_INTERVAL}s...")
        time.sleep(SYNC_INTERVAL)


if __name__ == "__main__":
    main_loop()
