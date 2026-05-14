---
description: "SPARROW hardware assembly guide — bill of materials, wiring, and Jetson Orin Nano setup for remote wildlife monitoring field deployment."
tags:
  - SPARROW
  - hardware
  - jetson
  - bill-of-materials
  - assembly
---

# Hardware Setup

This page covers the hardware required to build and deploy a SPARROW unit. For detailed step-by-step assembly instructions, wiring diagrams, and the full bill of materials, see the [SPARROW Assembly and Setup Guide](https://github.com/microsoft/SPARROW/blob/main/documentation/SPARROW_Assembly_and_Setup_Guide.pdf) (PDF).

## Bill of Materials

The [SPARROW BOM PDF](https://github.com/microsoft/SPARROW/blob/main/documentation/SPARROW_Bill_of_Materials_-_BOM.pdf) contains the complete component list with part numbers, vendors, and approximate costs. Key components include:

- **Compute:** NVIDIA Jetson Orin Nano (edge GPU for on-device AI inference)
- **Power:** Solar panel + LiPo battery with intelligent charge management
- **Sensing:** Camera trap module, acoustic sensor, environmental sensors (temperature, humidity)
- **Connectivity:** Starlink satellite dish and modem for remote uplink
- **Enclosure:** Weatherproof housing rated for field conditions

## Assembly

Refer to the [Assembly and Setup Guide PDF](https://github.com/microsoft/SPARROW/blob/main/documentation/SPARROW_Assembly_and_Setup_Guide.pdf) for full assembly instructions, including:

1. Enclosure preparation and component mounting
2. Wiring: power distribution, sensor connections, GPIO mapping
3. Jetson Orin Nano initial boot and configuration
4. Starlink dish alignment and network setup
5. RTC seeding and system clock configuration

## One-Click Jetson Setup

Once hardware is assembled, the `setup script/` directory contains an automated setup script that:

1. Flashes the Jetson with the required OS image
2. Installs system dependencies
3. Configures the Wi-Fi hotspot
4. Seeds the RTC
5. Builds and launches Docker containers

See the [Software Setup](setup.md) page for full details.
