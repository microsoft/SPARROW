#!/usr/bin/env python3
"""
ONNXRuntime-only inference pipeline (Pi-friendly).

- Runs MegaDetectorV6 (detection) using ONNXRuntime
- For each "animal" detection, crops and runs a classification ONNX model
- Logs to CSV
- Saves JPEG outputs with detection metadata stored as JSON in EXIF UserComment
- Optionally draws boxes on output images (DRAW_BOXES=true/false)

Required env:
  LOCAL_MODELS_DIR  -> root folder containing ONNX models:
      <LOCAL_MODELS_DIR>/megadetectorv6/1/model.onnx
      <LOCAL_MODELS_DIR>/<selected_model>/1/model.onnx

Optional env:
  ONLY_SAVE_ANIMALS=true/false
  DRAW_BOXES=true/false
  SERVER_BASE_URL (defaults to https://server.sparrow-earth.com)
"""

import os
import time
import csv
import json
import logging
import threading
from datetime import datetime

from PIL import Image, ImageFile, ImageDraw, ImageFont
import numpy as np
import torch
import torchvision.transforms as T
import torch.nn.functional as F
import requests
from filelock import FileLock
import piexif  # EXIF metadata

from utils.sparrow_id import get_hardware_id
from utils.detection_utils import non_max_suppression, scale_boxes

# ----------------- ONNXRuntime only -----------------
try:
    import onnxruntime as ort  # type: ignore

    HAVE_ORT = True
except ImportError:
    HAVE_ORT = False
    ort = None

LOCAL_MODELS_DIR = os.getenv("LOCAL_MODELS_DIR", "").strip() or None

# ----------------------------------------------------

# Setup Logging & Folders
LOGS_DIR = "/app/logs"
os.makedirs(LOGS_DIR, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(os.path.join(LOGS_DIR, "inference.log")),
        logging.StreamHandler(),
    ],
)
model_logger = logging.getLogger("model_settings")
log = logging.getLogger("inference")

ONLY_SAVE_ANIMALS = os.getenv("ONLY_SAVE_ANIMALS", "false").strip().lower() == "true"
DRAW_BOXES = os.getenv("DRAW_BOXES", "true").strip().lower() == "true"

# Model Config Sync
CONFIG_DIR = "/app/config"
MODEL_CONFIG_FILE = os.path.join(CONFIG_DIR, "model_settings.json")
MODEL_CONFIG_LOCK = f"{MODEL_CONFIG_FILE}.lock"

SERVER_BASE_URL = os.getenv("SERVER_BASE_URL", "https://server.sparrow-earth.com").rstrip("/")
MODEL_ENDPOINT = f"{SERVER_BASE_URL}/model_settings"
model_logger.info(f"Model settings endpoint: {MODEL_ENDPOINT}")
AUTH_KEY_PATH = "/app/config/access_key.txt"

DEFAULT_MODEL_CONFIG = {
    "selected_model": "AI4GAmazonClassification",
    # NOTE: keeping the original key name "lables" for backward compatibility
    "lables": {
        "0": "Dasyprocta",
        "1": "Bos",
        "2": "Pecari",
        "3": "Mazama",
        "4": "Cuniculus",
        "5": "Leptotila",
        "6": "Human",
        "7": "Aramides",
        "8": "Tinamus",
        "9": "Eira",
        "10": "Crax",
        "11": "Procyon",
        "12": "Capra",
        "13": "Dasypus",
        "14": "Sciurus",
        "15": "Crypturellus",
        "16": "Tamandua",
        "17": "Proechimys",
        "18": "Leopardus",
        "19": "Equus",
        "20": "Columbina",
        "21": "Nyctidromus",
        "22": "Ortalis",
        "23": "Emballonura",
        "24": "Odontophorus",
        "25": "Geotrygon",
        "26": "Metachirus",
        "27": "Catharus",
        "28": "Cerdocyon",
        "29": "Momotus",
        "30": "Tapirus",
        "31": "Canis",
        "32": "Furnarius",
        "33": "Didelphis",
        "34": "Sylvilagus",
        "35": "Unknown",
    },
    "classification_enabled": True,
    "keep_blanks": False,
    "detection_threshold": 0.4,
}

os.makedirs(CONFIG_DIR, exist_ok=True)


def load_model_config():
    """Load model_settings.json (create default if missing)."""
    if not os.path.isfile(MODEL_CONFIG_FILE):
        model_logger.info("No model_settings.json found. Creating default.")
        save_model_config(DEFAULT_MODEL_CONFIG)
        return DEFAULT_MODEL_CONFIG.copy()
    try:
        with FileLock(MODEL_CONFIG_LOCK, timeout=5):
            with open(MODEL_CONFIG_FILE, "r") as f:
                return json.load(f)
    except Exception as e:
        model_logger.error(f"Failed to load model_settings.json: {e}")
        return DEFAULT_MODEL_CONFIG.copy()


def save_model_config(config):
    """Atomically save model_settings.json."""
    tmp_path = f"{MODEL_CONFIG_FILE}.tmp"
    try:
        with FileLock(MODEL_CONFIG_LOCK, timeout=5):
            with open(tmp_path, "w") as f:
                json.dump(config, f, indent=4)
            os.replace(tmp_path, MODEL_CONFIG_FILE)
    except Exception as e:
        model_logger.error(f"Failed to save model_settings.json: {e}")


def fetch_model_settings(unique_id, auth_key):
    """Fetch updated model settings from server; update local file if changed."""
    payload = {"unique_id": unique_id, "auth_key": auth_key}
    headers = {"Content-Type": "application/json"}
    try:
        response = requests.post(MODEL_ENDPOINT, json=payload, headers=headers, timeout=10)
        if response.status_code == 200:
            server_model_config = response.json()
            current_config = load_model_config()
            if server_model_config != current_config:
                model_logger.info("Model settings have changed. Updating local config.")
                save_model_config(server_model_config)
            else:
                model_logger.info("Model settings unchanged.")
        else:
            model_logger.warning(
                f"Model settings fetch failed: {response.status_code} - {response.text}"
            )
    except Exception as e:
        model_logger.warning(f"Could not fetch model settings: {e}")


def model_settings_fetch_loop(unique_id, auth_key):
    """Background thread to periodically fetch model settings."""
    model_logger.info("Started model settings background fetch thread.")
    while True:
        fetch_model_settings(unique_id, auth_key)
        time.sleep(60)


def get_current_model_name():
    return load_model_config().get("selected_model", "AI4GAmazonClassification")


def get_current_labels():
    cfg = load_model_config()
    # accept either "lables" (legacy) or "labels" (if server fixed spelling)
    return cfg.get("lables") or cfg.get("labels") or DEFAULT_MODEL_CONFIG["lables"]


def is_classification_enabled():
    return load_model_config().get("classification_enabled", True)


def is_keep_blanks_enabled():
    return load_model_config().get("keep_blanks", False)


def get_detection_threshold():
    cfg = load_model_config()
    return cfg.get("detection_threshold", DEFAULT_MODEL_CONFIG["detection_threshold"])


# Image & Preprocess Utils
ImageFile.LOAD_TRUNCATED_IMAGES = True


def load_font():
    return ImageFont.load_default()


def letterbox(im, new_shape=(640, 640), auto=False, scaleFill=False, scaleup=True, stride=32):
    """Resize and pad image to meet stride-multiple constraints."""
    if isinstance(im, Image.Image):
        im = T.ToTensor()(im)
    shape = im.shape[1:]  # [height, width]
    if isinstance(new_shape, int):
        new_shape = (new_shape, new_shape)
    r = min(new_shape[0] / shape[0], new_shape[1] / shape[1])
    if not scaleup:
        r = min(r, 1.0)
    new_unpad = (int(round(shape[1] * r)), int(round(shape[0] * r)))
    dw, dh = new_shape[1] - new_unpad[0], new_shape[0] - new_unpad[1]
    if auto:
        dw, dh = dw % stride, dh % stride
    elif scaleFill:
        dw, dh = 0, 0
        new_unpad = new_shape
        r = (new_shape[1] / shape[1], new_shape[0] / shape[0])
    dw /= 2
    dh /= 2
    if shape[::-1] != new_unpad:
        resize_transform = T.Resize(
            new_unpad[::-1],
            interpolation=T.InterpolationMode.BILINEAR,
            antialias=False,
        )
        im = resize_transform(im)
    padding = (
        int(round(dw - 0.1)),
        int(round(dw + 0.1)),
        int(round(dh + 0.1)),
        int(round(dh - 0.1)),
    )
    im = F.pad(im * 255.0, padding, value=114) / 255.0
    return im


# MegaDetector classes
class_name_to_id = {0: "animal", 1: "person", 2: "vehicle"}
colors = ["red", "blue", "purple"]


def preprocess_classification(img):
    """Preprocess PIL image for classification -> numpy [1,3,224,224] FP32."""
    img = img.resize((224, 224))
    img_tensor = T.ToTensor()(img)
    img_np = img_tensor.numpy()
    img_np = np.expand_dims(img_np, axis=0).astype(np.float32)
    return img_np


# --------- ONNX inference wrappers (only) ----------
md_ort_session = None
clf_ort_sessions = {}  # model_name -> session


def _ensure_ort_ready() -> bool:
    if not HAVE_ORT or ort is None:
        log.error("onnxruntime is not installed. Cannot run inference.")
        return False
    if not LOCAL_MODELS_DIR:
        log.error("LOCAL_MODELS_DIR is not set. Cannot locate ONNX models.")
        return False
    return True


def _get_megadetector_onnx_session():
    global md_ort_session
    if md_ort_session is not None:
        return md_ort_session
    if not _ensure_ort_ready():
        return None
    md_path = os.path.join(LOCAL_MODELS_DIR, "megadetectorv6", "1", "model.onnx")
    if not os.path.isfile(md_path):
        log.error(f"MegaDetector ONNX model not found at: {md_path}")
        return None
    log.info(f"Loading MegaDetector ONNX model from {md_path}")
    md_ort_session = ort.InferenceSession(md_path, providers=["CPUExecutionProvider"])
    return md_ort_session


def _get_classifier_onnx_session(model_name: str):
    global clf_ort_sessions
    if model_name in clf_ort_sessions:
        return clf_ort_sessions[model_name]
    if not _ensure_ort_ready():
        return None
    clf_path = os.path.join(LOCAL_MODELS_DIR, model_name, "1", "model.onnx")
    if not os.path.isfile(clf_path):
        log.error(f"Classifier ONNX model not found at: {clf_path}")
        return None
    log.info(f"Loading classifier ONNX model '{model_name}' from {clf_path}")
    sess = ort.InferenceSession(clf_path, providers=["CPUExecutionProvider"])
    clf_ort_sessions[model_name] = sess
    return sess


def run_megadetector(image_np: np.ndarray):
    """Run MegaDetector with ONNXRuntime. Returns output ndarray or None."""
    sess = _get_megadetector_onnx_session()
    if sess is None:
        return None
    try:
        input_name = sess.get_inputs()[0].name
        outputs = sess.run(None, {input_name: image_np.astype(np.float32)})
        return outputs[0]
    except Exception as e:
        log.error(f"ONNX MegaDetector inference failed: {e}")
        return None


def run_classifier(cropped_np: np.ndarray, model_name: str):
    """Run classifier with ONNXRuntime. Returns 1D probs or None."""
    sess = _get_classifier_onnx_session(model_name)
    if sess is None:
        return None
    try:
        input_name = sess.get_inputs()[0].name
        outputs = sess.run(None, {input_name: cropped_np.astype(np.float32)})
        logits = outputs[0][0].astype(np.float32, copy=False)
        exp_scores = np.exp(logits - np.max(logits))
        probs = exp_scores / np.sum(exp_scores)
        return probs
    except Exception as e:
        log.error(f"ONNX classifier '{model_name}' inference failed: {e}")
        return None


# ------------------------------------------------------

# Input and output directories
input_dir = "/app/images/"
output_dir = "/app/static/gallery/"
os.makedirs(output_dir, exist_ok=True)

# CSV for logging detections
csv_file = "/app/static/data/detections.csv"
os.makedirs(os.path.dirname(csv_file), exist_ok=True)


def write_to_csv(image_name, detection, confidence, date):
    file_exists = os.path.isfile(csv_file)
    with open(csv_file, mode="a", newline="") as file:
        writer = csv.writer(file)
        if not file_exists:
            writer.writerow(["Image Name", "Detection", "Confidence Score", "Date"])
        writer.writerow([image_name, detection, confidence, date])


def save_jpeg_with_boxes(img, boxes_meta, out_path):
    """Save JPEG with boxes metadata stored as JSON in EXIF UserComment."""
    exif_bytes_in = img.info.get("exif", b"")
    if exif_bytes_in:
        try:
            exif_dict = piexif.load(exif_bytes_in)
        except Exception:
            exif_dict = {"0th": {}, "Exif": {}, "GPS": {}, "1st": {}, "thumbnail": None}
    else:
        exif_dict = {"0th": {}, "Exif": {}, "GPS": {}, "1st": {}, "thumbnail": None}

    payload = json.dumps(boxes_meta).encode("utf-8")
    exif_dict["Exif"][piexif.ExifIFD.UserComment] = b"ASCII\0\0\0" + payload
    exif_bytes_out = piexif.dump(exif_dict)
    img.save(out_path, format="JPEG", exif=exif_bytes_out)


# Background Settings Fetch
try:
    with open(AUTH_KEY_PATH, "r") as f:
        AUTH_KEY = f.read().strip()
except Exception as e:
    model_logger.error(f"Failed to read auth key: {e}")
    AUTH_KEY = None

try:
    UNIQUE_ID = get_hardware_id()
    model_logger.info(f"Hardware ID loaded: {UNIQUE_ID}")
except Exception as e:
    model_logger.error(f"Failed to get hardware ID: {e}")
    UNIQUE_ID = None

if AUTH_KEY and UNIQUE_ID:
    model_thread = threading.Thread(
        target=model_settings_fetch_loop,
        args=(UNIQUE_ID, AUTH_KEY),
        daemon=True,
    )
    model_thread.start()

log.info(
    f"ONNXRuntime-only mode. HAVE_ORT={HAVE_ORT}, LOCAL_MODELS_DIR={LOCAL_MODELS_DIR}, "
    f"ONLY_SAVE_ANIMALS={ONLY_SAVE_ANIMALS}, DRAW_BOXES={DRAW_BOXES}"
)

# Main Processing Loop
while True:
    try:
        names = os.listdir(input_dir)
    except Exception as e:
        log.error(f"Failed to list input_dir={input_dir}: {e}")
        time.sleep(5)
        continue

    for image_name in names:
        if not image_name.lower().endswith((".png", ".jpg", ".jpeg")):
            continue

        image_path = os.path.join(input_dir, image_name)
        log.info(f"Processing: {image_path}")

        # Try opening a few times (handles files still being written)
        attempt = 0
        image = None
        while attempt < 3:
            if attempt != 0:
                time.sleep(5)
            try:
                image = Image.open(image_path).convert("RGB")
                break
            except Exception as e:
                log.warning(f"Open failed (attempt {attempt+1}/3) for {image_path}: {e}")
                attempt += 1

        if image is None:
            try:
                os.remove(image_path)
                log.warning(f"Removed {image_path} without processing (could not open).")
            except Exception as e:
                log.error(f"Failed to remove {image_path}: {e}")
            continue

        # Prepare image for MegaDetector
        img_lb = letterbox(image, new_shape=(640, 640), auto=False, stride=32)
        image_np = img_lb.numpy()
        image_np = np.expand_dims(image_np, axis=0).astype(np.float32)

        # MegaDetector inference
        output_data = run_megadetector(image_np)
        if output_data is None:
            log.error(f"MegaDetector inference failed for {image_name}; treating as blank.")
            try:
                date_str = image_name.split("_")[-1].split(".")[0][:14]
                date = datetime.strptime(date_str, "%Y%m%d%H%M%S")
            except Exception:
                date = datetime.utcnow()

            if is_keep_blanks_enabled():
                write_to_csv(image_name, "blank", 0.0, date)
                image.save(os.path.join(output_dir, image_name))
                log.info(f"Saved blank image to {output_dir}")

            try:
                os.remove(image_path)
            except Exception as e:
                log.error(f"Failed to remove {image_path}: {e}")
            continue

        # Extract datetime from filename
        try:
            date_str = image_name.split("_")[-1].split(".")[0][:14]
            date = datetime.strptime(date_str, "%Y%m%d%H%M%S")
        except Exception:
            date = datetime.utcnow()

        # Non-max suppression
        conf_thres = get_detection_threshold()
        try:
            pred = non_max_suppression(
                torch.tensor(output_data),
                conf_thres=conf_thres,
                iou_thres=0.5,
                agnostic=False,
            )[0].numpy()
        except Exception as e:
            log.error(f"NMS failed for {image_name}: {e}")
            pred = np.array([])

        # Handle blank
        if pred.size == 0:
            if is_keep_blanks_enabled():
                write_to_csv(image_name, "blank", 1.0, date)
                image.save(os.path.join(output_dir, image_name))
                log.info(f"Saved blank image to {output_dir}")
            try:
                os.remove(image_path)
            except Exception as e:
                log.error(f"Failed to remove {image_path}: {e}")
            continue

        # Scale boxes back to original image size
        pred[:, :4] = scale_boxes([640, 640], pred[:, :4], np.array(image).shape)

        xyxy = pred[:, :4]
        md_confidence = pred[:, 4]
        md_class_id = pred[:, 5].astype(int)

        font = load_font()
        drew_any = False
        skipped_count = 0

        boxes_meta = []
        img_w, img_h = image.size

        annotated_img = image.copy() if DRAW_BOXES else image
        draw = ImageDraw.Draw(annotated_img) if DRAW_BOXES else None

        for i in range(len(pred)):
            cls_id = int(md_class_id[i])

            if ONLY_SAVE_ANIMALS and cls_id in (1, 2):
                skipped_count += 1
                continue

            md_label = class_name_to_id.get(cls_id, "unknown")
            det_conf = float(md_confidence[i])
            x1, y1, x2, y2 = [float(v) for v in xyxy[i]]

            # Run classification only for animals if enabled
            if cls_id == 0 and is_classification_enabled():
                cropped = image.crop((x1, y1, x2, y2))
                cropped_np = preprocess_classification(cropped)

                current_model_name = get_current_model_name()
                probs = run_classifier(cropped_np, current_model_name)

                if probs is None or probs.size == 0:
                    detected_class = md_label
                    clf_conf = det_conf
                    stored_model = None
                else:
                    pred_class = int(np.argmax(probs))
                    clf_conf = float(np.max(probs))
                    labels_dict = get_current_labels()
                    detected_class = labels_dict.get(str(pred_class), "Unknown")
                    if clf_conf < 0.8:
                        detected_class = "Unknown"
                    stored_model = current_model_name

                write_to_csv(image_name, detected_class, clf_conf, date)
                label_text = f"{detected_class} {clf_conf:.2f}"

                stored_label = detected_class
                stored_conf = clf_conf
            else:
                # Person/vehicle, or classification disabled
                write_to_csv(image_name, md_label, det_conf, date)
                label_text = f"{md_label} {det_conf:.2f}"

                stored_label = md_label
                stored_conf = det_conf
                stored_model = None

            # Optionally draw
            if DRAW_BOXES and draw is not None:
                draw.rectangle([x1, y1, x2, y2], outline=colors[cls_id] if cls_id in (0, 1, 2) else "white", width=2)
                text_bbox = draw.textbbox((x1, y1 - 20), label_text, font=font)
                draw.rectangle(
                    [text_bbox[0], text_bbox[1] - 2, text_bbox[2] + 2, text_bbox[3] + 2],
                    fill=colors[cls_id] if cls_id in (0, 1, 2) else "black",
                )
                draw.text((x1 + 2, y1 - 20), label_text, font=font, fill="white")

            drew_any = True

            # Store normalized coordinates + label in metadata list
            norm_x1 = x1 / float(img_w)
            norm_y1 = y1 / float(img_h)
            norm_x2 = x2 / float(img_w)
            norm_y2 = y2 / float(img_h)

            boxes_meta.append(
                {
                    "x1": float(norm_x1),
                    "y1": float(norm_y1),
                    "x2": float(norm_x2),
                    "y2": float(norm_y2),
                    "label": stored_label,
                    "score": float(stored_conf),
                    "class_id": int(cls_id),
                    "source": "megadetectorv6",
                    "model": stored_model,
                }
            )

        if ONLY_SAVE_ANIMALS and skipped_count:
            log.info(f"{image_name}: skipped {skipped_count} non-animal detection(s) due to ONLY_SAVE_ANIMALS")

        # If we filtered everything out, treat as blank
        if not drew_any:
            if is_keep_blanks_enabled():
                write_to_csv(image_name, "blank", 1.0, date)
                image.save(os.path.join(output_dir, image_name))
                log.info(f"Saved blank image to {output_dir}")
            try:
                os.remove(image_path)
            except Exception as e:
                log.error(f"Failed to remove {image_path}: {e}")
            continue

        # Save output image
        out_path = os.path.join(output_dir, image_name)
        img_to_save = annotated_img if DRAW_BOXES else image

        try:
            if image_name.lower().endswith((".jpg", ".jpeg")):
                save_jpeg_with_boxes(img_to_save, boxes_meta, out_path)
            else:
                img_to_save.save(out_path)
        except Exception as e:
            log.error(f"Failed to save output image {out_path}: {e}")

        # Remove original after processing
        try:
            os.remove(image_path)
        except Exception as e:
            log.error(f"Failed to remove {image_path}: {e}")

    # Check new images every 10s
    time.sleep(10)
