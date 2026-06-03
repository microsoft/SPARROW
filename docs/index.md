---
description: "SPARROW: Solar-Powered Acoustic and Remote Recording Observation Watch. Microsoft AI for Good Lab's open-source edge AI system for wildlife monitoring with NVIDIA Jetson, Starlink, and PyTorch-Wildlife."
tags:
  - SPARROW
  - edge-ai
  - wildlife-monitoring
  - conservation
  - camera-traps
  - jetson-orin-nano
  - starlink
  - pytorch-wildlife
  - bioacoustics
  - solar-powered
---

# SPARROW

**SPARROW** (Solar-Powered Acoustic and Remote Recording Observation Watch) is Microsoft AI for Good Lab's open-source edge AI system for wildlife monitoring in the most remote regions of the world.

In one sentence: SPARROW is a solar-powered wildlife monitoring device that runs AI on-device and uplinks results over satellite, so you can collect and act on biodiversity data from places with no power and no cell coverage.

Solar-powered and equipped with multi-modal sensors, SPARROW collects biodiversity data from camera traps, acoustic monitors, and environmental sensors. It processes that data **on-device** using [PyTorch-Wildlife](https://github.com/microsoft/Pytorch-Wildlife) models running on the NVIDIA Jetson Orin Nano, so inference needs no cloud, then transmits results via Starlink low-Earth-orbit satellites for near-real-time insights anywhere on the planet.

New here? Start with [edge AI biodiversity monitoring](edge-ai-wildlife-monitoring.md) for what SPARROW is and who it is for, then the [field deployment guide](field-deployment.md) to plan a remote install.

---

## What SPARROW Does

A single SPARROW unit autonomously:

1. **Collects data** from up to 150 solar WiFi camera traps, an AudioMoth acoustic sensor, and I²C environmental sensors (temperature, humidity, pressure)
2. **Runs AI models on-device** via NVIDIA Triton Inference Server: MegaDetector v6 for animal/human/vehicle detection, species classifiers for identification, and bird-specific detectors
3. **Manages power** intelligently using MPPT solar charging, LiFePO4 batteries, and dynamic component scheduling for continuous off-grid operation
4. **Transmits data** via Starlink satellite when connectivity is available; stores data locally when offline and syncs automatically on reconnect
5. **Scrubs privacy data**: automatically detects and removes human-related images before upload

All services run in Docker containers on the Jetson, orchestrated by Docker Compose.

---

## Key Capabilities

| Capability | Details |
|---|---|
| **On-device AI inference** | MegaDetector v6, Amazon species classifier, bird detector: all as ONNX models on NVIDIA Triton |
| **Camera trap support** | Up to 150 solar WiFi cameras per unit (e.g., Reolink Argus Eco+) |
| **Acoustic monitoring** | AudioMoth integration for bioacoustics (birds, bats, insects) |
| **Global connectivity** | Starlink Mini satellite uplink: works in locations with no cellular or WiFi |
| **Solar autonomous** | 24V LiFePO4 battery + MPPT solar controller; designed for months of unattended deployment |
| **Environmental sensing** | Temperature, humidity, pressure, gas (BME688 + SHTC3 I²C sensors) |
| **Privacy by design** | On-device human image scrubbing before any data leaves the device |

---

## Architecture

```
┌─────────────────────────────────────────┐
│  SPARROW Unit (Weatherproof IP65 Box)   │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  NVIDIA Jetson Orin Nano        │    │
│  │  ├── sparrow (Docker)           │    │
│  │  │   ├── Camera polling/ingest  │    │
│  │  │   ├── Triton inference       │    │
│  │  │   ├── Power mgmt (solar)     │    │
│  │  │   └── Data sync + FTP upload │    │
│  │  └── starlink (Docker)          │    │
│  │      └── Satellite link monitor │    │
│  └─────────────────────────────────┘    │
│                                         │
│  Power: Solar panels → MPPT → LiFePO4  │
│  Network: Starlink Mini satellite dish  │
│  Sensors: AudioMoth, I²C env sensors   │
└─────────────────────────────────────────┘
         │ Data upload (Starlink)
         ▼
  SPARROW Dashboard (cloud)
  sparrow-earth.com
```

---

## Getting Started

1. **[Edge AI Biodiversity Monitoring](edge-ai-wildlife-monitoring.md)**: What SPARROW is, who it is for, and why it runs the AI at the edge
2. **[Hardware and Architecture](hardware.md)**: Bill of materials, the solar and connectivity subsystems, and how they fit together
3. **[Field Deployment Guide](field-deployment.md)**: Siting, power planning, Starlink connectivity, and maintenance for a remote install
4. **[Software Setup](setup.md)**: One-click Jetson setup script, Docker architecture, AI models
5. **[Limitations and Field Considerations](limitations.md)**: Power, connectivity, weather, and storage constraints to plan around
6. **[Cite Us](cite.md)**: How to cite SPARROW in publications
7. **[GitHub Repository](https://github.com/microsoft/SPARROW)**: Source code, issues, and contributions

---

## Part of the Microsoft Biodiversity Ecosystem

| Repository | Description |
|---|---|
| [microsoft/Biodiversity](https://github.com/microsoft/Biodiversity) | Umbrella hub: PyTorch-Wildlife, MegaDetector, ecosystem overview |
| [microsoft/MegaDetector](https://github.com/microsoft/MegaDetector) | Animal/human/vehicle detector for camera traps |
| [microsoft/Pytorch-Wildlife](https://github.com/microsoft/Pytorch-Wildlife) | Unified AI framework: detection + species classification |
| [microsoft/MegaDetector-Acoustic](https://github.com/microsoft/MegaDetector-Acoustic) | Bioacoustic AI for audio-based wildlife detection and classification |
| [microsoft/MegaDetector-Overhead](https://github.com/microsoft/MegaDetector-Overhead) | Wildlife detection in aerial and drone imagery |
| [microsoft/MegaDetector-Sonar](https://github.com/microsoft/MegaDetector-Sonar) | Sonar-based wildlife detection for aquatic monitoring |
| [microsoft/MegaDetector-Classifier](https://github.com/microsoft/MegaDetector-Classifier) | Camera-trap species classification fine-tuning: adapt classifiers to your own datasets and geographic regions |
| [microsoft/SPARROW](https://github.com/microsoft/SPARROW) | This repo: solar-powered edge AI for wildlife monitoring |
| SPARROW Studio | Desktop application for all AI for Good Lab models |
