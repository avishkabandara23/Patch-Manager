# Patch-Manager
A PowerShell GUI tool for automating multi-server pre-patch health checks, executing maintenance scripts in parallel, and comparing pre/post-patch Windows Service states via WinRM.

# Multi-Server Pre-Patching & Post-Patching Manager

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

A standalone Windows Forms graphical interface (GUI) automation tool written in PowerShell. Built specifically for Systems Engineers, Infrastructure Engineers, and Windows System Administrators to manage, execute, verify, and document multi-server patching workflows across enterprise networks.

---

## Key Features

* **Auto-Elevation**: Self-elevates to run as Administrator automatically upon execution.
* **Interactive Graphical UI**: Native Windows Forms layout featuring draggable split panels, multi-window support, and status-coded data grids.
* **Parallel Remote Execution**: Query health metrics, WinRM status, and system information across multiple servers simultaneously using native PowerShell Remoting/WinRM with customizable throttling.
* **Comprehensive Pre-Patch Health Checks**:
  * Operating System details, build numbers, and uptime tracking.
  * Active network adapter (NIC) configuration and IP identification.
  * System drive ($C:$) and fixed volume free space evaluation.
  * Pending reboot detection (Component-Based Servicing, Windows Update, and Pending File Rename Operations).
  * Windows Update services status (`wuauserv`, `BITS`, `TrustedInstaller`) and WSUS policy reporting.
* **Service Baseline & State Comparison (Pre vs. Post)**:
  * Automatically captures a pre-patch baseline of all Windows Services.
  * Generates a side-by-side post-patch comparison highlight (color-coded red/green) to immediately flag services that stopped after system reboots.
* **Integrated Domain Admin Tools**:
  * Direct launch options for Remote Desktop (`mstsc.exe`) in standard or Console/Admin mode (`/admin`).
  * Granular single-server targeted reboots with automated ping monitoring and post-patch health verification once online.
* **Custom Script Orchestration**: Run bulk custom PowerShell scripts (`.ps1`) from a target directory across single or multi-server batches.
* **Multi-Format Exporting**: Export detailed hardware, patch history, and service comparison reports to CSV format.

---

## Prerequisites

* **Operating System**: Windows 10 / 11, Windows Server 2012 R2 or newer.
* **PowerShell Version**: PowerShell 5.1 or later.
* **Management Requirements**:
  * WinRM (Windows Remote Management) enabled on target remote servers (`Enable-PSRemoting`).
  * Network/Firewall permission for WinRM (Port 5985 for HTTP or 5986 for HTTPS).
  * Domain Administrator or local Administrator rights on target machines.

---

## Quick Start

1. Clone the repository:
   ```cmd
   git clone [https://github.com/YOUR_USERNAME/MultiServer-PrePatch-Manager.git](https://github.com/YOUR_USERNAME/MultiServer-PrePatch-Manager.git)
   ```
2. Navigate to the script directory:
   ```powershell
   cd MultiServer-PrePatch-Manager\src
   ```
3. Run the script from PowerShell (it will request elevation if required):
   ```powershell
   .\MultiServerPrePatchManager.ps1
   ```

---

## Usage Guide

1. **Target Servers**: Enter target hostnames/IP addresses (one per line) or load a `.txt` file using the **Load Server List (.txt)** button.
2. **Pre-Patch Check**: Click **1. Run Built-in Pre-Patch Check** to generate the initial health baseline across all targets.
3. **Custom Scripts (Optional)**: Browse to a directory containing custom `.ps1` maintenance scripts, select the ones you wish to run, and click **2. Run Checked Scripts**.
4. **Post-Patch Verification**: Following updates and reboots, click **3. Run Post-Patch Check** to verify update installation and check system status.
5. **Service Comparison**: Click **4. Compare Services (Pre vs Post)** to identify stopped or altered services using the comparative status window or export full CSV comparison reports.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
