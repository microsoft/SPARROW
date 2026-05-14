---
description: "SPARROW — Solar-Powered Acoustic and Remote Recording Observation Watch. AI-powered edge computing for wildlife monitoring by Microsoft AI for Good Lab."
tags:
  - SPARROW
  - edge-ai
  - wildlife-monitoring
  - conservation
  - camera-traps
  - jetson
---

# SPARROW

**SPARROW** (Solar-Powered Acoustic and Remote Recording Observation Watch) is Microsoft AI for Good Lab's open-source edge AI solution for wildlife monitoring in the most remote regions of the world.

Solar-powered and equipped with multi-modal sensors, SPARROW collects biodiversity data from camera traps, acoustic monitors, and environmental detectors. It processes that data on-device using [PyTorch-Wildlife](https://github.com/microsoft/Pytorch-Wildlife) models running on power-efficient edge GPUs (Jetson Orin Nano), then transmits results via low-Earth-orbit satellites for near-real-time insights — no matter how remote the deployment site.

## Key capabilities

- **On-device AI** — runs PyTorch-Wildlife detection and classification models locally, no cloud required for inference
- **Multi-modal sensing** — camera traps, acoustic monitoring, environmental sensors
- **Solar-powered** — autonomous operation with intelligent power management and battery health monitoring
- **Global connectivity** — Starlink satellite uplink for remote data transmission
- **Resilient** — records data offline, syncs automatically when connectivity is restored

## Quick links

- [Hardware Setup](hardware.md) — bill of materials, assembly, and Jetson Orin Nano setup
- [Software Setup](setup.md) — Docker installation, environment configuration, and one-click deploy
- [Cite Us](cite.md) — how to cite SPARROW in publications
- [GitHub Repository](https://github.com/microsoft/SPARROW)

## Part of the Microsoft Biodiversity Ecosystem

| Repository | Description |
|---|---|
| [microsoft/Biodiversity](https://github.com/microsoft/Biodiversity) | Umbrella hub — PyTorch-Wildlife, MegaDetector, ecosystem overview |
| [microsoft/MegaDetector](https://github.com/microsoft/MegaDetector) | Animal/human/vehicle detector for camera traps |
| [microsoft/Pytorch-Wildlife](https://github.com/microsoft/Pytorch-Wildlife) | Unified AI framework: detection + species classification |
| [microsoft/SPARROW](https://github.com/microsoft/SPARROW) | This repo — solar-powered edge AI for wildlife monitoring |
| [microsoft/SPARROW-Studio](https://github.com/microsoft/SPARROW-Studio) | Dashboard for SPARROW data visualization |
