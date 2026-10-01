# OMNI - System Hardware Telemetry & Optimizer Suite

**OMNI** is a modular, hardware-adaptive telemetry and optimization toolkit designed for **ANY Windows PC or laptop** (HP OMEN, Lenovo Legion, ASUS ROG, Dell XPS, Acer Nitro, MSI, custom desktops, etc.).

---

## Dynamic Hardware Branding & Partitioned Views

Whenever **OMNI** runs on any PC, it automatically detects the exact brand and hardware:
* On HP OMEN: `OMNI - SYSTEM HARDWARE TELEMETRY & OPTIMIZER (HP OMEN GAMING LAPTOP 16)`
* On Lenovo: `OMNI - SYSTEM HARDWARE TELEMETRY & OPTIMIZER (LENOVO LEGION 5)`
* On ASUS: `OMNI - SYSTEM HARDWARE TELEMETRY & OPTIMIZER (ASUS ROG ZEPHYRUS)`
* On Dell: `OMNI - SYSTEM HARDWARE TELEMETRY & OPTIMIZER (DELL XPS 15)`

### High-Performance Terminal Interface
**OMNI** provides clean, high-performance terminal environments:
1. **Live System Monitor (Python & Rich Engine):** Instantaneous 25ms keystroke response, btop-style dynamic micro-gauges, NVMe SSD partition meters, SMART wear degradation %, in-terminal session logs, and interactive PID killer.
2. **Native Console Hub (PowerShell):** Zero-dependency, flicker-free in-place console monitor with nested sub-menus ("option inside an option") and comprehensive "all option in one option" views.

---

## Modular Subfolder Architecture

```text
ubat/
│
├── omni.bat                      # Master Executable Launcher (Runs OMNI live terminal monitor directly)
├── ubat.bat                      # Backward-compatible CLI Launcher
├── Run-TUI.bat                   # 1-Click Launch: Python Live System Monitor
├── Run-Live-Monitor.bat          # 1-Click Launch: Native PowerShell Console Monitor
├── Optimize-Laptop.bat           # 1-Click Launch: Auto-profile hardware & optimize power settings
├── Start-Test-Logger.bat         # 1-Click Launch: Start background drain test recorder
├── Stop-Test-Logger.bat          # 1-Click Launch: Stop background drain test recorder
├── Generate-Report.bat           # 1-Click Launch: Instant statistical analysis & summary
├── Sync-Git.bat                  # 1-Click Git Synchronizer: Keeps local and GitHub in sync
│
├── tui/                          # Flagship Terminal Interface (Python)
│   └── ubat_tui.py               # Live monitor with btop gauges, partition meters & instant controls
│
├── core/                         # Core Hardware Profiling Engine
│   ├── HardwareProfile.ps1       # Auto-detects OEM, CPU, GPUs, Battery Design & Live Metrics
│   └── BatteryHealthModel.ps1    # Algorithmic health grade, calibrated charge %, & cycle life
│
├── monitor/                      # Live Visualization Module
│   └── LiveMonitor.ps1           # Dynamic branded UI with partitioned views
│
├── optimizer/                    # Hardware Optimization Engine
│   ├── SsdOptimizer.ps1          # Volume ReTrim, Windows TRIM subsystem & cache wear reduction
│   └── PowerOptimizer.ps1        # Safe CPU boost capping (99%), PCIe ASPM & thermal tuning
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
│   ├── ProcessManager.ps1        # High-speed process table & interactive PID killer (<20ms)
│   ├── SsdDiagnostics.ps1        # Partition tables, file systems, SMART wear % & throughput
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

### Option A: Master Subsystem Menu ("Option inside an Option" & "All in One")
Run **`omni --menu`** or **`ubat --menu`**:
```text
==========================================================================================
             OMNI - SYSTEM HARDWARE TELEMETRY & OPTIMIZER (HP OMEN 16)
==========================================================================================
 Hardware: HP OMEN Gaming Laptop 16-am0xxx  |  CPU: Intel(R) Core(TM) i7-14650HX

 Choose a hardware subsystem to inspect:
 (Use [Up / Down] Arrow Keys to navigate, [Enter] to select, or tap [0-6])

  > [1] Live System Monitor      - All-in-One real-time terminal telemetry engine
    [2] Storage & SSD Hub        - Partitions, file systems, SMART wear & SSD TRIM optimizer
    [3] Battery & Health Hub     - Calibrated health %, wear level, cycle count & battery tuner
    [4] CPU & Memory Hub         - Multi-thread core loads, RAM volume & frequency limits
    [5] Process Manager Hub      - Fast resource monitor & interactive PID killer
    [6] Session Logs & Reports   - In-terminal session logs, analysis reports & folder access
    [0] Exit                     - Exit OMNI toolkit

------------------------------------------------------------------------------------------
 Controls: [Up / Down] Move Selection  |  [Enter / Space] Select  |  [0-6] Quick Jump  |  [Q] Exit
```

### Option B: Direct Terminal Launch
Typing **`omni`** or **`ubat`** from any terminal opens the live monitor directly:
- Arrow keys `[<- / ->]` or `[1-7]` cycle between All, Battery, CPU, RAM, Storage, Processes, and Logs views.
- `[T]` triggers real-time volume TRIM & SSD optimization on all mounted partitions.
- `[O]` opens the `logs` folder in Windows File Explorer.
- `[K]` prompts for PID termination directly inside the terminal.
