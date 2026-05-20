![SPARROW — Solar-Powered Acoustic and Remote Recording Observation Watch, edge AI for wildlife monitoring](https://zenodo.org/records/17547596/files/SPARROW-banner.png)
 
  </a>
</p>

<div align="center"> 
<font size="6"> Accelerating Research and Conservation with Edge AI.</font>
<br>
<hr>
<!-- Badges Section -->
<p align="center">
  <!-- License -->  
    <img src="https://pypi-camo.freetls.fastly.net/cd0913ed24368b790668a699719b5562b033448d/68747470733a2f2f696d672e736869656c64732e696f2f707970692f6c2f5079746f72636857696c646c696665">
  <!-- Docker -->
    <img src="https://img.shields.io/badge/docker-ready-blue?logo=docker">
  <!-- Contributions Welcome -->
  <img src="https://img.shields.io/badge/contributions-welcome-brsvg">
<br><br>
</div>

# 👋 Welcome to SPARROW

**SPARROW**, developed by **Microsoft's AI for Good Lab**, is an **AI-powered edge computing solution** designed to monitor and protect wildlife in the most remote regions of the world. 

Solar-powered and equipped with advanced sensors, it collects biodiversity data—from camera traps, acoustic monitors, and other environmental detectors—that are processed using our most advanced PyTorch-based wildlife AI models on power efficient edge GPUs. 

The resulting critical information is then transmitted via low-Earth orbit satellites directly to the cloud or on-premise infrastructure, allowing researchers to access fresh, actionable insights in real time, no matter where they are.
<!-- This section has the latex citation 
To learn more about project SPARROW, please checkout our SPARROW paper here 👉 [aka.ms/sparrowpaper](https://aka.ms/sparrowpaper)-->

---

## Part of the Microsoft Biodiversity Ecosystem

| Repository | Description |
|---|---|
| [microsoft/Biodiversity](https://github.com/microsoft/Biodiversity) | Umbrella hub — PyTorch-Wildlife, MegaDetector, ecosystem overview |
| [microsoft/MegaDetector](https://github.com/microsoft/MegaDetector) | Animal/human/vehicle detector for camera traps |
| [microsoft/Pytorch-Wildlife](https://github.com/microsoft/Pytorch-Wildlife) | Unified AI framework: detection + species classification |
| [microsoft/MegaDetector-Acoustic](https://github.com/microsoft/MegaDetector-Acoustic) | Bioacoustic AI for audio-based wildlife detection and classification |
| [microsoft/MegaDetector-Overhead](https://github.com/microsoft/MegaDetector-Overhead) | Wildlife detection in aerial and drone imagery |
| [microsoft/MegaDetector-Sonar](https://github.com/microsoft/MegaDetector-Sonar) | Sonar-based wildlife detection for aquatic monitoring |
| [microsoft/MegaDetector-Classifier](https://github.com/microsoft/MegaDetector-Classifier) | Camera-trap species classification fine-tuning — adapt classifiers to your own datasets and geographic regions |
| [microsoft/SPARROW](https://github.com/microsoft/SPARROW) | This repo — solar-powered edge AI for wildlife monitoring |
| SPARROW Studio | Desktop application for all AI for Good Lab models |

---

# ✨ Key Features

1. **🔋 Autonomous operation**  
   Intelligent power management with solar charging, battery health monitoring, and dynamic component scheduling enables continuous off-grid operation.

2. **📷 Sensing**  
   Camera traps, acoustic monitoring, and environmental sensors - SPARROW integrates multi-modal sensing to capture images, sounds, and enviromental metrics for comprehensive biodiversity monitoring.

3. **🧠 On-device AI**  
   Runs optimized PyTorch-Wildlife models on power efficient edge GPUs (e.g., Jetson Orin Nano) for real-time image and acoustic detection, species classification, and event recognition.

4. **🌐 Global connectivity**  
   Even in the most remote ecosystems, SPARROW maintains a link to the cloud or on-premise infrastructure through low-Earth-orbit satellites, ensuring that vital conservation data reaches researchers in near real time.

5. **🛡️ Resilience**  
   Designed for extreme field conditions - SPARROW safely records data when offline, automatically synchronizing once connectivity is restored to ensure no loss of information.

---

# This repository contains the **SPARROW client**:  
Data collection, on-device inference, power management, telemetry, and secure transmission.  

All services run in **Docker** and are orchestrated with **Docker Compose**. 🐳

---

# 🚀 Getting Started

## 🛠️ 1. Hardware Assembly


### 📋 Prerequisites

<details>
<summary> 🛒 Before you begin, ensure you have all the necessary hardware listed in the SPARROW Bill of Materials (BOM) below: 👉CLICK TO EXPAND</summary>

The following list represents our **recommended Bill of Materials** for assembling SPARROW devices. Components listed under the **Tested & Recommended** column are those on which the official assembly guide was developed and validated.

If you choose alternative components, please be aware that additional steps may be required and potential compatibility issues could arise. 

This curated list is designed to simplify the process for beginners and those with limited hardware experience, ensuring a smoother build and reliable performance.

<p style="font-size:9px;">
 
| **System** | **Item**                                                        | **Description**                                                                                                                                                                                                                              | **Qty** | **Tested/Recommended**                                                                                                                                                   |
| -------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Brain          | NVIDIA Jetson Orin Nano Super Developer Kit                         | AI Edge Compute Device                                                                                                                                                                                                                            | 1           | NVIDIA Jetson Orin Nano Super Developer Kit                                                                                                                                  |
|                | 2TB PCIe Gen 4 NVMe M.2 Internal Solid State Hard Drive             | 2TB SSD Drive                                                                                                                                                                                                                                     | 1           | Samsung 980 PRO SSD MZ-V8P2T0CW                                                                                                                                              |
|                | Pi 3 Click Shield                                                   | Pi 3 Click Shield converts the GPIO pins on the NVIDIA Jetson Orin Nano into two mikroBUS™ sockets                                                                                                                                                | 1           | MIKROE-2756                                                                                                                                                                  |
|                | mikroBUS Shuttle                                                    | Mikroe Shuttle is a small add-on board, which is intended to be used with Shuttle click, in order to expand the mikroBUS™ with additional stacking options.                                                                                       | 4           | MIKROE-2882                                                                                                                                                                  |
|                | mikroBUS Shuttle Click                                              | Shuttle click is a mikroBUS socket expansion board, which provides an easy and elegant solution for stacking up to four click boards\\ on a single mikroBUS                                                                                       | 2           | MIKROE-2880                                                                                                                                                                  |
|                | DS3231M I2C Board                                                   | Real-time clock module which has an extremely low power consumption, allowing it to be used with a single button cell battery, for an extended period of time                                                                                     | 1           | MIKROE-3770                                                                                                                                                                  |
|                | BME688 I2C Board                                                    | Compact add-on board that contains a four-in-one environmental measurement solution                                                                                                                                                               | 1           | MIKROE-4893                                                                                                                                                                  |
|                | SHTC3 I2C Board                                                     | The SHTC3 sensors offers the complete measurement system: capacitive RH sensor, bandgap thermal sensor, analog and digital data processing, and the I2C communication interface                                                                   | 1           | MIKROE-3331                                                                                                                                                                  |
|                | I2C Relay Board                                                     | Relay board featuring at least one SRD-5VDC-SL-C relays                                                                                                                                                                                           | 1           | MIKROE-3357                                                                                                                                                                  |
|                |                                                                     |                                                                                                                                                                                                                                                   |             |                                                                                                                                                                              |
| Power          | 24V 15A MPPT Solar Charge Controller                                | 24V 15A (at least) MPPT solar charge controller with load output control and usb interface                                                                                                                                                        | 1           | Victron Smart Solar MPPT 100V/20A SCC110020160R                                                                                                                              |
|                | USB Solar Charge Controller Interface                               | Direct to USB interface connection to devices with a USB port                                                                                                                                                                                     | 1           | Victron Energy VE.Direct to USB interface ASS030530010                                                                                                                       |
|                | 100 Watt Solar Panels Monocrystalline Solar Panel                   | 100 Watt Monocrystalline Solar Panel (at least 2 required working in a 24V matrix)                                                                                                                                                                | 2           | ECO-WORTHY 100 Watt Solar Panel US-L02M100-B-1                                                                                                                               |
|                | 10AWG Solar Extension Cable 30A/1000V DC PV004, IP67                | Cables that go from the Solar Panels to the Solar Charge Controller (overall length subject to installation)                                                                                                                                      | 1           | ECO-WORTHY 10FT 10AWG Solar Extension Cable 30A/1000V DC, IP67 Waterproof with Compatible Quick Connectors                                                                   |
|                | 45in Solar Panel Mount Brackets                                     | 45in Solar Panel Mount Brackets, with Foldable Tilt Legs Suitable for 2pcs 100W                                                                                                                                                                   | 1           | ECO-WORTHY 45in Solar Panel Mount Brackets US-L03TYNSJZJ4-1                                                                                                                  |
|                | 24V 50Ah or 100Ah LifePo4 Battery                                   | 24V 50Ah  100Ah LifePo4 Battery (capacitiy depending on deployment conditions/location)                                                                                                                                                           | 1           | ECO-WORTHY 24V 100Ah LiFePO4 Lithium Battery US-L13070402010-1                                                                                                               |
|                | SAE to O Ring 10AWG Battery Connector Terminal                      | Fused Battery Cable that goes from the Battery (O-Ring) to the Solar Controller Battery Cable (SAE)                                                                                                                                               | 1           | iGreely 10 Gauge Wire SAE to O Ring Terminal                                                                                                                                 |
|                | 10AWG Solar Panel Connector Cable                                   | Solar Controller Battery Cable (SAE), 10AWG SAE to PV Male & Female Adapter (overall length subject to installation, see assembly instructions on how to modify for this use case)                                                                | 1           | iGreely Solar Panel Connector Cable, 10AWG SAE to Male & Female Adapter                                                                                                      |
|                |                                                                     |                                                                                                                                                                                                                                                   |             |                                                                                                                                                                              |
| Build          | Outdoor Weatherproof IP65 Electrical Junction Box                   | Outdoor Weatherproof IP65 Electrical Junction Box, Ventilated Design,  Use with Mounting Panel & Hinged Cover. Size: 17"x13"x7"                                                                                                                   | 1           | ANIMACYN Electrical Junction Box, Ventilated Design, Cable Grommets, Indoor/Outdoor Use with Mounting Panel & Hinged Cover. Waterproof IP 65. (Grey Cover, 17.7"x13.7"x7.9") |
|                | 18AWG Speaker Wire (Black+Red)                                      | 18AWG Copper Clad Aluminum Speaker Wire (Black + Red)                                                                                                                                                                                             | 1           | GEARit GEARit Speaker Wire 18 Gauge, Speaker Cable 18AWG                                                                                                                     |
|                | Displayport Headless EDID Dongle                                    | Displayport monitor emulator required to guarantee image output during remote control of Jetson unit                                                                                                                                              | 1           | BKFK dp Dummy Plug - Display to hdmi Adapter, Luna Display Virtual Window for Home-edid Emulator-Dummy, displayport Headless dummie dongle(DP-1P)                            |
|                | 5.5mm x 2.5mm 90 Degree Right Angle DC Barrel Male Plug Jack        | 5.5mm x 2.5mm 90 Degree Right Angle DC Barrel Plug to Power the Jetson Unit                                                                                                                                                                       | 1           | Fancasee DC Power Pigtail Cable, 10-Pack 5.5mm x 2.5mm 90 US-CAB-65                                                                                                          |
|                | 5.5mm x 2.1mm DC Female Plug to Bare Wire                           | Starlink Mini Power DC Female Plug (you can use either a DC female plug to bare wire, or a fully assembled pig tail)                                                                                                                              | 1           | Tonton 16AWG DC Power Pigtails Cable - 3.3FT, Pure Copper, Orange - 5.5mm x 2.1mm DC Female Plug to Bare Wire Open End                                                       |
|                | Zip Ties Assorted Size                                              | Zip Ties Assorted Size, Double Sided Toothed,Heavy Duty Cable Wire Ties                                                                                                                                                                           | 1           | JIANYANG Zip Ties Assorted Size, 8+12+14+18 Inch                                                                                                                             |
|                | 10FT USB A to Micro USB Cable                                       | Long Micro USB cable for the Audiomoth                                                                                                                                                                                                            | 1           | MOVOYEE Long 10FT USB to Micro USB Cable                                                                                                                                     |
|                | PG7 PG9 PG11 PG13.5 PG16 PG19 Weatherproof Cable Gland Connectors   | Weatherproof Cable Gland Connectors to route the cables going in and out of the electrical Junction Box                                                                                                                                           | 1           | LISTENJIALE Cable Gland Waterproof 50 pcs                                                                                                                                    |
|                |                                                                     |                                                                                                                                                                                                                                                   |             |                                                                                                                                                                              |
| Network        | STARLINK Mini Kit                                                   | STARLINK Mini Kit - High-Speed Portable Internet for Remote and Mobile Use                                                                                                                                                                        | 1           | Starlink Mini Antenna Kit                                                                                                                                                    |
|                | Starlink Ethernet Adapter RJ45 Coupler Waterproof Compatible        | Weatherproof Starlink Compatible RJ45 Coupler                                                                                                                                                                                                     | 1           | EAZUSE RJ45 Starlink Ethernet Adapter Gen 3/Mini                                                                                                                             |
|                | Cat 6 Outdoor Ethernet Cable from Jetson to Starlink                | Cat 6 Outdoor Ethernet Cable, 24AWG 10Gbps Waterproof Direct Burial LLDPE UV Jacket (overall length subject to installation)                                                                                                                      | 1           | VOIETOLT Cat 6 Outdoor Ethernet Cable 30 ft, 24AWG 10Gbps Cat6 Cable Cord Waterproof Direct Burial LLDPE UV Jacket                                                           |
|                | 2X WiFi Antenna with MHF4/IPEX to RP-SMA Pigtail Antenna WiFi Cable | Pair of 6dBi Dual Band WiFi RP-SMA Male Antenna +2 x 35CM RP-SMA IPEX MHF4 Pigtail Cable for M.2 NGFF WiFi WLAN Card                                                                                                                              | 1           | HIGHFINE 2 x 6dBi 2.4GHz 5GHz Dual Band WiFi RP-SMA Male Antenna+2 x 35CM RP-SMA IPEX MHF4 Pigtail Cable for M.2 NGFF WiFi WLAN Card                                         |
| Optional       | 10dBi Long Range Outdoor WiFi Fiberglass Antenna                    | Optional upgrade to improve overall WiFi Range. Requires additional glands to route the cables through the Junction Box Case, \*\*IMPORTANT NOTE: MHF4/IPEX to RP-SMA Pigtail Antenna WiFi Cable is REQUIRED and must be purchased separately\*\* | 2           | eifagur 10dBi Long Range Dual Band WiFi 2.4GHz 5GHz Fiberglass Antenna                                                                                                       |
|                |                                                                     |                                                                                                                                                                                                                                                   |             |                                                                                                                                                                              |
| Audio          | AudioMoth Dev Case                                                  | Weatherproof AudioMoth Case                                                                                                                                                                                                                       | 1           | AudioMoth Dev Case                                                                                                                                                           |
|                | AudioMoth Dev Board                                                 | AudioMoth Dev board                                                                                                                                                                                                                               | 1           | AudioMoth Dev Board                                                                                                                                                          |
|                |                                                                     |                                                                                                                                                                                                                                                   |             |                                                                                                                                                                              |
| Camera         | 2.4Ghz Solar WiFi Security Camera                                   | Solar Weatherproof WiFi Cameras to be used as the SPARROW Camera Traps (you can use up to 150 cams per SPARROW main unit)                                                                                                                         | 1           | Reolink Argus Eco+                                                                                                                                                           |

</p>

</details>

To download a PDF version of this BOM list, please visit 👉 [aka.ms/sparrowbom](https://aka.ms/sparrowbom)

SPARROW Bill of Materials (BOM) © 2025 by Microsoft is licensed under MIT.
🔗 To view a copy of this license, visit: [MIT License](https://mit-license.org/)

### ⚠️ Important Note on Alternative I²C Boards
If you choose to use generic I²C boards, please be aware that some modifications to the device address in the code 🔍 may be necessary. Different vendors often assign addresses that vary from those provided in this release.
For simplicity and flexibility, we adopted the Mikroe MikroBUS standard ✅, which greatly reduces the barrier to entry thanks to its ease of assembly 🔧 and standardized interface.
Our assembly guide 📖 was drafted using Mikroe Click boards, so if you opt for generic I²C boards, expect additional steps not covered in the guide. This approach is recommended only for advanced users 🛠️ familiar with hardware integration and troubleshooting. 

Generic boards may require custom wiring and code adjustments beyond what is documented here.

💡 Tip: To ensure a smooth experience, we strongly recommend starting with MikroBUS-compatible modules unless you have prior technical experience with I²C board assemblies, I²C address mapping and board-specific configurations.

### 🏗️ Hardware Assembly Instructions
Follow this step-by-step guide to assemble your SPARROW device with ease. We designed the process around the Mikroe MikroBUS standard for maximum flexibility and simplicity, reducing the skill barrier for new users. Each step includes clear visuals and tips to ensure proper installation of components like sensors, connectors, and power modules. 

⚠️ If you choose alternative boards or custom configurations, additional steps may be required and are not covered in this guide. For best results, start with the recommended components and verify connections before powering up. 🔌

To download the SPARROW Hardware Assembly Guide, please visit 👉 [aka.ms/sparrowassembly](https://aka.ms/sparrowassembly)

SPARROW Assembly and Set-Up Guide © 2025 by Microsoft is licensed under MIT.
🔗 To view a copy of this license, visit: [MIT License](https://mit-license.org/)

---

## ⚡ 2. One-click Jetson Setup (Recommended)

The repo contains a Jetson configuration script `sparrow_setup.sh` that installs prerequisites, prepares folders, downloads default Triton models, seeds the DS3231 RTC, configures Wi-Fi hotspot, and launches the SPARROW services.

To send data to the SPARROW dashboard you will need to pair it with your account.  
To create an account and obtain an access key visit:  
[https://dashboard.sparrow-earth.com/](https://dashboard.sparrow-earth.com/)

📄 [View the SPARROW dashboard Terms & Conditions](https://dev.sparrow-earth.com/agreement)

**Script:** Download the SPARROW setup script from this repo once the hardware assembly and Jetson flash is complete (detailed instructions can be found in the build instructions).  
The setup script should be run from `~/Desktop`.

### ▶️ Usage

```bash
cd ~/Desktop
sudo chmod +x sparrow_setup.sh
sudo ./sparrow_setup.sh

```

## What the Script Does

### 1️⃣ Prereqs & Tooling
Installs:
```
docker, docker-compose, git, curl, wget, uuidgen, smbus2
```

### 2️⃣ Device Identity
Generates `/etc/unique_id` if missing (single-line UUID).

### 3️⃣ Folder Layout (Host)
Creates `~/Desktop/system` with:
```
/system
├── docker-compose.yml
├── sparrow_setup.sh
├── Models/
│   └── tritonserver/
│       └── model_repository/
│           ├── megadetectorv6/
│           │   ├── 1/
│           │   │   └── model.onnx
│           │   └── config.pbtxt
│           ├── AI4GAmazonClassification/
│           │   ├── 1/
│           │   │   └── model.onnx
│           │   └── config.pbtxt
│           └── megadetector_birds_v1/
│               ├── 1/
│               │   └── model.onnx
│               └── config.pbtxt
├── sparrow/
│   ├── Dockerfile
│   ├── config/
│   │   └── access_key.txt
│   ├── images/
│   ├── recordings/
│   ├── logs/
│   └── static/
│       ├── data/
│       └── gallery/
└── starlink/
    ├── Dockerfile.starlink
    ├── config/
    │   └── access_key.txt
    └── logs/

```

### 4️⃣ Models + Configs
Downloads three default ONNX models from Zenodo and writes minimal `config.pbtxt` for each Triton repo.

### 5️⃣ Access Key
Prompts for the server access key (obtained from the SPARROW dashboard) and writes it to:
```
sparrow/config/access_key.txt
starlink/config/access_key.txt
```

### 6️⃣ RTC Seeding (DS3231 over I2C bus 7)
Gets UTC from WorldClock API (fallback: NTP or system UTC) and writes it to the RTC.

### 7️⃣ Wi-Fi Hotspot
Configures a persistent hotspot via NetworkManager:  
**SSID:** `CameraTraps`  
**Password:** `User prompted`

### 8️⃣ Docker Build & Launch
Builds images with BuildKit (no cache), runs `docker-compose up -d`, and tails logs.

---

# 🧩 Software Dependencies

All Python dependencies are inside the containers (no host Python required):

1. `PyTorch`, `torchaudio`, `tritonclient`, `aiosmtpd`, `psutil`, `smbus2`, `pyserial`, etc.  
2. **NVIDIA Triton Inference Server** (explicit model control mode)  
3. **Hardware:** I2C, ALSA audio, and USB serial (compose is configured privileged)

---

# 🔗 API References

The client calls these endpoints on `SERVER_BASE_URL`:

| Endpoint | Description |
|-----------|--------------|
| `/uploads` | Image + detection metadata |
| `/audio_uploads` | WAV audio files |
| `/system_metrics` | System + sensor metrics JSON |
| `/get_schedule` | Starlink sleep window |
| `/get_scheduleaudio` | Audio capture settings |
| `/model_settings` | Classification model + labels |
| `/model_update` | Triton model manifest |

Each request includes `auth_key` and a `unique_id` derived from `/etc/unique_id`.

---

# 🤝 Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit [Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

---
<!-- This section has the latex citation 
# :fountain_pen: Cite us!
We have recently published a technical paper on **SPARROW** and encourage you to cite our work! 

The paper is currently in the process of being published on **arXiv**. 

In the meantime, you can download the full version from the following link: [aka.ms/sparrowpaper](https://aka.ms/sparrowpaper)

<!-- This section has the latex citation 
We have recently published a [technical paper on SPARROW](https://aka.ms/sparrowpaper). Please feel free to cite us!

```
@misc{lavista2025listening,
      title={Listening to the Earth in Real Time: SPARROW and the Future of Conservation Technology}, 
      author={Juan M. Lavista Ferres*, Carl Chalmers*, Bruno Demuro Segundo*, Zhongqi Miao*, Andres Hernandez Celis, Isai Daniel Chacon Silva, Allen Kim, Luana Marotti, Amy Michaels, Daniela Ruiz Lopez, Rahul Dodhia, Inbal Becker-Reshef, Pablo Andrés Arbelaez Escalante, Federico Alves Torres, Meygha Machado, Anthony Cintron Roman},
      year={2025},
      eprint={xxxxxxx},
      archivePrefix={arXiv},
}
```

---
-->
# ⁉️ SPARROW FAQs
<details>
<summary> 🦜 What is SPARROW and what does it do? </summary>

The **Solar-Powered Acoustic and Remote Recording Observation Watch (SPARROW)** is an AI-powered computing solution designed to operate autonomously in the location where it is installed to monitor and collect data on biodiversity of the area.  Data is collected from camera traps, acoustic monitors, and other environmental detectors, and then processed using wildlife AI models. SPARROW is solar-powered so that it can be used in remote areas without easy access to power sources. Data can be transmitted to the cloud via satellites, allowing researchers to transfer data to the SPARROW Dashboard, or other personal dashboards, and further analyze and gain insights on their data from anywhere.   
</details>

<details>
<summary> 🤖 How do the AI models work?</summary>

AI models can take in different kinds of information like pictures, sounds, and sensor readings and look for patterns that help them understand what’s happening. For example, they can recognize objects in images, detect sounds in audio, or spot unusual readings in telemetry data. The AI models that run on SPARROW analyze the collected data to determine if the images should be kept and uploaded.  
</details>

<details>
<summary> 🛡️ How does SPARROW handle privacy and human-related data?</summary>

SPARROW includes scrubbing software that will delete any inadvertently collected human-related data off of the device.  Additionally, the Microsoft Dashboard includes scrubbing software that runs over the data that is uploaded to remove or anonymize any human-related data. If, after scrubbing, Microsoft personnel find any human-related data, it will be deleted.  You can also delete data off of your device or the Microsoft Dashboard by going to the gallery and deleting the associated files. The vision system looks at images and tries to recognize people by comparing what it sees with patterns it has seen previously. When it detects a person, the system calculates a confidence score (basically, how sure it is that it has found a match). If the score is high enough, the image is removed or anonymized.  
</details>

<details>
<summary> ⚠️ Can I remove the scrubbing software?</summary>

Microsoft **does not** recommend removal of scrubbing software on your device.  Data uploaded to the Microsoft Dashboard will be scrubbed of personally identifiable information regardless of SPARROW device scrubbing.  Dashboard scrubbing and privacy features cannot be altered or removed. 
</details>

<details>
<summary> 📬 How can I contact support for issues or privacy concerns?</summary>

For dashboard-related issues, Microsoft trademark authorization, privacy concerns, or general feedback, use the **contact form** under the “About” menu in the SPARROW dashboard. For development or client-specific issues, reach out via the **GitHub page**.
</details>

<details>
<summary> 📅 How often are these FAQs updated?</summary>
 
These FAQs will be updated on an **annual basis**.
</details>

---

# 🗄️ Data Storage & User Rights

When you register into the **SPARROW dashboard**, we store your **email address** solely for the purpose of **providing and maintaining access to our Dashboard**. You have the right to **permanently delete your account**, your email, and any other associated data at any time. Upon your request, all data related to your account will be **irreversibly removed** from our systems.  

---

# 📢 Publications & Publicity

Microsoft may only use your data for **model improvement with your explicit consent**. You can opt in at any time using the toggle switch in the dashboard (**default setting is OFF**). All data uploaded to the dashboard remains private and will **never be shared** unless you have provided prior consent. Uploaded data will only be analyzed to ensure compliance with the **Terms of Use, and to fix Dashboard bugs and security issues**.

If you publish any **academic papers**, **articles**, or **research** based on **Data from the SPARROW Dashboard**, please **cite our project** in your publication. 

You may not issue any press releases, public statements, or other publicity materials referencing Microsoft without our prior written approval. 
**Please use the contact form under the "About" section in the SPARROW Dashboard to send your request and we will get back to you right away (this is a very quick process).**

---

# 🏷️ Trademarks

This project may contain trademarks or logos for projects, products, or services.  **Use of any Microsoft trademarks or logos is not permitted without prior written consent from Microsoft. Please use the contact form under the "About" section in the dashboard to send your request**. If you have received authorization, **your use of Microsoft
trademarks or logos is subject to and must follow**
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.

---
