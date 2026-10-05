# OMNI Architecture & System Specification

## 1. High-Level Architecture Overview

OMNI (Unified Battery & System Optimization Suite) is an engineering-grade hardware telemetry, benchmarking, and power tuning toolkit designed for high-performance mobile workstations and gaming laptops (such as the HP OMEN series).

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                OMNI ARCHITECTURE                                       │
│                                                                                        │
│   ┌────────────────────────┐      ┌───────────────────────┐      ┌─────────────────┐   │
│   │    PowerShell Core     │ <──> │  Python Rich Engine   │ <──> │  Native Sensor  │   │
│   │       (ubat.ps1)       │      │   (tui/ubat_tui.py)   │      │ (NVML/WMI/DTT)  │   │
│   └────────────────────────┘      └───────────────────────┘      └─────────────────┘   │
│               │                               │                                        │
│               ▼                               ▼                                        │
│   ┌────────────────────────┐      ┌───────────────────────┐      ┌─────────────────┐   │
│   │  Storage & Diagnostics │      │  Battery Optimization │      │ Hardware Stress │   │
│   │   (NVMe / TRIM / SMART)│      │  (PowerPlan / ASPM)   │      │  (CPU/GPU/RAM)  │   │
│   └────────────────────────┘      └───────────────────────┘      └─────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Core Subsystems

### 2.1 Orchestrator & CLI Entry (`ubat.ps1`)
- **Single Source of Truth**: Coordinates menu navigation, environment pre-flight dependency installation (`rich`, `psutil`), and invokes underlying diagnostic modules.
- **Unified Navigation Engine**: Driven by `core/ConsoleHelpers.ps1` with zero-flicker ANSI cursor positioning, terminal resize detection, and enclosed container card frames.

### 2.2 Live Telemetry Engine (`tui/ubat_tui.py` & `monitor/LiveMonitor.ps1`)
- **Dual Runtime Architecture**: High-speed Python Rich TUI with native WMI/PowerShell fallback when Python is unavailable.
- **Hardware Telemetry Sources**:
  - Intel Core 14th Gen Hybrid Architecture (P-Cores + E-Cores thread grid).
  - NVIDIA RTX Dedicated GPU (core clocks, memory load, CUDA state).
  - DDR5 High-Bandwidth Memory (utilization, active commit charge).
  - NVMe SSD PCIe 4.0 Storage (read/write speed, SMART wear level, controller health).

### 2.3 Hardware Benchmark & Stress Engine (`diagnostics/BenchmarkEngine.ps1`)
- **Storage Read Throughput**: High-speed sequential and 4K random read tests with live MB/s measurement.
- **Multi-Core CPU Thermal Stress**: Multi-threaded mathematical saturation across all logical cores with throttle monitoring.
- **CUDA GPU Hardware Stress**: Matrix-multiplication stress on dedicated NVIDIA GPU with 524,288 threads.
- **Physical RAM Saturation**: Allocates and churns up to 95% of physical DDR5 memory to verify stability under extreme memory bus load.

### 2.4 Battery & Power Optimization (`optimizer/BatteryOptimizer.ps1` & `optimizer/PowerOptimizer.ps1`)
- **Health Calibration**: Computes real-world wear level from factory design capacity vs full charge capacity.
- **Power Delivery Tuning**: Configures PCIe ASPM (Active State Power Management), caps excessive CPU boost on battery (DC), and purges background wake-up triggers.

---

## 3. UI/TUI Design System

OMNI features a **Deep Modern Enclosed Container Card Frame**:
- **Border Geometry**: Rounded corners (`╭`, `╮`, `╰`, `╯`) with structural tee dividers (`├`, `┤`) and rails (`│`, `─`).
- **Column Alignment**: Dynamic padding ensures all separators (`─`) and descriptions line up in a single vertical column regardless of title length.
- **Responsive Geometry**: Dynamically adapts between 40 and 102 columns based on live terminal dimensions.
- **No Numbers / Direct Keyboard Navigation**: Seamless navigation via `[↑/↓]` Arrow keys, `[Enter/Space]` selection, and `[Esc/Q]` exit.
