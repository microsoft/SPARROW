---
description: "SPARROW software setup — one-click Jetson setup script, Docker Compose architecture, NVIDIA Triton inference server, MegaDetector ONNX models, and SPARROW dashboard configuration."
tags:
  - SPARROW
  - software-setup
  - docker
  - jetson
  - triton-inference-server
  - megadetector
  - onnx
  - installation
---

# Software Setup

SPARROW runs entirely in Docker containers orchestrated by Docker Compose. This page covers how to configure and launch the SPARROW software stack on a Jetson Orin Nano.

New to SPARROW? The [Getting Started](getting-started.md) guide places this software step in the full build-to-deploy sequence.

---

## Prerequisites

- Jetson Orin Nano with **JetPack 6.x** installed and flashed
- Hardware assembled per the [Hardware Setup](hardware.md) guide
- SPARROW dashboard account and access key — register at [dashboard.sparrow-earth.com](https://dashboard.sparrow-earth.com/)

---

## One-Click Setup (Recommended)

The `sparrow_setup.sh` script in the `setup script/` directory automates the entire Jetson configuration in a single command.

**Run from `~/Desktop`:**

```bash
cd ~/Desktop
sudo chmod +x sparrow_setup.sh
sudo ./sparrow_setup.sh
```

### What the script does

| Step | Action |
|---|---|
| **1. Prerequisites** | Installs `docker`, `docker-compose`, `git`, `curl`, `wget`, `uuidgen`, `smbus2` |
| **2. Device identity** | Generates `/etc/unique_id` (UUID) if missing |
| **3. Folder layout** | Creates `~/Desktop/system/` with all required directories (see below) |
| **4. Models** | Downloads three default ONNX models from Zenodo; writes Triton `config.pbtxt` |
| **5. Access key** | Prompts for your SPARROW dashboard access key; writes to `sparrow/config/access_key.txt` and `starlink/config/access_key.txt` |
| **6. RTC seeding** | Gets UTC from WorldClock API (fallback: NTP) and writes to DS3231 RTC over I²C bus 7 |
| **7. Wi-Fi hotspot** | Configures a persistent `NetworkManager` hotspot on the Jetson for camera trap connectivity |
| **8. Docker build + launch** | Builds images with BuildKit (no cache), runs `docker-compose up -d`, tails logs |

### Deployed folder structure

```
~/Desktop/system/
├── docker-compose.yml
├── sparrow_setup.sh
├── Models/
│   └── tritonserver/
│       └── model_repository/
│           ├── megadetectorv6/          ← MegaDetector v6 ONNX
│           │   ├── 1/model.onnx
│           │   └── config.pbtxt
│           ├── AI4GAmazonClassification/ ← Amazon species classifier ONNX
│           │   ├── 1/model.onnx
│           │   └── config.pbtxt
│           └── megadetector_birds_v1/   ← Bird detector ONNX
│               ├── 1/model.onnx
│               └── config.pbtxt
├── sparrow/
│   ├── Dockerfile
│   ├── config/access_key.txt
│   ├── images/
│   ├── recordings/
│   ├── logs/
│   └── static/data/ static/gallery/
└── starlink/
    ├── Dockerfile.starlink
    ├── config/access_key.txt
    └── logs/
```

---

## AI Models

SPARROW uses NVIDIA Triton Inference Server to run ONNX models on the Jetson's GPU. Three models are deployed by default:

| Model | Purpose |
|---|---|
| `megadetectorv6` | Detects animals, people, and vehicles in camera trap images ([MegaDetector](https://github.com/microsoft/MegaDetector)) |
| `AI4GAmazonClassification` | Species classification for Amazon Basin wildlife |
| `megadetector_birds_v1` | Bird-specific detector optimized for acoustic + visual monitoring |

All models are downloaded as ONNX format and served via Triton's gRPC/HTTP endpoints on ports 8000–8002.

---

## Docker Services

Two containers run on the Jetson:

### `sparrow`

The main SPARROW service — handles:
- **Camera trap management** — WiFi camera polling, image download, deduplication
- **On-device inference** — submits images to Triton for MegaDetector detection + species classification
- **Power management** — monitors solar charge controller, battery state, dynamic component scheduling
- **Telemetry** — environmental sensor readings (BME688, SHTC3), system health metrics
- **Data sync** — FTP/HTTP upload to SPARROW dashboard when connectivity is available
- **Privacy scrubbing** — removes human-related images before upload

### `starlink`

Monitors Starlink satellite connectivity via gRPC, logs signal metrics, and triggers data sync when uplink is available.

---

## Environment Configuration

The `sparrow.env` and `starlink.env` files in the repo root are **configuration templates**. The setup script fills in deployment-specific values (access key, FTP password). Key variables:

| Variable | Purpose |
|---|---|
| `SERVER_BASE_URL` | SPARROW dashboard API endpoint |
| `FTP_PASS` | FTP upload credential (prompted during setup) |
| `UNIQUE_ID_PATH` | Path to device UUID (`/host/etc/unique_id`) |

!!! warning
    Never commit `.env` files containing real credentials. The `.gitignore` already excludes all `.env` files.

---

## Manual Launch (Advanced)

To launch without the setup script (assumes folder structure already exists):

```bash
cd ~/Desktop/system
docker compose up -d
```

View logs:

```bash
docker compose logs -f
```

Restart a specific service:

```bash
docker compose restart sparrow
```

---

## SPARROW Dashboard

Data collected and processed by SPARROW is uploaded to the [SPARROW Dashboard](https://dashboard.sparrow-earth.com/) for visualization, filtering, and export.

- Register for an account and obtain your access key at [dashboard.sparrow-earth.com](https://dashboard.sparrow-earth.com/)
- Dashboard Terms & Conditions: [sparrow-earth.com/agreement](https://dev.sparrow-earth.com/agreement)
