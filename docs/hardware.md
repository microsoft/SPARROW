---
title: "SPARROW Hardware and Architecture: Solar Camera Trap on NVIDIA Jetson"
description: "SPARROW hardware and architecture: a solar powered camera trap and NVIDIA Jetson camera trap edge unit with Starlink wildlife connectivity and LiFePO4 power."
tags:
  - SPARROW
  - hardware
  - jetson-orin-nano
  - solar-powered-camera-trap
  - nvidia-jetson-camera-trap
  - starlink-wildlife
  - bill-of-materials
  - audiomoth
  - camera-trap
  - assembly
---

# SPARROW Hardware and Architecture

SPARROW is a solar-powered edge AI computing unit built around the **NVIDIA Jetson Orin Nano**. It collects data from camera traps, acoustic sensors, and environmental monitors, processes it on-device using PyTorch-Wildlife models via the NVIDIA Triton Inference Server, and transmits results via Starlink satellite.

This page summarizes the hardware that goes into a SPARROW unit and how the subsystems fit together. For the bigger-picture rationale see [edge AI biodiversity monitoring](edge-ai-wildlife-monitoring.md), and for planning a live install see the [field deployment guide](field-deployment.md).

## How the subsystems fit together

A SPARROW unit groups into five subsystems that share one weatherproof enclosure:

- **Compute** is the NVIDIA Jetson Orin Nano, which runs the AI models and every SPARROW service, making this a Jetson-based camera trap that does its detection on the spot.
- **Power** is the solar chain: panels, an MPPT charge controller, and a LiFePO4 battery feeding the Jetson, which is what makes it a true solar powered camera trap rather than a battery-swap device.
- **Network** is the Starlink Mini uplink for offsite reporting plus an internal WiFi link to the cameras, the combination that delivers Starlink wildlife connectivity from sites with no cellular service.
- **Audio** is the AudioMoth sensor, used here for field data collection.
- **Camera and enclosure** are the WiFi camera traps and the IP65 box that houses the electronics.

The sections below list the components in each subsystem. For full step-by-step assembly instructions, wiring diagrams, and part numbers, download the official guides:

- 📋 **[SPARROW Bill of Materials](https://aka.ms/sparrowbom)**: full component list with recommended vendors and quantities
- 🏗️ **[SPARROW Assembly and Setup Guide](https://aka.ms/sparrowassembly)**: step-by-step wiring and assembly instructions

---

## Hardware Components by Category

### Brain: Compute

| Component | Role |
|---|---|
| NVIDIA Jetson Orin Nano Super Developer Kit | Primary edge compute unit: runs AI models and all SPARROW services |
| 2TB PCIe Gen 4 NVMe SSD | Local image/audio storage for offline operation |
| DS3231M RTC (I²C) | Real-time clock for accurate timestamps in remote deployments |
| BME688 Environmental Sensor (I²C) | Temperature, humidity, pressure, and gas sensing |
| SHTC3 Temperature/Humidity Sensor (I²C) | Redundant environmental measurement |
| I²C Relay Board | Controlled power switching for peripheral components |
| Pi 3 Click Shield + mikroBUS Shuttles | Adapter to connect Mikroe Click boards to Jetson GPIO |

!!! note "I²C Board Compatibility"
    The assembly guide is developed around **Mikroe MikroBUS** click boards. Generic I²C boards may work but require custom address mapping and are recommended only for advanced users.

---

### Power: Solar + Battery

| Component | Role |
|---|---|
| MPPT Solar Charge Controller (24V/15A+) | Maximizes solar panel harvest; recommended: Victron SmartSolar MPPT 100/20 |
| 100W Monocrystalline Solar Panels (×2) | Primary power source: wired in 24V series configuration |
| 24V 50–100Ah LiFePO4 Battery | Energy storage for overnight and cloudy-day operation |
| Solar Panel Mount Brackets (45") | Tiltable mounting for optimal sun angle |
| 10AWG Weatherproof Cabling | Solar panel → charge controller → battery wiring |

---

### Network: Satellite Connectivity

| Component | Role |
|---|---|
| Starlink Mini Kit | Low-Earth-orbit satellite internet for remote data uplink |
| Starlink RJ45 Weatherproof Ethernet Adapter | Weatherproof wired connection from Jetson to Starlink dish |
| Cat 6 Outdoor Ethernet Cable | Direct-burial UV-rated cable between Jetson and Starlink |
| Dual-band WiFi Antenna (MHF4/IPEX to RP-SMA) | Internal WiFi for camera trap connectivity |
| 10dBi Long-Range Outdoor WiFi Antenna (optional) | Extended WiFi range for large camera trap deployments (up to 150 cameras) |

---

### Audio: Acoustic Monitoring

| Component | Role |
|---|---|
| AudioMoth Dev Board + Case | Open-source acoustic sensor for bioacoustic monitoring (bird calls, bat echolocation, etc.) |

---

### Camera

| Component | Role |
|---|---|
| Solar WiFi Camera Trap (×1+) | Camera traps for wildlife image capture: SPARROW supports **up to 150 cameras** per unit; recommended: Reolink Argus Eco+ |

---

### Enclosure

| Component | Role |
|---|---|
| IP65 Weatherproof Junction Box (17"×13"×7") | Houses all electronics; rated for outdoor/field deployment |
| Weatherproof Cable Gland Set (PG7–PG19) | Sealed cable routing in/out of enclosure |
| 18AWG Speaker Wire, Zip Ties, DC Barrel Plugs | Internal wiring and cable management |

---

## Assembly Process Overview

1. **Enclosure preparation**: drill gland holes, mount DIN rail or panel
2. **Power wiring**: solar panels → charge controller → battery → Jetson
3. **Sensor installation**: connect I²C boards (RTC, BME688, SHTC3, relay) to Jetson GPIO via Click Shield
4. **Camera network**: mount outdoor WiFi antenna(s); configure camera trap SSIDs
5. **Starlink setup**: weatherproof cable routing and dish alignment
6. **AudioMoth**: connect via USB; configure recording schedule
7. **Final check**: verify all connections before first power-up

For detailed instructions with photos and wiring diagrams, see the [SPARROW Assembly and Setup Guide](https://aka.ms/sparrowassembly).

Once hardware is assembled, proceed to [Software Setup](setup.md). To plan where and how to install the finished unit, see the [field deployment guide](field-deployment.md), and review the [limitations and field considerations](limitations.md) before committing a site.

!!! note "AudioMoth here is for capture, not analysis"
    The AudioMoth sensor is part of SPARROW's data-collection hardware. Analyzing and classifying the recorded audio is handled by [MegaDetector-Acoustic](https://microsoft.github.io/MegaDetector-Acoustic/), not by SPARROW.

## Related Microsoft biodiversity AI projects

SPARROW is the field-hardware layer of an open-source biodiversity toolkit from the Microsoft AI for Good Lab; the [Microsoft Biodiversity hub](https://microsoft.github.io/Biodiversity/) connects the projects below.

- **[MegaDetector](https://microsoft.github.io/MegaDetector/)**: the camera-trap detection model SPARROW runs on the Jetson.
- **[MegaDetector-Acoustic](https://microsoft.github.io/MegaDetector-Acoustic/)**: analyzes and classifies the audio SPARROW captures in the field.
- **[PyTorch-Wildlife](https://microsoft.github.io/Pytorch-Wildlife/)**: the AI framework whose models SPARROW packages for edge inference.
