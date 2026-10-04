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
1. **Live System Monitor (Python & Rich Engine):** Instantaneous 25ms keystroke response, btop-style dynamic micro-gauges, NVMe SSD partition meters, SMART wear degradation %, DDR5 RAM speed, NVIDIA PCIe link negotiation, native CPU thermal zones, in-terminal session logs, and interactive PID killer.
2. **Native Console Hub (PowerShell):** Zero-dependency, flicker-free in-place console monitor with nested sub-menus ("option inside an option") and comprehensive "all option in one option" views.
3. **Native Deep Sensor & Hardware Matrix:** 100% native hardware and sensor inspection embedded directly in code. Zero external app dependency - queries Motherboard (HP 8D3F), BIOS version/date (F.14), ACPI CPU thermal zones (MSAcpi), processor clock frequencies, deep NVIDIA dGPU telemetry (clocks, VRAM, PCIe Gen5 x8, throttle codes), DDR5 SPD topology, and NVMe SMART reliability counters.

---

## Modular Subfolder Architecture

```text
ubat/
|
+-- omni.bat                      # Master Executable Launcher (Runs OMNI live terminal monitor directly)
+-- ubat.bat                      # Backward-compatible CLI Launcher
+-- Run-TUI.bat                   # 1-Click Launch: Python Live System Monitor
+-- Run-Live-Monitor.bat          # 1-Click Launch: Native PowerShell Console Monitor
+-- Optimize-Laptop.bat           # 1-Click Launch: Auto-profile hardware & optimize power settings
+-- Start-Test-Logger.bat         # 1-Click Launch: Start background drain test recorder
+-- Stop-Test-Logger.bat          # 1-Click Launch: Stop background drain test recorder
+-- Generate-Report.bat           # 1-Click Launch: Instant statistical analysis & summary
+-- Sync-Git.bat                  # 1-Click Git Synchronizer: Keeps local and GitHub in sync
|
+-- tui/                          # Flagship Terminal Interface (Python)
|   +-- ubat_tui.py               # Live monitor with btop gauges, partition meters & instant controls
|   \-- hwinfo_bridge.py          # Zero-latency mmap bridge for HWiNFO_SENS_SM2 shared memory
|
+-- core/                         # Core Hardware Profiling Engine
|   +-- HardwareProfile.ps1       # Auto-detects OEM, Motherboard, BIOS, CPU thermals, GPUs, DDR5, NVMe SMART
|   \-- BatteryHealthModel.ps1    # Algorithmic health grade, calibrated charge %, & cycle life
|
+-- monitor/                      # Live Visualization Module
|   \-- LiveMonitor.ps1           # Dynamic branded UI with partitioned views
|
+-- optimizer/                    # Hardware Optimization Engine
|   +-- SsdOptimizer.ps1          # Volume ReTrim, Windows TRIM subsystem & cache wear reduction
|   \-- PowerOptimizer.ps1        # Safe CPU boost capping (99%), PCIe ASPM & thermal tuning
|
+-- logger/                       # Background Crash-Proof Recording Daemon
|   +-- BackgroundLogger.ps1      # 30-second silent fail-safe logger (saves into logs/)
|   \-- StopLogger.ps1            # PID-based background daemon terminator
|
+-- analyzer/                     # Statistical Analytics & Reporting Engine
|   +-- LogAnalyzer.ps1           # Calculates average watts, drop %, runtime, and exports Markdown
|   \-- ViewLogs.ps1              # In-terminal session log viewer with File Explorer shortcut
|
+-- diagnostics/                  # Hardware Diagnostic & Benchmark Utilities
|   +-- BenchmarkEngine.ps1       # Native PowerShell storage read, CPU stress & RAM benchmark
|   +-- bench_engine.py           # High-precision Python storage read, CPU stress & RAM benchmark
|   +-- ProcessManager.ps1        # High-speed process table & interactive PID killer (<20ms)
|   +-- SsdDiagnostics.ps1        # Partition tables, file systems, SMART wear % & throughput
|   \-- MeasureCpuDelta.ps1       # Process-level instantaneous CPU spike detector
|
+-- logs/                         # Dedicated Logs Directory (All data saved here)
|   +-- current-session.csv       # Active test session log
|   +-- last-report.md            # Most recently generated statistical Markdown report
|   \-- archive/                  # Historical test sessions saved by timestamp
|
\-- README.md                     # Documentation & project structure
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
 (Use [Up / Down] Arrow Keys to navigate, [Enter] to select, or tap [0-7])

  > [1] Live System Monitor      - All-in-One real-time terminal telemetry engine
    [2] Storage & SSD Hub        - Partitions, SMART wear, TRIM & NVMe read benchmark
    [3] Battery & Health Hub     - Calibrated health %, wear level, cycle count & battery tuner
    [4] CPU & Memory Hub         - Multi-thread loads, thermals, CPU stress & RAM bandwidth
    [5] Process Manager Hub      - Fast resource monitor & interactive PID killer
    [6] Session Logs & Reports   - In-terminal session logs, analysis reports & folder access
    [7] Benchmark & Stress Hub   - Storage read speeds, multi-core CPU stress & RAM bandwidth
    [0] Exit                     - Exit OMNI toolkit

------------------------------------------------------------------------------------------
 Controls: [Up / Down] Move Selection  |  [Enter / Space] Select  |  [0-7] Quick Jump  |  [Q] Exit
```

### Option B: Direct Terminal Launch
Typing **`omni`** or **`ubat`** from any terminal opens the live monitor directly:
* Python dependencies (`rich`, `psutil`) are automatically verified or installed from `requirements.txt`.
* Arrow keys `[<- / ->]` or `[1-9]` cycle between All, Battery, CPU, RAM, GPU, Storage, Processes, Logs, and Sensors views.
* `[G]` or `[9]` switches directly to the dedicated GPU focus view with VRAM bars, clocks, PCIe link, power draw, and throttle flags.
* `[M]` toggles between Minimized (clean overview) and Expanded (per-core matrix) CPU modes (persisted in `ubat-prefs.json`).
* `[B]` launches the interactive Benchmark & Hardware Stress Testing Suite with selectable 10s, 30s, or 60s durations.
* `[8]` or `[H]` opens the Native Deep Sensor Matrix and triggers an instant hardware bus poll.
* `[T]` triggers real-time volume TRIM & SSD optimization on all mounted partitions.
* `[O]` opens the `logs` folder in Windows File Explorer.
* `[K]` prompts for PID termination directly inside the terminal with forceful kill capability.
* `[R]` cycles refresh intervals (0.5s, 1.0s, 2.0s, 5.0s, 10.0s) and persists user preference.
* `[S]` toggles process sorting (CPU vs RAM).
* `[F]` toggles process filtering (All vs Heavy) with optimized low-noise thresholds.
* `[Q]` exits the monitor cleanly.

---

## Decentralized Hardware Telemetry Architecture

Rather than isolating telemetry into a single disconnected area, **OMNI** distributes metrics directly into their natural functional domains:

1. **CPU Hub & Focus View (`[3]` or `ubat.ps1 [4]`):**
   * Motherboard model & vendor (HP 8D3F)
   * System BIOS version & release date (F.14)
   * Live ACPI thermal zone temperature (MSAcpi_ThermalZoneTemperature)
   * Average processor clock frequency (MHz)
   * Multi-Core CPU Stress Test results (peak thermal rise, delta, throttle state)
   * CPU Computational Benchmark scoring (single-thread & multi-thread scaling)

2. **Storage & SSD Hub (`[5]` or `ubat.ps1 [2]`):**
   * Physical drive identification & SMART health state
   * Lifetime wear degradation percentage & remaining endurance
   * Controller operating temperature (C)
   * High-precision NVMe Sequential Read Throughput (MB/s)
   * 4K Random Read Throughput (MB/s), IOPS, and average access latency (ms)
   * File system volume TRIM & write wear optimizer

3. **Memory & RAM Hub (`[4]` or `ubat.ps1 [4]`):**
   * Configured DDR5 bus clock speed (e.g., 5600 MT/s)
   * Physical SPD memory module bank topology (SK Hynix part numbers, per-slot GB)
   * Physical memory read & copy bandwidth benchmarks (GB/s)

---

## Benchmark & Hardware Stress Testing Suite

The benchmark engine provides safe, non-destructive hardware testing available both via Python (`diagnostics/bench_engine.py`) and PowerShell (`diagnostics/BenchmarkEngine.ps1`):

* **NVMe Storage Read Benchmark:**
  Measures pure sequential read throughput (1MB blocks) and 4K unbuffered random read throughput, calculating real-world IOPS and sub-millisecond access latency. Tests are executed against a safe, transient test block in the system temp directory and cleaned up immediately.
* **Multi-Core CPU Stress Test:**
  Saturates all physical cores and logical threads with high-intensity floating-point math workloads (10s or 30s). Continuously monitors ACPI thermal zone rise and clock frequency dips to detect hardware thermal throttling.
* **Dedicated GPU Hardware Stress Test:**
  Leverages the native CUDA Driver API (`nvcuda.dll`) to launch 524,288 concurrent GPU threads executing heavy floating-point fused-multiply-add (FMA) arithmetic. Forces graphics clock frequencies up to maximum boost target (2.7+ GHz), measuring live GPU power draw (Watts), utilization, and diode thermals with zero external GUI app dependencies.
* **Combined Full-System Burn-In Stress Test:**
  Simultaneously saturates all logical CPU cores, dedicated GPU CUDA threads, and system memory bus. Stress-tests laptop cooling fans, vapor chambers, VRMs, and dual-rail power delivery under peak combined wattage.
* **Manual Start / Stop Continuous Stress Test:**
  Provides on-demand interactive burn-in control across Combined Full-System, Dedicated GPU (RTX 5050 CUDA), or Multi-Core CPU targets. Starts immediately upon user keypress ([Enter] or [Space]) and runs continuously under maximum load with real-time in-place thermal and power telemetry until explicitly stopped ([Space], [Enter], [Q], or [Esc]). Cleans up all worker threads and releases CUDA memory contexts safely upon cessation.
* **CPU Computational Benchmark:**
  Runs normalized single-threaded and multi-threaded mathematical workloads, calculating computational scores and multi-core scaling efficiency ratios.
* **RAM Memory Bandwidth Benchmark:**
  Allocates high-speed memory buffers to measure sequential memory read throughput and memory copy rates in GB/s.
* **All-in-One Full System Hardware Benchmark:**
  Executes the entire suite in automated sequence and outputs a comprehensive system performance scorecard.
