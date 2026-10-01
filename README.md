# ⚡ ubat - Universal Battery & Hardware Telemetry Tool

**ubat** is a modular, hardware-adaptive power diagnostic and optimization toolkit designed for **ANY Windows laptop** (HP OMEN, Lenovo Legion, ASUS ROG, Dell XPS, Acer Nitro, MSI, Surface, etc.).

---

## 🌟 Dynamic Laptop Branding & Partitioned Views

Whenever **ubat** runs on any PC, it automatically detects the exact brand and hardware, branding the monitor directly:
* On HP OMEN: `HP OMEN GAMING LAPTOP 16 - BATTERY, CPU, RAM & POWER MONITOR`
* On Lenovo: `LENOVO LEGION 5 - BATTERY, CPU, RAM & POWER MONITOR`
* On ASUS: `ASUS ROG ZEPHYRUS - BATTERY, CPU, RAM & POWER MONITOR`
* On Dell: `DELL XPS 15 - BATTERY, CPU, RAM & POWER MONITOR`

### 🎛️ Three Flexible Interfaces (Terminal, Web, & Native Console)
**ubat** now supports three distinct interface layers:
1. **🌈 Rich Animated Terminal UI (Python & Rich Engine):** Cyberpunk neon styling, smooth ANSI animations, multi-core visualizers, live GPU wattage & interactive hotkeys.
2. **🌐 Modern Web & App Dashboard (HTML + CSS + JS):** Futuristic dark-mode control center with glowing circular battery SVG dials, real-time Canvas charts, and Task Manager process manager.
3. **⚡ Native Motionless Console Monitor (PowerShell):** Zero-dependency, flicker-free in-place console monitor with 6 partition views.

---

## 📁 Modular Subfolder Architecture

```text
ubat/
│
├── ubat.bat                      # 🎯 Master Interactive Menu Launcher (Options 1 - 0)
├── Run-TUI.bat                   # 🌈 Quick Launch: Rich Animated Python Terminal UI
├── Launch-Web-Dashboard.bat      # 🌐 Quick Launch: Modern Web & App Dashboard in browser
├── Run-Live-Monitor.bat          # 🚀 Quick Launch: Partitioned live telemetry dashboard
├── Optimize-Laptop.bat           # ⚡ Quick Launch: Auto-profile hardware & optimize power plan
├── Start-Test-Logger.bat         # ⏺️ Quick Launch: Start background drain test recorder
├── Stop-Test-Logger.bat          # ⏹️ Quick Launch: Stop background drain test recorder
├── Generate-Report.bat           # 📊 Quick Launch: Instant statistical analysis & summary
│
├── tui/                          # 🌈 Rich Animated Terminal Interface (Python)
│   └── ubat_tui.py               # Neon dashboard with live animations, GPU stats & process killer
│
├── web/                          # 🌐 Modern Web & App Dashboard (HTML / CSS / JS / Python)
│   ├── index.html                # Cyberpunk glassmorphic control center
│   ├── style.css                 # Obsidian dark theme, glowing SVG gauges & animations
│   ├── app.js                    # Live telemetry poller, Canvas charts & process filter
│   └── server.py                 # Zero-dependency local telemetry API server (port 5050)
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
