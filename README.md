# ubat - Universal Battery & Hardware Telemetry Tool

**ubat** is a modular, hardware-adaptive power diagnostic and optimization toolkit designed for **ANY Windows laptop** (HP OMEN, Lenovo Legion, ASUS ROG, Dell XPS, Acer Nitro, MSI, Surface, etc.).

---

## Dynamic Laptop Branding & Partitioned Views

Whenever **ubat** runs on any PC, it automatically detects the exact brand and hardware, branding the monitor directly:
* On HP OMEN: `HP OMEN GAMING LAPTOP 16 - BATTERY, CPU, RAM & POWER MONITOR`
* On Lenovo: `LENOVO LEGION 5 - BATTERY, CPU, RAM & POWER MONITOR`
* On ASUS: `ASUS ROG ZEPHYRUS - BATTERY, CPU, RAM & POWER MONITOR`
* On Dell: `DELL XPS 15 - BATTERY, CPU, RAM & POWER MONITOR`

### High-Performance Terminal Interface
**ubat** provides clean, high-performance terminal environments:
1. **Live Terminal Monitor (Python & Rich Engine):** Instantaneous 25ms keystroke response, Task Manager-style color heatmap shading, multi-core visualizers, live GPU wattage, in-terminal session log viewer, and interactive PID killer.
2. **Native Console Monitor (PowerShell):** Zero-dependency, flicker-free in-place console monitor with partitioned views.

---

## Modular Subfolder Architecture

```text
ubat/
│
├── ubat.bat                      # Master Executable Launcher (Runs live terminal monitor directly)
├── Run-TUI.bat                   # 1-Click Launch: Python Live Terminal Monitor
├── Run-Live-Monitor.bat          # 1-Click Launch: Native PowerShell Console Monitor
├── Optimize-Laptop.bat           # 1-Click Launch: Auto-profile hardware & optimize power plan
├── Start-Test-Logger.bat         # 1-Click Launch: Start background drain test recorder
├── Stop-Test-Logger.bat          # 1-Click Launch: Stop background drain test recorder
├── Generate-Report.bat           # 1-Click Launch: Instant statistical analysis & summary
│
├── tui/                          # Flagship Terminal Interface (Python)
│   └── ubat_tui.py               # Live monitor with Task Manager heatmaps, logs view & instant controls
│
├── core/                         # Core Hardware Profiling Engine
│   ├── HardwareProfile.ps1       # Auto-detects OEM, CPU, GPUs, Battery Design & Live Metrics
│   └── BatteryHealthModel.ps1    # Algorithmic health grade, calibrated charge %, & cycle life
│
├── monitor/                      # Live Visualization Module
│   └── LiveMonitor.ps1           # Dynamic branded UI with partitioned views
│
├── optimizer/                    # Power Plan & Hardware Tuning Module
│   └── PowerOptimizer.ps1        # Safe CPU boost capping (99%), PCIe ASPM, & GPU tuning
│
├── logger/                       # Background Crash-Proof Recording Daemon
│   ├── BackgroundLogger.ps1      # 30-second silent fail-safe logger (saves into logs/)
│   └── StopLogger.ps1            # PID-based background daemon terminator
│
├── analyzer/                     # Statistical Analytics & Reporting Engine
│   ├── LogAnalyzer.ps1           # Calculates average watts, drop %, runtime, and exports Markdown
│   └── ViewLogs.ps1              # In-terminal session log viewer with File Explorer shortcut
│
├── diagnostics/                  # Hardware Diagnostic Utilities
│   ├── ProcessManager.ps1        # Task Manager-style parallel table & interactive PID killer
│   ├── SsdDiagnostics.ps1        # NVMe SSD throughput, health status, & storage power
│   └── MeasureCpuDelta.ps1       # Process-level instantaneous CPU spike detector
│
├── logs/                         # Dedicated Logs Directory (All data saved here)
│   ├── current-session.csv       # Active test session log
│   ├── last-report.md            # Most recently generated statistical Markdown report
│   └── archive/                  # Historical test sessions saved by timestamp
│
└── README.md                     # Documentation & project structure
```

---

## How to Run

### Option A: Master Interactive Menu (Full Arrow-Key Navigation)
Run **`ubat --menu`** or run **`ubat.ps1`**:
```text
==========================================================================================
                   UBAT - UNIVERSAL BATTERY OPTIMIZER (HP OMEN 16)
==========================================================================================
 Hardware: HP HP OMEN Gaming Laptop 16-am0xxx  |  CPU: Intel(R) Core(TM) i7-14650HX

 Choose a toolkit module to execute:
 (Use [↑ / ↓] Arrow Keys to navigate, [Enter] to select, or tap [0-9])

  ► [1] Live Monitor             - Real-time battery, CPU, GPU & Task Manager heatmaps
    [2] Battery Health           - Calibrated health %, wear level, cycle count & pack grade
    [3] Battery Optimizer        - Tune power schemes, PCIe ASPM & safe CPU boost limits
    [4] Process Manager          - Task Manager process table & interactive PID killer
    [5] Storage Diagnostics      - NVMe SSD read/write speeds, drive health & APST draw
    [6] Start Session Logger     - Record battery and power usage every 30s in background
    [7] Stop Session Logger      - Terminate active background battery recording daemon
    [8] Generate Test Report     - Statistical analysis, average drain Watts & runtime
    [9] View Session Logs        - Show logs in terminal (with option to open folder)
    [0] Exit                     - Exit ubat toolkit

------------------------------------------------------------------------------------------
 Controls: [↑ / ↓] Move Selection  |  [Enter / Space] Select  |  [0-9] Quick Jump  |  [Q] Exit
```

### Option B: Direct Terminal Launch
Typing **`ubat`** from any terminal opens the live monitor directly:
- Arrow keys `[<- / ->]` or `[1-7]` cycle between All, Battery, CPU, RAM, GPU/SSD, Processes, and Logs views.
- `[O]` opens the `logs` folder in Windows File Explorer.
- `[K]` prompts for PID termination directly inside the terminal.
- `[P]` toggles power schemes (HP OMEN Unbundle vs Balanced).
