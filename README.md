# ⚡ ubat - Universal Battery & Hardware Telemetry Tool

**ubat** is a modular, hardware-adaptive power diagnostic and optimization toolkit designed for **ANY Windows laptop** (HP OMEN, Lenovo Legion, ASUS ROG, Dell XPS, Acer Nitro, MSI, Surface, etc.).

---

## 🌟 Dynamic Laptop Branding & Partitioned Views

Whenever **ubat** runs on any PC, it automatically detects the exact brand and hardware, branding the monitor directly:
* On HP OMEN: `HP OMEN GAMING LAPTOP 16 - BATTERY, CPU, RAM & POWER MONITOR`
* On Lenovo: `LENOVO LEGION 5 - BATTERY, CPU, RAM & POWER MONITOR`
* On ASUS: `ASUS ROG ZEPHYRUS - BATTERY, CPU, RAM & POWER MONITOR`
* On Dell: `DELL XPS 15 - BATTERY, CPU, RAM & POWER MONITOR`

### 🎛️ Partitioned Display Views (Switch Live on the Fly!)
When running the Live Monitor, you can tap keys **1 through 6** to switch views instantly in real-time:
1. **[1] Full All-in-One Dashboard:** Everything combined — battery health, wattage, GPU/CPU/Screen split, and parallel Task Manager process table.
2. **[2] Battery & Power Focus:** Deep battery health (true calibrated charge, cell wear level %, health grade, cycle life bar 31/500, pack voltage, and 4-hour target budget).
3. **[3] CPU & Processor Focus:** Core configuration, clock speeds, live CPU load %, package wattage, and top 10 CPU processes.
4. **[4] RAM & Memory Focus:** Physical memory allocation %, used vs available RAM, memory load bar, and top 10 memory-hungry apps.
5. **[5] NVMe SSD & Storage Focus:** Drive model, health, live read/write speed (MB/s), active disk time %, and low-power APST storage wattage.
6. **[6] Task Manager Process Table:** Full 14-process parallel table showing Process Name, PID, CPU %, RAM MB, RAM %, Disk KB/s, and GPU status.

### ⚡ Motionless (Zero-Flicker) In-Place Display & Rate Controls
The Live Monitor features a **motionless in-place rendering engine** (no screen blanking, clearing, or strobing). The borders and labels remain perfectly still while numbers update dynamically:
* **`[F]` Fast Rate:** Sets refresh rate to **0.5s** (sub-second high-precision updates).
* **`[S]` Standard Rate:** Sets refresh rate to **1.0s** (normal cadence).
* **`[+]` / `[-]`:** Fine-tune refresh rate up or down in 0.25s increments.
* **`[1-6]`:** Instantly switch partition focus without quitting.
* **`[Q]`:** Clean exit restoring cursor state.

---

## 📁 Modular Subfolder Architecture

```text
ubat/
│
├── ubat.bat                      # 🎯 Master Interactive Menu Launcher (Options 1 - 9)
├── Run-Live-Monitor.bat          # 🚀 Quick Launch: Partitioned live telemetry dashboard
├── Optimize-Laptop.bat           # ⚡ Quick Launch: Auto-profile hardware & optimize power plan
├── Start-Test-Logger.bat         # ⏺️ Quick Launch: Start background drain test recorder
├── Stop-Test-Logger.bat          # ⏹️ Quick Launch: Stop background drain test recorder
├── Generate-Report.bat           # 📊 Quick Launch: Instant statistical analysis & summary
│
├── core/                         # 🧠 Core Hardware Profiling Engine
│   ├── HardwareProfile.ps1       # Auto-detects OEM, CPU, GPUs, Battery Design & Live Metrics
│   └── BatteryHealthModel.ps1    # Algorithmic health grade, calibrated charge %, & cycle life
│
├── monitor/                      # 🖥️ Live Visualization Module
│   └── LiveMonitor.ps1           # Dynamic branded UI with partitioned views (1-6)
│
├── optimizer/                    # ⚡ Power Plan & Hardware Tuning Module
│   └── PowerOptimizer.ps1        # Safe CPU boost capping (99%), PCIe ASPM, & GPU tuning
│
├── logger/                       # ⏺️ Background Crash-Proof Recording Daemon
│   ├── BackgroundLogger.ps1      # 30-second silent fail-safe logger (saves into logs/)
│   └── StopLogger.ps1            # PID-based background daemon terminator
│
├── analyzer/                     # 📊 Statistical Analytics & Reporting Engine
│   └── LogAnalyzer.ps1           # Calculates average watts, drop %, runtime, and exports Markdown
│
├── diagnostics/                  # 🔍 Hardware Diagnostic Utilities
│   ├── ProcessManager.ps1        # Task Manager-style parallel table & interactive PID killer
│   ├── SsdDiagnostics.ps1        # NVMe SSD throughput, health status, & storage power
│   └── MeasureCpuDelta.ps1       # Process-level instantaneous CPU spike detector
│
├── logs/                         # 📁 Dedicated Logs Directory (All data saved here)
│   ├── current-session.csv       # Active test session log
│   ├── last-report.md            # Most recently generated statistical Markdown report
│   └── archive/                  # Historical test sessions saved by timestamp
│
└── README.md                     # Documentation & upgrade roadmap
```

---

## 🚀 How to Run

### Option A: Master Interactive Menu (Full Arrow-Key Navigation)
Run **`ubat.bat`** from any terminal or double-click it:
```text
==========================================================================================
                   UBAT - UNIVERSAL BATTERY OPTIMIZER (HP OMEN 16)
==========================================================================================
 Hardware: HP HP OMEN Gaming Laptop 16-am0xxx  |  CPU: Intel(R) Core(TM) i7-14650HX

 Choose a toolkit module to execute:
 (Use [↑ / ↓] Arrow Keys to navigate, [Enter] to select, or tap [0-9])

  ► [1] Launch Live Monitor          - Flicker-free live wattage, power breakdown & process table
    [2] Battery Health Model         - Calibrated health %, cycle life, degradation grade & pack balance
    [3] Optimize Laptop Battery      - Safe CPU boost capping (99%), PCIe ASPM & OEM guidance
    [4] Start Background Logger      - 30s silent crash-proof session recording into logs/
    [5] Stop Background Logger       - Terminate active background recording daemon
    [6] Generate Test Report         - Statistical analysis, average Watts, battery drop & Markdown export
    [7] Process Manager & Killer     - Task Manager parallel table & interactive PID killer
    [8] NVMe SSD Health & Speed     - Storage throughput (MB/s), active disk %, drive health & APST draw
    [9] Open Logs Folder             - Open ubat/logs/ folder in Windows File Explorer
    [0] Exit                         - Exit ubat toolkit

------------------------------------------------------------------------------------------
 Controls: [↑ / ↓] Move Selection  |  [Enter / Space] Select  |  [0-9] Quick Jump  |  [Q] Exit
```

### Option B: Quick 1-Click Launchers
* **Live Monitor with Partition Picker:** Double-click `Run-Live-Monitor.bat`
* **Optimize Laptop:** Double-click `Optimize-Laptop.bat`
* **Start Drain Test:** Double-click `Start-Test-Logger.bat`
* **Stop Drain Test:** Double-click `Stop-Test-Logger.bat`
* **View Drain Report:** Double-click `Generate-Report.bat`
