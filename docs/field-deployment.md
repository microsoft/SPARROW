---
title: "Remote Wildlife Monitoring: SPARROW Field Deployment Guide"
description: "Plan a remote wildlife monitoring deployment with SPARROW: siting, solar power, Starlink wildlife connectivity, camera-trap networking, and field maintenance."
tags:
  - remote-wildlife-monitoring
  - field-deployment
  - starlink
  - solar-powered
  - SPARROW
  - camera-trap
---

# Remote Wildlife Monitoring: SPARROW Field Deployment Guide

Getting a SPARROW unit to run unattended for months in a remote location is mostly a planning problem. This guide walks through the field-side decisions: where to put the unit, how to size its power, how its connectivity behaves over Starlink, how to lay out the camera-trap network, and what maintenance looks like once it is live.

It assumes the unit is already built and flashed. For parts and wiring see [hardware and architecture](hardware.md); for the software stack see [software setup](setup.md).

## Siting the unit

The SPARROW enclosure has to satisfy three things at once: sun for the panels, sky for the satellite dish, and radio reach to the cameras.

- **Sun exposure.** The solar panels are the unit's only power source, so the mounting spot needs as much unobstructed daylight as the site allows. The 45-inch tilt brackets let you angle the panels toward the sun's seasonal arc.
- **Clear sky for Starlink.** The Starlink Mini dish needs an open view overhead to hold a link to the low-Earth-orbit constellation. Site it away from dense canopy or terrain that blocks the sky.
- **WiFi reach to the cameras.** The Jetson runs a WiFi hotspot that the camera traps join, so cameras need to sit within radio range of the enclosure. A long-range outdoor antenna is an option when the camera network spreads out.
- **Weather and physical security.** The electronics live in an IP65-rated weatherproof junction box built for outdoor field use. Choose a mounting point that protects the panels and dish from the worst of the local weather and keeps the unit out of easy reach.

## Power planning

SPARROW is built to run off-grid indefinitely on solar, but only if power generation and storage are matched to the site.

- **Generation.** Two 100W monocrystalline panels feed an MPPT charge controller wired for a 24V configuration. MPPT tracking squeezes more usable energy out of the panels than a simpler controller would, which matters on short or overcast days.
- **Storage.** A 24V LiFePO4 battery carries the unit through nights and cloudy stretches. The bill of materials lists a 50Ah to 100Ah cell; pick capacity for your latitude, season, and how much cloud the site sees. Longer dark periods call for more storage.
- **Demand management.** SPARROW actively manages its own draw. It monitors the charge controller and battery state and schedules components dynamically, throttling or pausing power-hungry tasks to ride out low-charge periods rather than draining the battery flat.

!!! tip "Size for the worst week, not the average"
    Solar autonomy is set by your cloudiest stretch, not by typical conditions. When in doubt, favor more battery capacity and panel headroom for the darkest part of the deployment season.

## Connectivity over Starlink

SPARROW uses a Starlink Mini kit for its uplink, which is what lets it report from places with no cellular or terrestrial WiFi. Connectivity is treated as intermittent by design.

- **Satellite uplink.** A dedicated `starlink` service watches the satellite link, logs signal metrics, and triggers a data sync when the uplink is up.
- **Store and forward.** When the link is down the unit keeps working: data is recorded to local storage and synced automatically once connectivity returns, so a connectivity gap does not cost you observations.
- **Scheduled link windows.** The unit pulls a Starlink sleep-window schedule from the dashboard, so the satellite terminal can be powered down during set hours to conserve energy rather than drawing current around the clock.

Because inference runs on-device, only detections and metadata cross the satellite link, which keeps data volumes within what a remote uplink can carry.

## Camera-trap network

A single SPARROW unit can act as the hub for a sizeable camera network, up to 150 solar WiFi cameras. During setup the Jetson is configured with a persistent WiFi hotspot that the cameras join, and the unit polls them, pulls new images, and deduplicates before running detection. For larger or more spread-out deployments, a higher-gain outdoor WiFi antenna extends the usable range.

## Maintenance and operation

Once a unit is live, most operation is hands-off, but a few things are worth planning around:

- **Pairing and data flow.** The unit pairs to a SPARROW dashboard account with an access key; detections, audio, and system metrics upload there when connectivity allows. Register and obtain a key at [dashboard.sparrow-earth.com](https://dashboard.sparrow-earth.com/).
- **Health telemetry.** Environmental sensors and system metrics are uploaded alongside detections, giving you a remote read on how the unit is faring without a site visit.
- **Storage headroom.** A 2TB NVMe SSD buffers images and audio locally so the unit can keep recording through extended offline periods; plan visits or sync windows so the buffer does not fill during a long connectivity gap.
- **Privacy.** Human images are screened and removed on-device before upload, and the dashboard applies its own scrubbing as a second pass.

## Related pages

- **[Edge AI biodiversity monitoring](edge-ai-wildlife-monitoring.md)**: what SPARROW is and why on-device AI suits remote work.
- **[Hardware and architecture](hardware.md)**: the components behind every choice on this page.
- **[Limitations and field considerations](limitations.md)**: the constraints to weigh before committing a site.

## Related Microsoft biodiversity AI projects

SPARROW is part of an open-source biodiversity toolkit from the Microsoft AI for Good Lab; the [Microsoft Biodiversity hub](https://microsoft.github.io/Biodiversity/) is the umbrella for the projects below.

- **[MegaDetector](https://microsoft.github.io/MegaDetector/)**: the camera-trap detection model SPARROW runs on captured images in the field.
- **MegaDetector-Acoustic (documentation coming soon)**: handles analysis and classification of the audio SPARROW records.
- **[PyTorch-Wildlife](https://microsoft.github.io/Pytorch-Wildlife/)**: the framework supplying SPARROW's on-device wildlife models.
