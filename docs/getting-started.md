---
title: "Getting Started with SPARROW: Build and Deploy the Edge AI Unit"
description: "Getting started with SPARROW: decide if it fits, assemble the hardware, flash and run the one-click Jetson setup, bring up the services, and deploy in the field."
slug: getting-started
tags:
  - getting started
  - SPARROW
  - edge AI wildlife monitoring
  - Jetson setup
  - field deployment
---

# Getting Started with SPARROW

New to SPARROW? This page is the path from parts on a bench to a unit collecting data in the field. It runs four steps: assemble the hardware, flash and configure the Jetson, bring up the software, and deploy. Each step links to the full guide when you need the detail.

SPARROW is a hardware and software project, so getting started means building a physical device, not installing a package. Plan for assembly time and a SPARROW dashboard account before you begin.

## Is SPARROW right for my project?

SPARROW is the Microsoft AI for Good Lab open-source edge AI system for wildlife monitoring in places with no grid power and no cellular coverage. A solar-powered unit gathers images and sound from its sensors, runs PyTorch-Wildlife models on an NVIDIA Jetson Orin Nano on the spot, and sends only the results back over Starlink. Because inference happens on the device, the design works where sending raw data home is not an option.

Consider SPARROW when you need to:

- Monitor a remote site autonomously for months on solar power.
- Run detection and species classification at the edge rather than in the cloud.
- Pull together camera traps, acoustic sensors, and environmental sensors in one unit.

If you want to run the models on your own computer instead of a field device, start with [PyTorch-Wildlife](https://github.com/microsoft/Pytorch-Wildlife) or [MegaDetector](https://github.com/microsoft/MegaDetector). SPARROW is the option for putting that AI in the landscape.

## Step 1: Assemble the hardware

Build the unit from the bill of materials. The core components are an NVIDIA Jetson Orin Nano for compute, a solar panel with an MPPT controller and a LiFePO4 battery for power, a Starlink Mini dish for connectivity, an AudioMoth for acoustics, WiFi camera traps, environmental sensors, and a weatherproof enclosure. The [Hardware Setup](hardware.md) guide lists every part, the tested and recommended options, and the assembly steps.

## Step 2: Flash and run one-click setup

Start with a Jetson Orin Nano that has JetPack 6.x flashed, then register for a SPARROW dashboard account to get an access key. The `sparrow_setup.sh` script configures the whole device in one command: it installs Docker and tooling, generates a device identity, downloads the default ONNX models, writes your access key, seeds the real-time clock, sets up a WiFi hotspot for the cameras, and builds and launches the containers. Full prerequisites and a step-by-step breakdown are in the [Software Setup](setup.md) guide.

## Step 3: Bring up the services

SPARROW runs entirely in Docker containers managed by Docker Compose. Two services come up: `sparrow`, which polls the cameras, runs on-device inference through NVIDIA Triton, manages solar power, reads the environmental sensors, scrubs human images for privacy, and syncs results; and `starlink`, which watches the satellite link and triggers uploads when the uplink is available. The default model repository ships MegaDetector v6, an Amazon species classifier, and a bird detector. The [Software Setup](setup.md) page covers the services, models, and environment configuration, including a manual launch path for advanced users.

## Step 4: Deploy and view your data

Once a unit is running, site it in the field and let it operate unattended. It stores data locally when offline and syncs automatically when the Starlink uplink returns. Processed images, audio, and telemetry flow to the [SPARROW Dashboard](https://dashboard.sparrow-earth.com/), where you can visualize, filter, and export them. Register there for the account and access key the setup step needs.

## Get help

- **GitHub Issues:** [microsoft/SPARROW/issues](https://github.com/microsoft/SPARROW/issues) for bugs and questions.

SPARROW is part of the [microsoft/Biodiversity](https://github.com/microsoft/Biodiversity) umbrella, which links every tool in the AI for Good Lab wildlife ecosystem.
