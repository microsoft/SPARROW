---
description: "SPARROW software setup — Docker installation, environment configuration, and one-click Jetson deploy script for edge wildlife monitoring."
tags:
  - SPARROW
  - software-setup
  - docker
  - jetson
  - installation
---

# Software Setup

SPARROW runs entirely in Docker containers. This page covers how to configure and launch the SPARROW software stack on a Jetson Orin Nano.

## Prerequisites

- Jetson Orin Nano with JetPack 6.x installed
- Docker and Docker Compose installed (included in the one-click setup script)
- Starlink modem connected and configured
- Hardware assembled per the [Hardware Setup](hardware.md) guide

## Environment Configuration

Copy the environment templates and fill in your deployment-specific values:

```bash
cp sparrow.env .env.sparrow
cp starlink.env .env.starlink
```

Edit `.env.sparrow` and `.env.starlink` with your site-specific configuration (coordinates, upload endpoints, API keys, etc.).

!!! warning
    Never commit `.env` files containing real credentials. The `.gitignore` already excludes `.env` files.

## Docker Compose Launch

Start the full SPARROW stack:

```bash
docker compose up -d
```

This launches two services defined in `docker-compose.yml`:

- **sparrow** — camera trap capture, on-device AI inference (PyTorch-Wildlife), data management, power control, telemetry
- **starlink** — Starlink satellite connectivity monitoring and data uplink

View logs:

```bash
docker compose logs -f
```

## One-Click Jetson Setup

For a fresh Jetson deployment, use the automated setup script in `setup script/`:

```bash
cd "setup script"
./setup.sh
```

This script handles all steps from OS configuration through Docker launch. See the [Assembly and Setup Guide PDF](https://github.com/microsoft/SPARROW/blob/main/documentation/SPARROW_Assembly_and_Setup_Guide.pdf) for full details on each step.

## Dependencies

Python dependencies are organized per service:

- `sparrow/requirements.txt` — AI/ML stack (torch, torchvision, librosa, etc.)
- `starlink/requirements.txt` — Starlink gRPC interface

These are installed inside their respective Docker images — no manual `pip install` needed on the host.
