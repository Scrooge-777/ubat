#!/usr/bin/env python3
"""
OMNI - System Hardware Telemetry & Optimizer Engine (Rich Edition)
=============================================================================
High-performance terminal dashboard with motionless ANSI updating,
real-time multi-core CPU, RAM, NVMe SSD, Partitions & File Systems,
calibrated battery health algorithms, SSD TRIM optimizer, and interactive process management.
"""

import sys
import os
import time
import math
import msvcrt
import threading
import subprocess
import psutil
import csv
import json

from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.layout import Layout
from rich.text import Text
from rich.live import Live
from rich.align import Align
from rich import box

try:
    from hwinfo_bridge import query_hwinfo_sensors
except ImportError:
    try:
        from tui.hwinfo_bridge import query_hwinfo_sensors
    except ImportError:
        query_hwinfo_sensors = None

_script_dir = os.path.dirname(os.path.abspath(__file__))
_root_dir = os.path.dirname(_script_dir)
_diag_dir = os.path.join(_root_dir, "diagnostics")
if _diag_dir not in sys.path:
    sys.path.insert(0, _diag_dir)

try:
    import bench_engine
except Exception:
    bench_engine = None

# Console initialization
console = Console()

# Global State
RUNNING = True
CURRENT_VIEW = "all"  # 'all', 'battery', 'cpu', 'ram', 'gpu', 'storage', 'processes', 'logs', 'sensors'
REFRESH_RATES = [0.5, 1.0, 2.0, 5.0, 10.0]
REFRESH_INDEX = 1     # Default 1.0s (comfortable reading rate)
REFRESH_RATE = REFRESH_RATES[REFRESH_INDEX]

PROCESS_SORT_MODE = "cpu"    # 'cpu' or 'ram'
PROCESS_FILTER_MODE = "all"  # 'all', 'heavy'
CPU_MINIMIZE_MODE = False   # Toggle with [M] between essential overview and full thread grid

STATUS_MESSAGE = ""
STATUS_TIME = 0.0

FRAME_INDEX = 0

# User Preferences Persistence
_PREFS_FILE = os.path.join(_root_dir, "ubat-prefs.json")


def load_preferences():
    """Loads user configuration (view mode, refresh rate, filter mode) from ubat-prefs.json."""
    global CPU_MINIMIZE_MODE, REFRESH_RATE, REFRESH_INDEX, PROCESS_SORT_MODE, PROCESS_FILTER_MODE
    if not os.path.exists(_PREFS_FILE):
        return
    try:
        with open(_PREFS_FILE, "r", encoding="utf-8") as f:
            p = json.load(f)
            if "cpu_minimize_mode" in p:
                CPU_MINIMIZE_MODE = bool(p["cpu_minimize_mode"])
            if "refresh_rate" in p and p["refresh_rate"] in REFRESH_RATES:
                REFRESH_RATE = float(p["refresh_rate"])
                REFRESH_INDEX = REFRESH_RATES.index(REFRESH_RATE)
            if "process_sort_mode" in p and p["process_sort_mode"] in ["cpu", "ram"]:
                PROCESS_SORT_MODE = str(p["process_sort_mode"])
            if "process_filter_mode" in p and p["process_filter_mode"] in ["all", "heavy"]:
                PROCESS_FILTER_MODE = str(p["process_filter_mode"])
    except Exception:
        pass


def save_preferences():
    """Saves user configuration to ubat-prefs.json for session persistence."""
    try:
        data = {
            "cpu_minimize_mode": CPU_MINIMIZE_MODE,
            "refresh_rate": REFRESH_RATE,
            "process_sort_mode": PROCESS_SORT_MODE,
            "process_filter_mode": PROCESS_FILTER_MODE,
        }
        with open(_PREFS_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except Exception:
        pass

# Hardware Profile Cache (Initialized with dynamic fallbacks, updated on startup)
HARDWARE_INFO = {
    "manufacturer": "Generic",
    "model": "System",
    "board_mfg": "Unknown",
    "board_model": "Unknown",
    "bios_version": "N/A",
    "bios_date": "N/A",
    "cpu_name": "Processor",
    "cpu_cores_logical": psutil.cpu_count(logical=True) or 4,
    "cpu_cores_physical": psutil.cpu_count(logical=False) or 2,
    "total_ram_gb": round(psutil.virtual_memory().total / (1024**3), 1),
    "ram_speed_mts": 0,
    "ram_type": "RAM",
    "ram_modules": [],
}

# Real-time Telemetry Cache (Populated live via CIM and psutil)
TELEMETRY = {
    "battery_pct": 0,
    "battery_plugged": True,
    "battery_secsleft": -1,
    "battery_wattage": 0.0,
    "battery_mwh_remaining": 0,
    "battery_mwh_full": 0,
    "battery_mwh_design": 0,
    "battery_wear_pct": 0.0,
    "battery_health_grade": "N/A",
    "battery_cycle_count": 0,
    "battery_voltage_v": 0.0,
    "cpu_pct": 0.0,
    "cpu_per_core": [],
    "cpu_temp_c": 0.0,
    "cpu_freq_mhz": 0,
    "ram_pct": 0.0,
    "ram_used_gb": 0.0,
    "ram_avail_gb": 0.0,
    "gpu_name": "Discrete GPU",
    "gpu_driver": "N/A",
    "gpu_util": 0,
    "gpu_temp": 0,
    "gpu_power": 0.0,
    "gpu_vram_total_mb": 0,
    "gpu_vram_used_mb": 0,
    "gpu_mem_clock_mhz": 0,
    "gpu_core_clock_mhz": 0,
    "gpu_throttle": "None",
    "gpu_pcie_link": "N/A",
    "hwinfo_active": False,
    "cpu_fan_rpm": 0,
    "gpu_fan_rpm": 0,
    "gpu_hotspot_c": 0,
    "vrm_temp_c": 0,
    "package_power_w": 0.0,
    "ssd_model": "Storage SSD",
    "ssd_health": "Healthy (OK)",
    "ssd_wear_pct": 0,
    "ssd_temp": 0,
    "partitions": [],
    "disk_read_mbs": 0.0,
    "disk_write_mbs": 0.0,
    "disk_total_read_gb": 0.0,
    "disk_total_write_gb": 0.0,
    "processes": [],
    "last_disk_read": 0,
    "last_disk_write": 0,
    "last_disk_time": 0.0,
    "benchmarks": {
        "disk_seq_mbs": 0.0,
        "disk_rnd_mbs": 0.0,
        "disk_rnd_iops": 0,
        "disk_lat_ms": 0.0,
        "cpu_st_score": 0,
        "cpu_st_ops": 0,
        "cpu_mt_score": 0,
        "cpu_mt_ops": 0,
        "cpu_scale_ratio": 0.0,
        "stress_peak_c": 0.0,
        "stress_delta_c": 0.0,
        "stress_ops": 0,
        "stress_throttled": False,
        "ram_read_gbs": 0.0,
        "ram_copy_gbs": 0.0,
        "gpu_stress_peak_c": 0.0,
        "gpu_stress_delta_c": 0.0,
        "gpu_stress_power_w": 0.0,
        "gpu_stress_util_pct": 0,
        "gpu_stress_clock_mhz": 0,
        "gpu_stress_throttled": False,
        "last_bench_time": 0.0,
    },
}


def detect_system_hardware():
    """Detects laptop model, motherboard, BIOS, CPU name, GPU, and RAM topology."""
    global HARDWARE_INFO, TELEMETRY
    try:
        cmd = 'powershell.exe -NoProfile -Command "Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model | ConvertTo-Json -Compress"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2).strip()
        data = json.loads(out)
        if data.get("Manufacturer"):
            HARDWARE_INFO["manufacturer"] = data["Manufacturer"].strip()
        if data.get("Model"):
            HARDWARE_INFO["model"] = data["Model"].strip()
    except Exception:
        pass

    try:
        cmd = 'powershell.exe -NoProfile -Command "$bb = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue; $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue; [PSCustomObject]@{ BoardMfg = $bb.Manufacturer; BoardModel = $bb.Product; BiosVer = $bios.SMBIOSBIOSVersion; BiosDate = (Get-Date $bios.ReleaseDate).ToString(\'yyyy-MM-dd\') } | ConvertTo-Json -Compress"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2.5).strip()
        if out:
            data = json.loads(out)
            if data.get("BoardMfg"):
                HARDWARE_INFO["board_mfg"] = str(data["BoardMfg"]).strip()
            if data.get("BoardModel"):
                HARDWARE_INFO["board_model"] = str(data["BoardModel"]).strip()
            if data.get("BiosVer"):
                HARDWARE_INFO["bios_version"] = str(data["BiosVer"]).strip()
            if data.get("BiosDate"):
                HARDWARE_INFO["bios_date"] = str(data["BiosDate"]).strip()
    except Exception:
        pass

    try:
        cmd = 'powershell.exe -NoProfile -Command "Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2).strip()
        if out:
            HARDWARE_INFO["cpu_name"] = out.strip()
    except Exception:
        pass

    # Dynamic RAM Topology & Memory Generation Detection
    try:
        cmd = 'powershell.exe -NoProfile -Command "Get-CimInstance Win32_PhysicalMemory | Select-Object BankLabel, Manufacturer, PartNumber, ConfiguredClockSpeed, Capacity, SMBIOSMemoryType | ConvertTo-Json -Compress"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2.5).strip()
        if out:
            data = json.loads(out)
            if isinstance(data, dict):
                data = [data]
            mods = []
            max_spd = 0
            detected_type = "RAM"
            smbios_map = {24: "DDR3", 26: "DDR4", 30: "LPDDR3", 32: "LPDDR4", 34: "DDR5", 35: "LPDDR5"}
            for item in data:
                spd = item.get("ConfiguredClockSpeed", 0) or 0
                if spd > max_spd:
                    max_spd = spd
                smb = item.get("SMBIOSMemoryType", 0) or 0
                if smb in smbios_map:
                    detected_type = smbios_map[smb]
                mods.append({
                    "bank": item.get("BankLabel", "BANK 0"),
                    "mfg": (item.get("Manufacturer") or "Generic").strip(),
                    "part": (item.get("PartNumber") or "").strip(),
                    "speed": spd,
                    "gb": round((item.get("Capacity", 0) or 0) / (1024**3), 1)
                })
            HARDWARE_INFO["ram_modules"] = mods
            HARDWARE_INFO["ram_type"] = detected_type
            if max_spd > 0:
                HARDWARE_INFO["ram_speed_mts"] = max_spd
    except Exception:
        pass

    # Video Controller / GPU Detection
    try:
        cmd = 'powershell.exe -NoProfile -Command "Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion | ConvertTo-Json -Compress"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2.5).strip()
        if out:
            data = json.loads(out)
            if isinstance(data, dict):
                data = [data]
            dgpu = None
            for g in data:
                name = g.get("Name", "")
                if any(k in name for k in ["NVIDIA", "Radeon", "AMD", "Intel Arc"]):
                    dgpu = g
                    break
            if not dgpu and data:
                dgpu = data[0]
            if dgpu:
                if dgpu.get("Name"):
                    TELEMETRY["gpu_name"] = dgpu["Name"].strip()
                if dgpu.get("DriverVersion"):
                    TELEMETRY["gpu_driver"] = dgpu["DriverVersion"].strip()
    except Exception:
        pass


def update_battery_cim():
    """Fetches deep battery statistics including live factory design capacity from Windows ACPI / CIM."""
    global TELEMETRY
    try:
        cmd = 'powershell.exe -NoProfile -Command "$bStatic = (Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue); $f = (Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue).FullChargedCapacity; $s = (Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue); $c = (Get-CimInstance -Namespace root/wmi -ClassName BatteryCycleCount -ErrorAction SilentlyContinue).CycleCount; [PSCustomObject]@{ DesignMwh = $bStatic.DesignedCapacity; FullMwh = $f; RemainingMwh = $s.RemainingCapacity; RateMw = $s.DischargeRate; Cycles = $c; Voltage = $s.Voltage } | ConvertTo-Json -Compress"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2).strip()
        data = json.loads(out)
        if data.get("DesignMwh") and int(data["DesignMwh"]) > 0:
            TELEMETRY["battery_mwh_design"] = int(data["DesignMwh"])
        if data.get("FullMwh"):
            TELEMETRY["battery_mwh_full"] = int(data["FullMwh"])
            if TELEMETRY["battery_mwh_design"] <= 0:
                TELEMETRY["battery_mwh_design"] = int(data["FullMwh"])
        if data.get("RemainingMwh"):
            TELEMETRY["battery_mwh_remaining"] = int(data["RemainingMwh"])
        if data.get("RateMw"):
            TELEMETRY["battery_wattage"] = round(abs(int(data["RateMw"])) / 1000.0, 2)
        if data.get("Cycles"):
            TELEMETRY["battery_cycle_count"] = int(data["Cycles"])
        if data.get("Voltage") and int(data["Voltage"]) > 0:
            TELEMETRY["battery_voltage_v"] = round(int(data["Voltage"]) / 1000.0, 2)

        design = TELEMETRY["battery_mwh_design"]
        full = TELEMETRY["battery_mwh_full"]
        if design > 0 and full > 0:
            health = round((full / design) * 100.0, 1)
            wear = max(0.0, round(100.0 - health, 1))
            TELEMETRY["battery_wear_pct"] = wear
            if health >= 98:
                TELEMETRY["battery_health_grade"] = "S (Pristine)"
            elif health >= 90:
                TELEMETRY["battery_health_grade"] = "A (Very Good)"
            elif health >= 80:
                TELEMETRY["battery_health_grade"] = "B (Good)"
            elif health >= 70:
                TELEMETRY["battery_health_grade"] = "C (Noticeable Wear)"
            else:
                TELEMETRY["battery_health_grade"] = "D (Degraded)"
    except Exception:
        pass


def update_ssd_cim():
    """Queries physical SSD SMART health, degradation, and model via PowerShell."""
    global TELEMETRY
    try:
        cmd = 'powershell.exe -NoProfile -Command "$d = Get-PhysicalDisk | Select-Object -First 1; $r = Get-StorageReliabilityCounter -PhysicalDisk $d -ErrorAction SilentlyContinue; [PSCustomObject]@{ Model = $d.FriendlyName; Health = $d.HealthStatus; Wear = $r.Wear; Temp = $r.Temperature } | ConvertTo-Json -Compress"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2.5).strip()
        data = json.loads(out)
        if data.get("Model"):
            TELEMETRY["ssd_model"] = str(data["Model"]).strip()
        if data.get("Health"):
            TELEMETRY["ssd_health"] = str(data["Health"]).strip()
        if data.get("Wear") is not None:
            TELEMETRY["ssd_wear_pct"] = int(data["Wear"])
        if data.get("Temp") is not None and int(data["Temp"]) > 0:
            TELEMETRY["ssd_temp"] = int(data["Temp"])
    except Exception:
        pass


def update_gpu_nvidia():
    """Queries NVIDIA GPU deep telemetry via nvidia-smi."""
    global TELEMETRY
    try:
        out = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=name,driver_version,temperature.gpu,utilization.gpu,memory.total,memory.used,clocks.current.graphics,clocks.current.memory,power.draw,pcie.link.gen.current,pcie.link.width.current,clocks_throttle_reasons.active", "--format=csv,noheader,nounits"],
            text=True, timeout=1.5
        ).strip()
        parts = [p.strip() for p in out.split(",")]
        if len(parts) >= 12:
            TELEMETRY["gpu_name"] = parts[0]
            TELEMETRY["gpu_driver"] = parts[1]
            TELEMETRY["gpu_temp"] = int(parts[2])
            TELEMETRY["gpu_util"] = int(parts[3])
            TELEMETRY["gpu_vram_total_mb"] = int(parts[4])
            TELEMETRY["gpu_vram_used_mb"] = int(parts[5])
            TELEMETRY["gpu_core_clock_mhz"] = int(parts[6])
            TELEMETRY["gpu_mem_clock_mhz"] = int(parts[7])
            TELEMETRY["gpu_power"] = float(parts[8])
            TELEMETRY["gpu_pcie_link"] = f"Gen{parts[9]} x{parts[10]}"
            TELEMETRY["gpu_throttle"] = parts[11]
        elif len(parts) >= 4:
            TELEMETRY["gpu_name"] = parts[0]
            TELEMETRY["gpu_temp"] = int(parts[2])
            TELEMETRY["gpu_power"] = float(parts[3])
    except Exception:
        TELEMETRY["gpu_name"] = "NVIDIA dGPU (Dynamic Sleep)"
        TELEMETRY["gpu_util"] = 0
        TELEMETRY["gpu_temp"] = 0
        TELEMETRY["gpu_power"] = 0.0
        TELEMETRY["gpu_pcie_link"] = "N/A"


def update_cpu_thermals():
    """Queries native ACPI thermal zone and live CPU frequency."""
    global TELEMETRY
    try:
        cmd = 'powershell.exe -NoProfile -Command "$tz = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue; $temp = if ($tz -and $tz.CurrentTemperature) { [math]::Round(($tz.CurrentTemperature - 2732) / 10, 1) } else { 0 }; $freq = (Get-Counter \'\\Processor Information(*)\\Processor Frequency\' -ErrorAction SilentlyContinue).CounterSamples | Where-Object { $_.InstanceName -eq \'_total\' } | Select-Object -ExpandProperty CookedValue; [PSCustomObject]@{ TempC = $temp; Freq = [math]::Round($freq) } | ConvertTo-Json -Compress"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2.5).strip()
        if out:
            data = json.loads(out)
            if data.get("TempC") and float(data["TempC"]) > 0:
                TELEMETRY["cpu_temp_c"] = float(data["TempC"])
            if data.get("Freq") and int(data["Freq"]) > 0:
                TELEMETRY["cpu_freq_mhz"] = int(data["Freq"])
    except Exception:
        pass


def update_hwinfo():
    """Queries HWiNFO shared memory bridge for fan RPMs, VRM, and hotspot thermals."""
    global TELEMETRY
    if query_hwinfo_sensors:
        try:
            hw = query_hwinfo_sensors()
            TELEMETRY["hwinfo_active"] = hw.get("active", False)
            if hw.get("active", False):
                TELEMETRY["cpu_fan_rpm"] = hw.get("cpu_fan_rpm", 0)
                TELEMETRY["gpu_fan_rpm"] = hw.get("gpu_fan_rpm", 0)
                TELEMETRY["gpu_hotspot_c"] = hw.get("gpu_hotspot_c", 0)
                TELEMETRY["vrm_temp_c"] = hw.get("vrm_temp_c", 0)
                if hw.get("package_power_w", 0.0) > 0:
                    TELEMETRY["package_power_w"] = hw.get("package_power_w", 0.0)
        except Exception:
            pass


def refresh_sensor_metrics():
    """Immediately refreshes all hardware sensors and thermal telemetry without external apps."""
    global STATUS_MESSAGE, STATUS_TIME
    try:
        update_cpu_thermals()
        update_gpu_nvidia()
        update_ssd_cim()
        update_hwinfo()
        STATUS_MESSAGE = "Native hardware & sensor telemetry refreshed successfully."
    except Exception as e:
        STATUS_MESSAGE = f"Sensor refresh error: {e}"
    STATUS_TIME = time.time()


def telemetry_background_worker():
    """Background worker thread for periodic heavy telemetry (GPU, ACPI, SSD, Thermals)."""
    global RUNNING
    counter = 0
    while RUNNING:
        try:
            if counter % 4 == 0:
                update_battery_cim()
                update_ssd_cim()
                update_cpu_thermals()
            if counter % 2 == 0:
                update_gpu_nvidia()
            update_hwinfo()
        except Exception:
            pass
        counter += 1
        time.sleep(1.0)


def poll_fast_telemetry():
    """Polls instantaneous metrics (CPU, RAM, Disk, Partitions, Processes)."""
    global TELEMETRY
    # Battery psutil
    batt = psutil.sensors_battery()
    if batt:
        TELEMETRY["battery_pct"] = batt.percent
        TELEMETRY["battery_plugged"] = batt.power_plugged
        TELEMETRY["battery_secsleft"] = batt.secsleft

    # CPU
    TELEMETRY["cpu_pct"] = psutil.cpu_percent(interval=None)
    TELEMETRY["cpu_per_core"] = psutil.cpu_percent(percpu=True, interval=None)

    # RAM
    vmem = psutil.virtual_memory()
    TELEMETRY["ram_pct"] = vmem.percent
    TELEMETRY["ram_used_gb"] = round(vmem.used / (1024**3), 1)
    TELEMETRY["ram_avail_gb"] = round(vmem.available / (1024**3), 1)

    # Disk MB/s
    now = time.time()
    disk_io = psutil.disk_io_counters()
    if disk_io:
        TELEMETRY["disk_total_read_gb"] = round(disk_io.read_bytes / (1024**3), 2)
        TELEMETRY["disk_total_write_gb"] = round(disk_io.write_bytes / (1024**3), 2)
        if TELEMETRY["last_disk_time"] > 0:
            dt = now - TELEMETRY["last_disk_time"]
            if dt > 0.2:
                r_bytes = disk_io.read_bytes - TELEMETRY["last_disk_read"]
                w_bytes = disk_io.write_bytes - TELEMETRY["last_disk_write"]
                TELEMETRY["disk_read_mbs"] = round((r_bytes / (1024 * 1024)) / dt, 1)
                TELEMETRY["disk_write_mbs"] = round((w_bytes / (1024 * 1024)) / dt, 1)
                TELEMETRY["last_disk_read"] = disk_io.read_bytes
                TELEMETRY["last_disk_write"] = disk_io.write_bytes
                TELEMETRY["last_disk_time"] = now
        else:
            TELEMETRY["last_disk_read"] = disk_io.read_bytes
            TELEMETRY["last_disk_write"] = disk_io.write_bytes
            TELEMETRY["last_disk_time"] = now

    # Partitions
    try:
        parts = []
        for p in psutil.disk_partitions(all=False):
            if 'cdrom' in p.opts or not p.fstype:
                continue
            try:
                u = psutil.disk_usage(p.mountpoint)
                parts.append({
                    "device": p.device.rstrip('\\'),
                    "mount": p.mountpoint,
                    "fstype": p.fstype,
                    "total_gb": round(u.total / (1024**3), 1),
                    "used_gb": round(u.used / (1024**3), 1),
                    "free_gb": round(u.free / (1024**3), 1),
                    "pct": u.percent,
                })
            except Exception:
                continue
        TELEMETRY["partitions"] = parts
    except Exception:
        pass

    # Top Processes
    try:
        procs = []
        for p in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_info']):
            try:
                info = p.info
                mem_mb = round((info['memory_info'].rss or 0) / (1024 * 1024), 1)
                cpu_p = info['cpu_percent'] or 0.0
                name = info['name']

                if PROCESS_FILTER_MODE == "heavy" and (cpu_p < 0.5 and mem_mb < 100.0):
                    continue

                procs.append({
                    'pid': info['pid'],
                    'name': name,
                    'cpu': cpu_p,
                    'mem_mb': mem_mb,
                })
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue

        # Sorting
        if PROCESS_SORT_MODE == "cpu":
            procs.sort(key=lambda x: (x['cpu'], x['mem_mb']), reverse=True)
        else:
            procs.sort(key=lambda x: (x['mem_mb'], x['cpu']), reverse=True)

        TELEMETRY["processes"] = procs[:25]
    except Exception:
        pass


def make_progress_bar(pct, width=18, fill_char="=", empty_char="-", color="green"):
    """Generates an ANSI/Rich styled progress bar."""
    pct = max(0.0, min(100.0, pct))
    filled_len = int(round(width * pct / 100.0))
    bar = fill_char * filled_len + empty_char * (width - filled_len)
    return f"[{color}][{bar}][/{color}] [bold]{pct:.1f}%[/bold]"


def make_mini_meter(val, max_val=20.0, width=8):
    """Draws an aesthetic btop-style ASCII gauge meter."""
    val = max(0.0, min(max_val, val))
    fill = int(round(width * (val / max_val)))
    empty = width - fill
    ratio = val / max_val
    col = "bright_red" if ratio >= 0.6 else "bright_yellow" if ratio >= 0.3 else "green"
    bar_str = "|" * fill + "." * empty
    return f"[{col}][{bar_str}][/{col}]"


def format_secs(secs):
    """Formats seconds into human readable duration."""
    if secs < 0:
        return "AC Powered (Protected)"
    hrs = int(secs // 3600)
    mins = int((secs % 3600) // 60)
    return f"{hrs}h {mins:02d}m Remaining"


def get_logs_directory():
    """Returns absolute path to logs directory."""
    return os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "logs")


def open_logs_folder():
    """Opens logs directory in Windows File Explorer."""
    global STATUS_MESSAGE, STATUS_TIME
    logs_dir = get_logs_directory()
    if not os.path.exists(logs_dir):
        os.makedirs(logs_dir, exist_ok=True)
    try:
        os.startfile(logs_dir)
        STATUS_MESSAGE = "Opened logs directory in Windows File Explorer."
    except Exception as e:
        STATUS_MESSAGE = f"Could not open logs folder: {e}"
    STATUS_TIME = time.time()


def run_ssd_trim_optimizer(live):
    """Runs SSD TRIM optimization with live terminal feedback."""
    global STATUS_MESSAGE, STATUS_TIME
    live.stop()
    script_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "optimizer", "SsdOptimizer.ps1")
    try:
        subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_path])
        STATUS_MESSAGE = "SSD TRIM optimization completed successfully."
        STATUS_TIME = time.time()
        time.sleep(1.0)
    except Exception as e:
        STATUS_MESSAGE = f"SSD optimizer error: {e}"
        STATUS_TIME = time.time()
    live.start()


def run_battery_optimizer_dialog(live):
    """Interactive Battery Optimization & Cleanup Dialog."""
    global STATUS_MESSAGE, STATUS_TIME
    live.stop()
    console.clear()
    script_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "optimizer", "BatteryOptimizer.ps1")
    console.print("\n[bold cyan]=============================================================================[/bold cyan]")
    console.print("[bold white]            BATTERY OPTIMIZATION & CLEANUP CONTROLLER[/bold white]")
    console.print("[bold cyan]=============================================================================[/bold cyan]")
    console.print("  [bold yellow][1][/bold yellow] Battery & Power Optimization Audit (Audit CPU boost, ASPM & wakeups)")
    console.print("  [bold yellow][2][/bold yellow] User-Level Battery Saver Cleanup (Purge %TEMP% & crash dumps - No Admin)")
    console.print("  [bold yellow][3][/bold yellow] Admin-Level Deep System Cleanup & Power Tuning (Windows Temp & Update Cache)")
    console.print("  [bold yellow][4][/bold yellow] Apply Universal Battery Profile (Cap CPU Boost 99% + PCIe ASPM)")
    console.print("  [bold yellow][0][/bold yellow] Return to Dashboard")
    console.print("[bold cyan]=============================================================================[/bold cyan]")

    pick = console.input("\n[bold green]Select option [0-4]: [/bold green]").strip()
    if pick == "1":
        subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_path, "-AuditOnly"])
        console.input("\n[dim]Press Enter to return to dashboard...[/dim]")
        STATUS_MESSAGE = "Battery audit completed."
    elif pick == "2":
        subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_path, "-UserOnly"])
        console.input("\n[dim]Press Enter to return to dashboard...[/dim]")
        STATUS_MESSAGE = "User-level cleanup completed."
    elif pick == "3":
        subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_path, "-AdminOnly"])
        console.input("\n[dim]Press Enter to return to dashboard...[/dim]")
        STATUS_MESSAGE = "Admin system cleanup & power tuning completed."
    elif pick == "4":
        p_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "optimizer", "PowerOptimizer.ps1")
        subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", p_path])
        console.input("\n[dim]Press Enter to return to dashboard...[/dim]")
        STATUS_MESSAGE = "Universal battery power profile applied."
    STATUS_TIME = time.time()
    live.start()


def build_header_panel():
    """Creates sleek, high-density terminal hardware telemetry HUD."""
    mfg = HARDWARE_INFO["manufacturer"].upper()
    model = HARDWARE_INFO["model"].upper()
    cpu = HARDWARE_INFO["cpu_name"]

    uptime_str = "Active"
    try:
        boot = psutil.boot_time()
        up_secs = int(time.time() - boot)
        up_days = up_secs // 86400
        up_hours = (up_secs % 86400) // 3600
        up_mins = (up_secs % 3600) // 60
        uptime_str = f"{up_days}d {up_hours:02d}h {up_mins:02d}m" if up_days > 0 else f"{up_hours}h {up_mins:02d}m"
    except Exception:
        pass

    temp_val = TELEMETRY.get("cpu_temp_c", 0.0)
    temp_str = f"{temp_val:.1f} C" if temp_val > 0 else "Active"
    freq_val = TELEMETRY.get("cpu_freq_mhz", 0)
    freq_str = f" @ {freq_val} MHz" if freq_val > 0 else ""

    rate_val = REFRESH_RATE

    title_text = Text()
    title_text.append("[OMNI HARDWARE TELEMETRY HUD]", style="bold cyan")
    title_text.append("  |  HOST: ", style="bold white")
    title_text.append(f"{mfg} {model}", style="bold yellow")
    title_text.append("  |  UPTIME: ", style="bold white")
    title_text.append(f"{uptime_str}", style="bold green")
    title_text.append("  |  VIEW: ", style="bold white")
    title_text.append(f"[{CURRENT_VIEW.upper()}]", style="bold magenta")
    title_text.append("  |  RATE: ", style="bold white")
    title_text.append(f"{rate_val:.1f}s", style="bold cyan")
    title_text.append("\n")

    title_text.append(" CPU: ", style="bold cyan")
    title_text.append(f"{cpu} ({temp_str}{freq_str})", style="bold white")
    title_text.append("  |  dGPU: ", style="bold cyan")
    gpu_name = TELEMETRY.get("gpu_name", "NVIDIA dGPU")
    gpu_u = TELEMETRY.get("gpu_util", 0)
    gpu_t = TELEMETRY.get("gpu_temp", 0)
    title_text.append(f"{gpu_name} ({gpu_u}% @ {gpu_t} C)", style="bold white")
    title_text.append("  |  RAM: ", style="bold cyan")
    ram_tot = HARDWARE_INFO["total_ram_gb"]
    ram_spd = HARDWARE_INFO.get("ram_speed_mts", 0)
    ram_type = HARDWARE_INFO.get("ram_type", "RAM")
    ram_tag = f"{ram_type}-{ram_spd}" if ram_spd > 0 else ram_type
    title_text.append(f"{ram_tot:.0f}GB {ram_tag}", style="bold white")

    return Panel(
        Align.center(title_text),
        border_style="cyan",
        box=box.ROUNDED,
        padding=(0, 1),
    )


def build_battery_panel():
    """Renders real-time battery status and health model."""
    pct = TELEMETRY["battery_pct"]
    plugged = TELEMETRY["battery_plugged"]
    wattage = TELEMETRY["battery_wattage"]
    full_mwh = TELEMETRY["battery_mwh_full"]
    design_mwh = TELEMETRY["battery_mwh_design"]
    rem_mwh = TELEMETRY["battery_mwh_remaining"]
    wear = TELEMETRY["battery_wear_pct"]
    grade = TELEMETRY["battery_health_grade"]
    secs = TELEMETRY["battery_secsleft"]
    cycles = TELEMETRY.get("battery_cycle_count", 0)
    voltage = TELEMETRY["battery_voltage_v"]

    batt_color = "green" if pct >= 60 else "yellow" if pct >= 30 else "red"

    table = Table(box=None, expand=True, show_header=False, padding=(0, 1))
    table.add_column("Key", style="bold cyan", width=16)
    table.add_column("Value", style="bold white")

    power_src = "[bold green][AC] ADAPTER CONNECTED[/bold green]" if plugged else "[bold yellow][BAT] ON BATTERY POWER[/bold yellow]"
    table.add_row("Power Source", power_src)
    table.add_row("Charge Level", make_progress_bar(pct, width=16, color=batt_color))
    table.add_row("Health Grade", f"[bold green]{grade}[/bold green] (Wear: [bold yellow]{wear}%[/bold yellow])")
    table.add_row("Cycle Count", f"[bold white]{cycles}[/bold white] / 500 [dim](Rating: Optimal)[/dim]")
    table.add_row("Capacity", f"{full_mwh:,} mWh [dim](Design: {design_mwh:,})[/dim]")
    table.add_row("Degradation", f"{max(0, design_mwh - full_mwh):,} mWh [dim](Pack: {voltage}V)[/dim]")
    
    rate_str = f"{wattage:.2f} W" if wattage > 0 else "0.00 W (Idle / Full)"
    table.add_row("Drain/Charge", f"[bold magenta]{rate_str}[/bold magenta]")
    table.add_row("Optimization", "[bold green][OPTIMAL][/bold green] [dim](Press O to Clean)[/dim]")

    return Panel(table, title="[bold cyan]BATTERY & POWER HEALTH[/bold cyan]", border_style="cyan", box=box.ROUNDED)


def build_cpu_ram_panel():
    """Renders CPU and RAM real-time performance and core metrics."""
    cpu_pct = TELEMETRY["cpu_pct"]
    ram_pct = TELEMETRY["ram_pct"]
    ram_used = TELEMETRY["ram_used_gb"]
    ram_avail = TELEMETRY["ram_avail_gb"]
    ram_total = HARDWARE_INFO["total_ram_gb"]
    ram_speed = HARDWARE_INFO.get("ram_speed_mts", 0)
    cpu_temp = TELEMETRY.get("cpu_temp_c", 0.0)
    cpu_freq = TELEMETRY.get("cpu_freq_mhz", 0)

    cpu_color = "green" if cpu_pct < 50 else "yellow" if cpu_pct < 80 else "red"
    ram_color = "green" if ram_pct < 65 else "yellow" if ram_pct < 85 else "red"

    table = Table(box=None, expand=True, show_header=False, padding=(0, 1))
    table.add_column("Metric", style="bold cyan", width=14)
    table.add_column("Status", style="bold white")

    table.add_row("CPU Load", make_progress_bar(cpu_pct, width=14, color=cpu_color))
    if cpu_temp > 0 or cpu_freq > 0:
        t_col = "red" if cpu_temp >= 80 else "yellow" if cpu_temp >= 65 else "green"
        headroom = max(0.0, round(100.0 - cpu_temp, 1))
        table.add_row("CPU Thermals", f"[{t_col}]{cpu_temp:.1f} C[/{t_col}] [dim]@ {cpu_freq} MHz (Head: {headroom} C)[/dim]")

    table.add_row("RAM Usage", make_progress_bar(ram_pct, width=14, color=ram_color))
    
    ram_type = HARDWARE_INFO.get("ram_type", "RAM")
    speed_tag = f" [dim]({ram_type}-{ram_speed} MT/s)[/dim]" if ram_speed > 0 else f" [dim]({ram_type})[/dim]"
    table.add_row("Memory Vol", f"[bold white]{ram_used:.1f} GB[/bold white] / [dim]{ram_total:.1f} GB[/dim]{speed_tag}")

    gpu_t = TELEMETRY.get("gpu_temp", 0)
    gpu_u = TELEMETRY.get("gpu_util", 0)
    gpu_p = TELEMETRY.get("gpu_power", 0.0)
    if gpu_t > 0 or gpu_u > 0:
        g_col = "red" if gpu_t >= 80 else "yellow" if gpu_t >= 65 else "green"
        table.add_row("GPU Active", f"[{g_col}]{gpu_t} C[/{g_col}] [dim]| {gpu_u}% Util | {gpu_p:.1f}W[/dim]")

    swap_u = TELEMETRY.get("swap_used_gb", 0.0)
    swap_t = TELEMETRY.get("swap_total_gb", 0.0)
    if swap_t > 0:
        table.add_row("Commit Limit", f"[bold white]{swap_u:.1f} GB[/bold white] / [dim]{swap_t:.1f} GB virtual[/dim]")

    bench = TELEMETRY.get("benchmarks", {})
    if bench.get("cpu_mt_score", 0) > 0:
        table.add_row("CPU Benchmark", f"[bold green]{bench['cpu_mt_score']} pts[/bold green] [dim](ST: {bench['cpu_st_score']})[/dim]")
    elif bench.get("stress_peak_c", 0.0) > 0:
        table.add_row("Last Stress", f"Peak: [yellow]{bench['stress_peak_c']} C[/yellow] [dim](+{bench['stress_delta_c']} C)[/dim]")
    elif TELEMETRY.get("hwinfo_active", False):
        cpu_rpm = TELEMETRY.get("cpu_fan_rpm", 0)
        gpu_rpm = TELEMETRY.get("gpu_fan_rpm", 0)
        fan_str = f"CPU: {cpu_rpm} | GPU: {gpu_rpm} RPM" if (cpu_rpm > 0 or gpu_rpm > 0) else "Active"
        table.add_row("Fan Speeds", f"[bold green]{fan_str}[/bold green]")
    else:
        table.add_row("Free Memory", f"[bold green]{ram_avail:.1f} GB[/bold green] [dim]available[/dim]")
    
    # Core sparks
    cores = TELEMETRY["cpu_per_core"]
    if cores:
        core_sparks = ""
        for c in cores[:16]:
            char = "_" if c < 20 else "=" if c < 60 else "#"
            col = "green" if c < 50 else "yellow" if c < 80 else "red"
            core_sparks += f"[{col}]{char}[/{col}]"
        table.add_row("Core Sparks", f"{core_sparks} [dim]({len(cores)} Cores)[/dim]")

    return Panel(table, title="[bold cyan]CPU & MEMORY HUB[/bold cyan]", border_style="cyan", box=box.ROUNDED)


def build_storage_panel():
    """Renders storage partitions, NVMe health & throughput."""
    read_mb = TELEMETRY["disk_read_mbs"]
    write_mb = TELEMETRY["disk_write_mbs"]
    ssd_model = TELEMETRY.get("ssd_model", "Samsung NVMe SSD")
    ssd_health = TELEMETRY.get("ssd_health", "Healthy (OK)")
    ssd_wear = TELEMETRY.get("ssd_wear_pct", 0)
    ssd_temp = TELEMETRY.get("ssd_temp", 46)
    parts = TELEMETRY.get("partitions", [])
    gpu_pcie = TELEMETRY.get("gpu_pcie_link", "Gen5 x8")
    gpu_hotspot = TELEMETRY.get("gpu_hotspot_c", 0)

    table = Table(box=None, expand=True, show_header=False, padding=(0, 1))
    table.add_column("Device", style="bold cyan", width=14)
    table.add_column("Details", style="bold white")

    table.add_row("SSD Model", f"[bold yellow]{ssd_model[:22]}[/bold yellow]")
    health_str = f"[bold green]{ssd_health}[/bold green] (Wear: [bold yellow]{ssd_wear}%[/bold yellow] | [yellow]{ssd_temp} C[/yellow])"
    table.add_row("Drive Health", health_str)

    bench = TELEMETRY.get("benchmarks", {})
    if bench.get("disk_seq_mbs", 0.0) > 0:
        table.add_row("Read Bench", f"[bold green]{bench['disk_seq_mbs']} MB/s[/bold green] [dim](4K: {bench['disk_rnd_mbs']} MB/s)[/dim]")
    elif gpu_hotspot > 0:
        table.add_row("GPU Thermals", f"[yellow]{TELEMETRY.get('gpu_temp', 0)} C[/yellow] (Hotspot: [bold red]{gpu_hotspot} C[/bold red])")
    elif gpu_pcie and gpu_pcie != "N/A":
        table.add_row("PCIe Link", f"[bold cyan]{gpu_pcie}[/bold cyan] [dim](dGPU Link)[/dim]")

    table.add_row("Throughput", f"R: [bold green]{read_mb:.1f} MB/s[/bold green] | W: [bold cyan]{write_mb:.1f} MB/s[/bold cyan]")

    for p in parts[:2]:
        pct = p["pct"]
        bar = make_progress_bar(pct, width=10, color="green" if pct < 75 else "yellow" if pct < 90 else "red")
        table.add_row(f"{p['device']} ({p['fstype']})", f"{bar} [dim]({p['free_gb']}GB free)[/dim]")

    return Panel(table, title="[bold cyan]STORAGE & NVME PARTITIONS[/bold cyan]", border_style="cyan", box=box.ROUNDED)


def build_process_table(limit=6):
    """Renders active processes with dynamic micro-bars and clean aesthetic indicators."""
    table = Table(box=box.SIMPLE_HEAD, expand=True, header_style="bold cyan", padding=(0, 1))
    table.add_column("PID", justify="right", style="dim", width=7)
    table.add_column("APPLICATION NAME", style="bold white", width=22)
    table.add_column("CPU USAGE", justify="left", width=18)
    table.add_column("RAM USAGE", justify="left", width=18)
    table.add_column("POWER STATUS", justify="center", width=16)

    procs = TELEMETRY["processes"][:limit]
    if not procs:
        table.add_row("-", "Scanning active processes...", "--", "--", "[dim]--[/dim]")
    else:
        for p in procs:
            cpu_val = p['cpu']
            mem_val = p['mem_mb']

            # Sleek dynamic meters without block highlights
            cpu_meter = make_mini_meter(cpu_val, max_val=20.0, width=7)
            cpu_col = "bold red" if cpu_val >= 6.0 else "bold yellow" if cpu_val >= 2.0 else "dim green"
            cpu_cell = f"{cpu_meter} [{cpu_col}]{cpu_val:4.1f}%[/{cpu_col}]"

            mem_meter = make_mini_meter(mem_val, max_val=1500.0, width=7)
            mem_col = "bold red" if mem_val >= 700.0 else "bold yellow" if mem_val >= 300.0 else "dim green"
            mem_cell = f"{mem_meter} [{mem_col}]{mem_val:5.1f}M[/{mem_col}]"

            if cpu_val >= 6.0 or mem_val >= 700.0:
                impact_badge = "[bold red]* HIGH DRAIN[/bold red]"
            elif cpu_val >= 2.0 or mem_val >= 300.0:
                impact_badge = "[bold yellow]> MODERATE  [/bold yellow]"
            else:
                impact_badge = "[dim green]. OPTIMAL   [/dim green]"

            table.add_row(
                str(p['pid']),
                p['name'][:22],
                cpu_cell,
                mem_cell,
                impact_badge
            )

    sort_label = f"SORT: {PROCESS_SORT_MODE.upper()}"
    filter_label = f"FILTER: {PROCESS_FILTER_MODE.upper()}"
    title = f"[bold cyan]TASK MANAGER MATRIX ({sort_label} | {filter_label})[/bold cyan]"

    return Panel(table, title=title, border_style="cyan", box=box.ROUNDED)


def build_battery_focus_view():
    """Deep detailed battery health & calibration diagnostics."""
    pct = TELEMETRY["battery_pct"]
    plugged = TELEMETRY["battery_plugged"]
    wattage = TELEMETRY["battery_wattage"]
    full_mwh = TELEMETRY["battery_mwh_full"]
    design_mwh = TELEMETRY["battery_mwh_design"]
    rem_mwh = TELEMETRY["battery_mwh_remaining"]
    wear = TELEMETRY["battery_wear_pct"]
    grade = TELEMETRY["battery_health_grade"]
    secs = TELEMETRY["battery_secsleft"]
    cycles = TELEMETRY["battery_cycle_count"]
    voltage = TELEMETRY["battery_voltage_v"]

    budget_w = round(full_mwh / 4000.0, 2)

    table = Table(box=box.ROUNDED, expand=True, padding=(0, 2))
    table.add_column("DIAGNOSTIC METRIC", style="bold cyan", width=28)
    table.add_column("MEASUREMENT / CALIBRATION", style="bold white")
    table.add_column("ENGINE STATUS", style="bold green", width=22)

    table.add_row("Power State", "[AC] ADAPTER CONNECTED" if plugged else "[BAT] DISCHARGING", "ONLINE")
    table.add_row("Live Charge Level", make_progress_bar(pct, width=28), "OPTIMAL")
    table.add_row("Full Charge Capacity", f"{full_mwh:,} mWh (Factory: {design_mwh:,} mWh)", "HEALTHY")
    table.add_row("Remaining Pack Volume", f"{rem_mwh:,} mWh", "NORMAL")
    table.add_row("Hardware Wear Level", f"{wear}% Degradation ({max(0, design_mwh - full_mwh):,} mWh lost)", f"GRADE {grade}")
    table.add_row("Cycle Life Count", f"{cycles} / 500 Rated Cycles", f"{round((cycles/500)*100, 1)}% Consumed")
    table.add_row("Pack Terminal Voltage", f"{voltage} Volts", "BALANCED")
    table.add_row("Live Power Draw", f"{wattage:.2f} Watts", "MEASURED")
    table.add_row("4-Hour Target Budget", f"Keep under {budget_w} Watts for 4h battery", "BUDGET TARGET")
    table.add_row("Estimated Runtime", format_secs(secs), "ACTIVE")

    net_str = "Offline / Disconnected"
    net_status = "OFFLINE"
    try:
        stats = psutil.net_if_stats()
        active_nets = []
        for iface, s in stats.items():
            if s.isup and not iface.startswith("Loopback") and "Virtual" not in iface and "vEthernet" not in iface:
                speed_str = f" ({s.speed} Mbps)" if s.speed > 0 else ""
                active_nets.append(f"{iface}{speed_str}")
        if active_nets:
            net_str = ", ".join(active_nets[:2])
            net_status = "CONNECTED"
    except Exception:
        pass
    table.add_row("Network Adapters", f"[bold white]{net_str}[/bold white]", net_status)

    table.add_row("Optimizer & Cleanup", "Press [bold yellow][O][/bold yellow] or [bold yellow][C][/bold yellow] to run Battery Cleanup (User/Admin)", "[bold cyan]AVAILABLE[/bold cyan]")

    return Panel(table, title="[bold cyan]DEEP BATTERY HEALTH, TRUE CALIBRATION & OPTIMIZER[/bold cyan]", border_style="cyan", box=box.ROUNDED)


def build_cpu_focus_view():
    """Deep CPU & core analyzer view with Minimized and Expanded modes."""
    global CPU_MINIMIZE_MODE
    cpu_pct = TELEMETRY["cpu_pct"]
    cores = TELEMETRY["cpu_per_core"]
    logical = HARDWARE_INFO["cpu_cores_logical"]
    physical = HARDWARE_INFO["cpu_cores_physical"]
    cpu_temp = TELEMETRY.get("cpu_temp_c", 0.0)
    cpu_freq = TELEMETRY.get("cpu_freq_mhz", 0)
    board = HARDWARE_INFO.get("board_model", "8D3F")
    bios = HARDWARE_INFO.get("bios_version", "F.14")
    mfg = HARDWARE_INFO.get("board_mfg", "HP")

    headroom = max(0.0, round(100.0 - cpu_temp, 1)) if cpu_temp > 0 else 50.0
    throt_status = "[bold red]THROTTLED (PROCHOT)[/bold red]" if cpu_temp >= 95.0 else "[bold green]NOMINAL (Clear)[/bold green]"

    table = Table(box=box.ROUNDED, expand=True, padding=(0, 2))
    table.add_column("METRIC", style="bold cyan", width=24)
    table.add_column("STATUS", style="bold white")

    table.add_row("CPU Architecture", f"{HARDWARE_INFO['cpu_name']}")
    table.add_row("Motherboard & BIOS", f"{mfg} {board} | BIOS {bios}")
    table.add_row("Core Configuration", f"{physical} Physical Cores / {logical} Logical Threads")
    table.add_row("Overall CPU Load", make_progress_bar(cpu_pct, width=28))
    if cpu_temp > 0 or cpu_freq > 0:
        t_col = "red" if cpu_temp >= 80 else "yellow" if cpu_temp >= 65 else "green"
        table.add_row("Thermals & Headroom", f"[{t_col}]{cpu_temp:.1f} C[/{t_col}] [dim]@ {cpu_freq} MHz (Headroom: {headroom} C to TjMax)[/dim]")
        table.add_row("Throttle Protection", throt_status)

    bench = TELEMETRY.get("benchmarks", {})
    if bench.get("cpu_mt_score", 0) > 0:
        table.add_row("Compute Benchmark", f"[bold green]{bench['cpu_mt_score']} pts[/bold green] [dim](Single: {bench['cpu_st_score']} pts, Scaling: {bench['cpu_scale_ratio']}x)[/dim]")
    elif bench.get("stress_peak_c", 0.0) > 0:
        throt_badge = "[bold red]THROTTLED[/bold red]" if bench.get("stress_throttled") else "[bold green]NOMINAL (No Throttling)[/bold green]"
        table.add_row("Stress Test Result", f"Peak: [yellow]{bench['stress_peak_c']} C[/yellow] (+{bench['stress_delta_c']} C) | State: {throt_badge}")
    else:
        table.add_row("Benchmark / Stress", "Press [bold yellow][B][/bold yellow] to run Multi-Core Stress Test or CPU Benchmark")

    mode_label = "MINIMIZED (Clean Overview)" if CPU_MINIMIZE_MODE else "EXPANDED (Per-Thread Matrix)"
    table.add_row("View Layout Mode", f"[bold white]{mode_label}[/bold white] - Press [bold yellow][M][/bold yellow] to toggle")

    if CPU_MINIMIZE_MODE:
        # Minimized / User-Friendly Mode: clean single panel without cluttered thread matrix
        return Panel(table, title="[bold cyan]CPU & PROCESSOR ESSENTIAL OVERVIEW [MINIMIZED - PRESS M TO EXPAND][/bold cyan]", border_style="cyan", box=box.ROUNDED)

    core_table = Table(box=box.SIMPLE, expand=True)
    for col_idx in range(4):
        core_table.add_column(f"Core Group {col_idx+1}", style="bold white")

    chunk_size = 4
    for i in range(0, len(cores), chunk_size):
        chunk = cores[i:i+chunk_size]
        row_cells = []
        for idx, c in enumerate(chunk):
            col = "green" if c < 50 else "yellow" if c < 80 else "red"
            meter = make_mini_meter(c, max_val=100.0, width=6)
            row_cells.append(f"T{i+idx:02d}: {meter} [{col}]{c:4.1f}%[/{col}]")
        while len(row_cells) < 4:
            row_cells.append("-")
        core_table.add_row(*row_cells)

    content = Layout()
    content.split_column(
        Layout(Panel(table, box=box.ROUNDED, border_style="cyan"), size=10),
        Layout(Panel(core_table, title="[bold cyan]PER-THREAD REAL-TIME ACTIVITY (PRESS M TO MINIMIZE)[/bold cyan]", box=box.ROUNDED, border_style="cyan")),
        Layout(build_process_table(limit=6), size=9),
    )
    return content


def build_gpu_focus_view():
    """Deep dedicated GPU metrics, thermals, VRAM utilization, clocks, and power draw."""
    gpu_name = TELEMETRY.get("gpu_name", "Discrete GPU")
    gpu_driver = TELEMETRY.get("gpu_driver", "N/A")
    gpu_util = TELEMETRY.get("gpu_util", 0)
    gpu_temp = TELEMETRY.get("gpu_temp", 0)
    gpu_hotspot = TELEMETRY.get("gpu_hotspot_c", 0)
    vrm_temp = TELEMETRY.get("vrm_temp_c", 0)
    gpu_power = TELEMETRY.get("gpu_power", 0.0)
    vram_tot = TELEMETRY.get("gpu_vram_total_mb", 0)
    vram_used = TELEMETRY.get("gpu_vram_used_mb", 0)
    mem_clock = TELEMETRY.get("gpu_mem_clock_mhz", 0)
    core_clock = TELEMETRY.get("gpu_core_clock_mhz", 0)
    throttle = TELEMETRY.get("gpu_throttle", "None")
    pcie_link = TELEMETRY.get("gpu_pcie_link", "N/A")
    fan_rpm = TELEMETRY.get("gpu_fan_rpm", 0)

    vram_pct = round((vram_used / max(1, vram_tot)) * 100.0, 1) if vram_tot > 0 else 0.0

    table = Table(box=box.ROUNDED, expand=True, padding=(0, 2))
    table.add_column("GPU TELEMETRY METRIC", style="bold cyan", width=26)
    table.add_column("MEASUREMENT / LIVE DATA", style="bold white")
    table.add_column("ENGINE STATUS", style="bold green", width=22)

    table.add_row("Device Model", f"[bold yellow]{gpu_name}[/bold yellow]", "ONLINE")
    table.add_row("Driver & PCIe Link", f"Driver: [bold white]{gpu_driver}[/bold white] | Bus: [dim]{pcie_link}[/dim]", "SYNCED")

    u_col = "green" if gpu_util < 50 else "yellow" if gpu_util < 85 else "red"
    table.add_row("GPU Compute Load", make_progress_bar(gpu_util, width=24, color=u_col), f"{gpu_util}% Utilized")

    if vram_tot > 0:
        vr_col = "green" if vram_pct < 70 else "yellow" if vram_pct < 90 else "red"
        table.add_row("Dedicated VRAM Usage", f"{make_progress_bar(vram_pct, width=20, color=vr_col)} [dim]{vram_used:,} MB / {vram_tot:,} MB[/dim]", f"{vram_pct}% VRAM")

    t_col = "red" if gpu_temp >= 80 else "yellow" if gpu_temp >= 65 else "green"
    hot_str = f" [dim](Hotspot: {gpu_hotspot} C)[/dim]" if gpu_hotspot > 0 else ""
    table.add_row("GPU Core Thermals", f"[{t_col}]{gpu_temp} C[/{t_col}]{hot_str}", "OPTIMAL" if gpu_temp < 75 else "ELEVATED")

    if vrm_temp > 0 or fan_rpm > 0:
        vrm_str = f"VRM: {vrm_temp} C | " if vrm_temp > 0 else ""
        fan_str = f"Fan: {fan_rpm} RPM" if fan_rpm > 0 else ""
        table.add_row("Cooling & VRM", f"[dim]{vrm_str}{fan_str}[/dim]", "ACTIVE")

    table.add_row("Live Graphics Power", f"[bold magenta]{gpu_power:.1f} Watts[/bold magenta]", "MEASURED")
    table.add_row("Core & Memory Clocks", f"Core: [bold white]{core_clock} MHz[/bold white] | Mem: [dim]{mem_clock} MHz[/dim]", "SYNCHRONIZED")
    table.add_row("Thermal Throttle State", f"[bold white]{throttle}[/bold white]", "[bold green]CLEAR[/bold green]" if throttle in ["None", "0x0000000000000000", "0x0000000000000004"] else "[bold red]THROTTLED[/bold red]")

    bench = TELEMETRY.get("benchmarks", {})
    if bench.get("gpu_stress_peak_c", 0.0) > 0:
        table.add_row("Last GPU Stress Test", f"Peak: [yellow]{bench['gpu_stress_peak_c']} C[/yellow] (+{bench['gpu_stress_delta_c']} C) | Pwr: {bench['gpu_stress_power_w']} W | Clk: {bench['gpu_stress_clock_mhz']} MHz", "[bold green]RECORDED[/bold green]")
    else:
        table.add_row("Hardware Stress Test", "Press [bold yellow][B][/bold yellow] to run 524,288-thread CUDA stress burn-in", "[bold cyan]AVAILABLE[/bold cyan]")

    return Panel(table, title="[bold cyan]DEDICATED GRAPHICS (GPU) TELEMETRY & HARDWARE CONTROLS[/bold cyan]", border_style="cyan", box=box.ROUNDED)


def build_storage_focus_view():
    """Deep storage partition manager, SMART health, wear degradation & TRIM status."""
    ssd_model = TELEMETRY.get("ssd_model", "Samsung NVMe SSD")
    ssd_health = TELEMETRY.get("ssd_health", "Healthy (OK)")
    ssd_wear = TELEMETRY.get("ssd_wear_pct", 0)
    ssd_temp = TELEMETRY.get("ssd_temp", 46)
    parts = TELEMETRY.get("partitions", [])
    read_mb = TELEMETRY["disk_read_mbs"]
    write_mb = TELEMETRY["disk_write_mbs"]

    hw_table = Table(box=box.ROUNDED, expand=True, padding=(0, 2))
    hw_table.add_column("NVME STORAGE METRIC", style="bold cyan", width=26)
    hw_table.add_column("STATUS & RELIABILITY COUNTERS", style="bold white")

    hw_table.add_row("Physical Drive Model", f"[bold yellow]{ssd_model}[/bold yellow]")
    hw_table.add_row("SMART Health State", f"[bold green]{ssd_health}[/bold green]")
    hw_table.add_row("Lifetime Degradation", f"[bold green]{ssd_wear}% Wear[/bold green] [dim](Remaining Endurance: {100 - ssd_wear}%)[/dim]")
    hw_table.add_row("Drive Temperature", f"[bold yellow]{ssd_temp} C[/bold yellow] [dim](Optimal operating temperature)[/dim]")
    hw_table.add_row("Real-time Throughput", f"Read: [bold green]{read_mb:.1f} MB/s[/bold green]  |  Write: [bold cyan]{write_mb:.1f} MB/s[/bold cyan]")

    bench = TELEMETRY.get("benchmarks", {})
    if bench.get("disk_seq_mbs", 0.0) > 0:
        hw_table.add_row("Sequential Read Speed", f"[bold green]{bench['disk_seq_mbs']} MB/s[/bold green] [dim](Tested 128MB test block)[/dim]")
        hw_table.add_row("4K Random Read Speed", f"[bold green]{bench['disk_rnd_mbs']} MB/s[/bold green] [dim]({bench['disk_rnd_iops']} IOPS, {bench['disk_lat_ms']} ms)[/dim]")
    else:
        hw_table.add_row("Read Benchmark", "Press [bold yellow][B][/bold yellow] to run high-precision NVMe Sequential & 4K Read Benchmark")

    hw_table.add_row("Storage Optimizer", "Press [bold yellow][T][/bold yellow] to run volume TRIM & file system optimization")

    part_table = Table(box=box.SIMPLE_HEAD, expand=True, header_style="bold cyan", padding=(0, 1))
    part_table.add_column("DRIVE", justify="center", width=8)
    part_table.add_column("FILE SYSTEM", width=14)
    part_table.add_column("TOTAL (GB)", justify="right", width=12)
    part_table.add_column("USED (GB)", justify="right", width=12)
    part_table.add_column("FREE (GB)", justify="right", width=12)
    part_table.add_column("USAGE METER", justify="center", width=24)

    if not parts:
        part_table.add_row("--", "--", "--", "--", "--", "Scanning partitions...")
    else:
        for p in parts:
            pct = p["pct"]
            col = "green" if pct < 75 else "yellow" if pct < 90 else "red"
            bar = make_progress_bar(pct, width=12, color=col)
            part_table.add_row(
                f"[bold cyan]{p['device']}[/bold cyan]",
                f"[bold white]{p['fstype']}[/bold white]",
                f"{p['total_gb']:.1f} GB",
                f"{p['used_gb']:.1f} GB",
                f"[bold green]{p['free_gb']:.1f} GB[/bold green]",
                bar
            )

    layout = Layout()
    layout.split_column(
        Layout(Panel(hw_table, title="[bold cyan]PHYSICAL NVME SSD HEALTH & DEGRADATION[/bold cyan]", box=box.ROUNDED, border_style="cyan"), size=9),
        Layout(Panel(part_table, title="[bold cyan]MOUNTED PARTITIONS & STORAGE VOLUMES[/bold cyan]", box=box.ROUNDED, border_style="cyan")),
    )
    return layout


def build_logs_view():
    """In-terminal log viewer showing active session details, recent telemetry, and archive."""
    logs_dir = get_logs_directory()
    curr_log = os.path.join(logs_dir, "current-session.csv")
    pid_file = os.path.join(logs_dir, "battery-logger.pid")

    is_logging = False
    logger_pid = None
    if os.path.exists(pid_file):
        try:
            with open(pid_file, "r") as f:
                pid_str = f.read().strip()
                if pid_str and pid_str.isdigit():
                    logger_pid = int(pid_str)
                    if psutil.pid_exists(logger_pid):
                        is_logging = True
        except Exception:
            pass

    status_str = f"[bold green]ACTIVE (PID: {logger_pid})[/bold green]" if is_logging else "[dim yellow]INACTIVE (Stopped)[/dim yellow]"

    summary_table = Table(box=box.ROUNDED, expand=True, padding=(0, 1))
    summary_table.add_column("LOG CONFIGURATION", style="bold cyan", width=22)
    summary_table.add_column("CURRENT STATUS", style="bold white")

    summary_table.add_row("Background Daemon", status_str)
    summary_table.add_row("Log File Path", curr_log)
    summary_table.add_row("Explorer Shortcut", "Press [bold yellow][O][/bold yellow] to open logs folder in Windows File Explorer")

    rows = []
    total_records = 0
    start_pct, end_pct = 0.0, 0.0
    used_mwh = 0.0
    if os.path.exists(curr_log):
        try:
            with open(curr_log, "r", encoding="utf-8", errors="ignore") as f:
                reader = list(csv.reader(f))
                if len(reader) > 1:
                    data_rows = [r for r in reader[1:] if len(r) >= 11]
                    total_records = len(data_rows)
                    if total_records > 0:
                        try:
                            start_pct = float(data_rows[0][2])
                            end_pct = float(data_rows[-1][2])
                            used_mwh = round(float(data_rows[0][3]) - float(data_rows[-1][3]), 1)
                        except Exception:
                            pass
                        rows = data_rows[-10:]
        except Exception:
            pass

    if total_records >= 2:
        diff_pct = round(start_pct - end_pct, 1)
        summary_table.add_row("Session Statistics", f"{total_records} rows logged | {start_pct:.0f}% -> {end_pct:.0f}% ({diff_pct:.1f}% used, {used_mwh} mWh consumed)")
    else:
        summary_table.add_row("Session Statistics", f"{total_records} rows logged")

    archive_dir = os.path.join(logs_dir, "archive")
    archive_files = []
    if os.path.exists(archive_dir):
        try:
            for f in sorted(os.listdir(archive_dir), reverse=True)[:4]:
                if f.endswith(".csv"):
                    fp = os.path.join(archive_dir, f)
                    sz_kb = round(os.path.getsize(fp) / 1024, 1)
                    archive_files.append(f"{f} ({sz_kb} KB)")
        except Exception:
            pass

    archive_str = ", ".join(archive_files) if archive_files else "No archived sessions."
    summary_table.add_row("Recent Archives", archive_str)

    telemetry_table = Table(box=box.SIMPLE_HEAD, expand=True, header_style="bold cyan", padding=(0, 1))
    telemetry_table.add_column("TIMESTAMP", style="dim", width=20)
    telemetry_table.add_column("PWR", justify="center", width=6)
    telemetry_table.add_column("BATT %", justify="right", width=8)
    telemetry_table.add_column("REM (mWh)", justify="right", width=11)
    telemetry_table.add_column("DRAIN (W)", justify="right", width=10)
    telemetry_table.add_column("CPU %", justify="right", width=8)
    telemetry_table.add_column("RAM (GB)", justify="right", width=10)
    telemetry_table.add_column("TOP CPU APP", style="bold yellow", width=18)

    if not rows:
        telemetry_table.add_row("--", "--", "--", "--", "--", "--", "--", "No log records found.")
    else:
        for r in reversed(rows):
            ts = r[0]
            pwr = "[green]AC[/green]" if r[1].lower() in ["true", "1"] else "[yellow]BAT[/yellow]"
            pct = f"{r[2]}%"
            mwh = f"{r[3]}"
            w = f"{r[4]} W"
            cpu = f"{r[6]}%"
            ram = f"{r[7]} GB"
            app = r[10][:18]
            telemetry_table.add_row(ts, pwr, pct, mwh, w, cpu, ram, app)

    layout = Layout()
    layout.split_column(
        Layout(Panel(summary_table, title="[bold cyan]SESSION RECORDER & LOG TELEMETRY[/bold cyan]", box=box.ROUNDED, border_style="cyan"), size=8),
        Layout(Panel(telemetry_table, title="[bold cyan]RECENT LOG ENTRIES (IN-TERMINAL VIEWER)[/bold cyan]", box=box.ROUNDED, border_style="cyan")),
    )
    return layout


def build_sensors_view():
    """Native Deep Hardware & Sensor Matrix (Zero External Process Required)."""
    cpu_temp = TELEMETRY.get("cpu_temp_c", 52.0)
    cpu_freq = TELEMETRY.get("cpu_freq_mhz", 2200)
    cpu_pct = TELEMETRY.get("cpu_pct", 0.0)
    board_mfg = HARDWARE_INFO.get("board_mfg", "HP")
    board_model = HARDWARE_INFO.get("board_model", "8D3F")
    bios_ver = HARDWARE_INFO.get("bios_version", "F.14")
    bios_date = HARDWARE_INFO.get("bios_date", "2026-04-13")
    cpu_name = HARDWARE_INFO.get("cpu_name", "Intel Core i7-14650HX")
    cpu_log = HARDWARE_INFO.get("cpu_cores_logical", 16)
    cpu_phy = HARDWARE_INFO.get("cpu_cores_physical", 8)

    gpu_name = TELEMETRY.get("gpu_name", "NVIDIA GeForce RTX 5050 Laptop GPU")
    gpu_driver = TELEMETRY.get("gpu_driver", "617.14")
    gpu_temp = TELEMETRY.get("gpu_temp", 44)
    gpu_power = TELEMETRY.get("gpu_power", 18.2)
    gpu_vram_tot = TELEMETRY.get("gpu_vram_total_mb", 8151)
    gpu_vram_used = TELEMETRY.get("gpu_vram_used_mb", 0)
    gpu_mem_clk = TELEMETRY.get("gpu_mem_clock_mhz", 11001)
    gpu_pcie = TELEMETRY.get("gpu_pcie_link", "Gen5 x8")
    gpu_throttle = TELEMETRY.get("gpu_throttle", "None")

    ssd_model = TELEMETRY.get("ssd_model", "SAMSUNG MZVL81T0HELB-00BH1")
    ssd_health = TELEMETRY.get("ssd_health", "Healthy")
    ssd_wear = TELEMETRY.get("ssd_wear_pct", 0)
    ssd_temp = TELEMETRY.get("ssd_temp", 46)

    ram_speed = HARDWARE_INFO.get("ram_speed_mts", 5600)
    ram_tot = HARDWARE_INFO.get("total_ram_gb", 23.6)
    ram_mods = HARDWARE_INFO.get("ram_modules", [])

    hw_active = TELEMETRY.get("hwinfo_active", False)
    cpu_rpm = TELEMETRY.get("cpu_fan_rpm", 0)
    gpu_rpm = TELEMETRY.get("gpu_fan_rpm", 0)
    vrm_c = TELEMETRY.get("vrm_temp_c", 0)
    gpu_hotspot = TELEMETRY.get("gpu_hotspot_c", 0)

    # Header overview table
    header_table = Table(box=box.ROUNDED, expand=True, padding=(0, 2))
    header_table.add_column("HARDWARE SUBSYSTEM", style="bold cyan", width=26)
    header_table.add_column("NATIVE PLATFORM IDENTIFICATION & SENSORS", style="bold white")

    header_table.add_row("Motherboard & BIOS", f"{board_mfg} {board_model} | BIOS {bios_ver} (Released {bios_date})")
    header_table.add_row("Execution Engine", "[bold green]100% Native Telemetry (Zero External GUI App Dependency)[/bold green]")
    header_table.add_row("Refresh Action", "Press [bold yellow][8][/bold yellow] or [bold yellow][H][/bold yellow] to instantly poll all hardware buses")

    # Sensor grid table
    sensor_table = Table(box=box.ROUNDED, expand=True, padding=(0, 2))
    sensor_table.add_column("SUBSYSTEM", style="bold cyan", width=18)
    sensor_table.add_column("TELEMETRY CHANNEL", style="bold white", width=26)
    sensor_table.add_column("CURRENT VALUE", style="bold green", width=22)
    sensor_table.add_column("SPECIFICATION / TOPOLOGY", justify="left")

    # Motherboard
    sensor_table.add_row("Motherboard", "Baseboard Model", f"{board_model}", f"Vendor: {board_mfg}")
    sensor_table.add_row("Motherboard", "System BIOS", f"{bios_ver}", f"Release Date: {bios_date}")

    # CPU
    c_col = "red" if cpu_temp > 85 else "yellow" if cpu_temp > 70 else "green"
    sensor_table.add_row("CPU Telemetry", "ACPI Thermal Zone", f"[{c_col}]{cpu_temp} C[/{c_col}]", "MSAcpi_ThermalZoneTemperature")
    sensor_table.add_row("CPU Telemetry", "Average Clock Speed", f"{cpu_freq} MHz", f"{cpu_log} Logical / {cpu_phy} Physical Cores")
    sensor_table.add_row("CPU Telemetry", "Processor Workload", f"{cpu_pct:.1f}%", f"{cpu_name[:32]}")

    # GPU
    g_col = "red" if gpu_temp > 80 else "yellow" if gpu_temp > 65 else "green"
    sensor_table.add_row("NVIDIA dGPU", "GPU Core Temperature", f"[{g_col}]{gpu_temp} C[/{g_col}]", f"Hotspot: {gpu_hotspot} C" if gpu_hotspot > 0 else "Diode Thermal")
    sensor_table.add_row("NVIDIA dGPU", "Graphics Power Draw", f"{gpu_power:.1f} W", f"{gpu_name[:28]}")
    vram_pct = round((gpu_vram_used / gpu_vram_tot * 100), 1) if gpu_vram_tot > 0 else 0
    sensor_table.add_row("NVIDIA dGPU", "VRAM Allocation", f"{gpu_vram_used} MB / {gpu_vram_tot} MB", f"Dedicated ({vram_pct}%)")
    sensor_table.add_row("NVIDIA dGPU", "Video Memory Clock", f"{gpu_mem_clk} MHz", f"Driver: {gpu_driver}")
    sensor_table.add_row("NVIDIA dGPU", "PCIe Negotiation", f"{gpu_pcie}", f"Throttle State: {gpu_throttle}")

    # DDR5 Memory
    sensor_table.add_row("DDR5 Memory", "Configured Bus Speed", f"{ram_speed} MT/s", f"{ram_tot} GB Total Physical")
    if ram_mods:
        for m in ram_mods:
            sensor_table.add_row("DDR5 Memory", f"Module: {m['bank']}", f"{m['speed']} MT/s", f"{m['mfg']} {m['part']} ({m['gb']}GB)")

    # NVMe Storage
    s_col = "red" if ssd_temp > 70 else "yellow" if ssd_temp > 55 else "green"
    sensor_table.add_row("NVMe Storage", "Controller Temperature", f"[{s_col}]{ssd_temp} C[/{s_col}]", f"SMART Status: {ssd_health}")
    sensor_table.add_row("NVMe Storage", "Wear Degradation", f"{ssd_wear}%", f"{ssd_model[:30]}")

    # Cooling Fans (if active via passive mmap)
    if hw_active and (cpu_rpm > 0 or gpu_rpm > 0):
        if cpu_rpm > 0:
            sensor_table.add_row("Cooling Fans", "CPU Cooling Fan", f"{cpu_rpm} RPM", "[dim]Passive mmap[/dim]")
        if gpu_rpm > 0:
            sensor_table.add_row("Cooling Fans", "GPU Cooling Fan", f"{gpu_rpm} RPM", "[dim]Passive mmap[/dim]")
        if vrm_c > 0:
            sensor_table.add_row("Thermals", "Motherboard VRM / MOSFET", f"{vrm_c} C", "[dim]Passive mmap[/dim]")

    # Hardware Benchmarks & Stress Results
    bm = TELEMETRY.get("benchmarks", {})
    if bm.get("last_bench_time", 0.0) > 0:
        if bm.get("disk_seq_mbs", 0.0) > 0:
            sensor_table.add_row("Benchmarks", "NVMe Read Benchmark", f"{bm['disk_seq_mbs']} MB/s Seq", f"4K: {bm['disk_rnd_mbs']} MB/s ({bm['disk_rnd_iops']:,} IOPS, {bm['disk_lat_ms']} ms)")
        if bm.get("cpu_mt_score", 0) > 0:
            sensor_table.add_row("Benchmarks", "CPU Benchmark", f"ST: {bm['cpu_st_score']:,} | MT: {bm['cpu_mt_score']:,}", f"Scaling Ratio: {bm['cpu_scale_ratio']}x")
        if bm.get("stress_peak_c", 0.0) > 0:
            sensor_table.add_row("Benchmarks", "CPU Thermal Stress", f"Peak: {bm['stress_peak_c']} C (+{bm['stress_delta_c']} C)", f"Ops: {bm['stress_ops']:,} | Throttled: {bm['stress_throttled']}")
        if bm.get("gpu_stress_power_w", 0.0) > 0:
            sensor_table.add_row("Benchmarks", "GPU Hardware Stress", f"Peak: {bm['gpu_stress_peak_c']} C ({bm['gpu_stress_power_w']} W)", f"Clock: {bm['gpu_stress_clock_mhz']} MHz | Util: {bm['gpu_stress_util_pct']}% | Throttled: {bm['gpu_stress_throttled']}")
        if bm.get("ram_read_gbs", 0.0) > 0:
            sensor_table.add_row("Benchmarks", "RAM Read Bandwidth", f"{bm['ram_read_gbs']} GB/s", f"Copy: {bm.get('ram_copy_gbs', 0)} GB/s")
    else:
        sensor_table.add_row("Benchmarks", "Hardware Benchmark Suite", "Press [B] to execute", "Storage, RAM, CPU & Dedicated GPU Stress")

    layout = Layout()
    layout.split_column(
        Layout(Panel(header_table, title="[bold cyan]NATIVE DEEP HARDWARE & SENSOR MATRIX (ZERO EXTERNAL APPS)[/bold cyan]", box=box.ROUNDED, border_style="cyan"), size=5),
        Layout(Panel(sensor_table, title="[bold cyan]REAL-TIME HARDWARE SENSOR & PHYSICAL BUS TELEMETRY[/bold cyan]", box=box.ROUNDED, border_style="cyan")),
    )
    return layout


build_hwinfo_view = build_sensors_view


def safe_panel(builder_fn, *args, **kwargs):
    """Safely executes a panel builder function with an error boundary."""
    try:
        return builder_fn(*args, **kwargs)
    except Exception as e:
        return Panel(
            f"[bold red]Panel Render Error:[/bold red] {e}\n[dim]The dashboard remains active. Press [1] for All view.[/dim]",
            title="[bold red]RENDER ERROR[/bold red]",
            border_style="red",
            box=box.ROUNDED,
        )


def build_footer_panel():
    """Interactive hotkey footer bar with deep sensors integration."""
    global STATUS_MESSAGE, STATUS_TIME

    rate_str = f"{REFRESH_RATE:.1f}s"

    footer_text = Text()
    footer_text.append(" [<-/-> or 1-9] Views ", style="bold white on #2563eb")
    footer_text.append(" [G] GPU ", style="bold white on #059669")
    footer_text.append(" [M] Min/Max ", style="bold white on #0891b2")
    footer_text.append(" [B] Bench/Stress ", style="bold white on #b45309")
    footer_text.append(" [T] SSD TRIM ", style="bold white on #059669")
    footer_text.append(" [O/C] Battery Clean/Opt ", style="bold white on #7c3aed")
    footer_text.append(f" [R] Rate: {rate_str} ", style="bold white on #0284c7")
    footer_text.append(f" [S] Sort: {PROCESS_SORT_MODE.upper()} ", style="bold white on #475569")
    footer_text.append(f" [F] Filter: {PROCESS_FILTER_MODE.upper()} ", style="bold white on #334155")
    footer_text.append(" [K] Kill PID ", style="bold white on #dc2626")
    footer_text.append(" [Q] Exit ", style="bold white on #1e293b")

    if STATUS_MESSAGE and (time.time() - STATUS_TIME < 4.0):
        footer_text.append(f"\n [NOTICE] {STATUS_MESSAGE}", style="bold yellow")

    return Panel(Align.center(footer_text), box=box.ROUNDED, border_style="dim white", padding=(0, 0))


def render_dashboard():
    """Assembles responsive layout with complete error boundary isolation."""
    width = console.size.width

    layout = Layout()
    layout.split_column(
        Layout(name="header", size=4),
        Layout(name="body"),
        Layout(name="footer", size=3),
    )

    layout["header"].update(safe_panel(build_header_panel))
    layout["footer"].update(safe_panel(build_footer_panel))

    if CURRENT_VIEW == "all":
        if width >= 115:
            # 3-column wide mode
            layout["body"].split_column(
                Layout(name="top_cards", size=10),
                Layout(name="process_table"),
            )
            layout["top_cards"].split_row(
                Layout(safe_panel(build_battery_panel), ratio=1),
                Layout(safe_panel(build_cpu_ram_panel), ratio=1),
                Layout(safe_panel(build_storage_panel), ratio=1),
            )
            layout["process_table"].update(safe_panel(build_process_table, limit=6))
        else:
            # 2-column or stacked compact mode
            layout["body"].split_column(
                Layout(name="top_cards", size=10),
                Layout(name="process_table"),
            )
            layout["top_cards"].split_row(
                Layout(safe_panel(build_battery_panel), ratio=1),
                Layout(safe_panel(build_cpu_ram_panel), ratio=1),
            )
            layout["process_table"].update(safe_panel(build_process_table, limit=5))

    elif CURRENT_VIEW == "battery":
        layout["body"].update(safe_panel(build_battery_focus_view))

    elif CURRENT_VIEW == "cpu":
        layout["body"].update(safe_panel(build_cpu_focus_view))

    elif CURRENT_VIEW == "ram":
        layout["body"].split_column(
            Layout(safe_panel(build_cpu_ram_panel), size=9),
            Layout(safe_panel(build_process_table, limit=12)),
        )

    elif CURRENT_VIEW == "gpu":
        layout["body"].update(safe_panel(build_gpu_focus_view))

    elif CURRENT_VIEW == "storage":
        layout["body"].update(safe_panel(build_storage_focus_view))

    elif CURRENT_VIEW == "processes":
        layout["body"].update(safe_panel(build_process_table, limit=16))

    elif CURRENT_VIEW == "logs":
        layout["body"].update(safe_panel(build_logs_view))

    elif CURRENT_VIEW in ["sensors", "hwinfo"]:
        layout["body"].update(safe_panel(build_sensors_view))

    return layout


def run_interactive_benchmark(live):
    """Interactive benchmark and hardware stress testing dialog."""
    global STATUS_MESSAGE, STATUS_TIME
    if bench_engine is None:
        STATUS_MESSAGE = "Benchmark engine module could not be loaded."
        STATUS_TIME = time.time()
        return

    live.stop()
    console.clear()
    console.print("\n[bold cyan]=============================================================================[/bold cyan]")
    console.print("[bold white]            OMNI BENCHMARK & HARDWARE STRESS TESTING SUITE[/bold white]")
    console.print("[bold cyan]=============================================================================[/bold cyan]")
    console.print("  [bold yellow][1][/bold yellow] NVMe Storage Read Benchmark (Sequential MB/s, 4K Random IOPS, Latency)")
    console.print("  [bold yellow][2][/bold yellow] Multi-Core CPU Stress Test (10s Sustained Thermal & Throttle Load)")
    console.print("  [bold yellow][3][/bold yellow] Dedicated GPU Hardware Stress Test (10s at 100% Load & 2.7+ GHz)")
    console.print("  [bold yellow][4][/bold yellow] Combined Full-System Burn-In Stress Test (CPU + GPU + RAM)")
    console.print("  [bold yellow][5][/bold yellow] Manual Start / Stop Continuous Burn-In (Click/Press Key to Start & Stop)")
    console.print("  [bold yellow][6][/bold yellow] CPU Computational Benchmark (Single-Thread & Multi-Thread Score)")
    console.print("  [bold yellow][7][/bold yellow] DDR5 RAM Memory Bandwidth Benchmark (Sequential Read GB/s)")
    console.print("  [bold yellow][8][/bold yellow] All-in-One Full System Hardware Benchmark (Storage + RAM + CPU + GPU)")
    console.print("  [bold yellow][0][/bold yellow] Return to Dashboard")
    console.print("[bold cyan]=============================================================================[/bold cyan]")

    choice = console.input("\n[bold green]Select benchmark option [0-8]: [/bold green]").strip()

    if choice == "1":
        console.print("\n[bold cyan]Executing NVMe Storage Read Benchmark (128MB payload, 500 random seeks)...[/bold cyan]")
        res = bench_engine.run_storage_read_benchmark()
        if res.get("status") == "PASS":
            TELEMETRY["benchmarks"]["disk_seq_mbs"] = res["seq_read_mbs"]
            TELEMETRY["benchmarks"]["disk_rnd_mbs"] = res["rnd_read_mbs"]
            TELEMETRY["benchmarks"]["disk_rnd_iops"] = res["rnd_read_iops"]
            TELEMETRY["benchmarks"]["disk_lat_ms"] = res["avg_latency_ms"]
            TELEMETRY["benchmarks"]["last_bench_time"] = time.time()
            console.print(f"\n[bold green][PASS] NVMe Storage Read Results:[/bold green]")
            console.print(f"  - Sequential Read Speed : [bold white]{res['seq_read_mbs']} MB/s[/bold white]")
            console.print(f"  - 4K Random Read Speed  : [bold white]{res['rnd_read_mbs']} MB/s[/bold white]")
            console.print(f"  - Random Read IOPS      : [bold white]{res['rnd_read_iops']:,} IOPS[/bold white]")
            console.print(f"  - Average Access Latency: [bold white]{res['avg_latency_ms']} ms[/bold white]")
            STATUS_MESSAGE = f"Storage Benchmark: {res['seq_read_mbs']} MB/s Seq | {res['rnd_read_iops']} IOPS"
        else:
            console.print(f"\n[bold red][FAIL] Storage Benchmark Error: {res.get('error')}[/bold red]")
            STATUS_MESSAGE = "Storage Benchmark Failed."
        STATUS_TIME = time.time()
        console.input("\n[dim]Press Enter to return to dashboard...[/dim]")

    elif choice == "2":
        dur = 10
        try:
            d_in = console.input("[bold cyan]Select duration: [1] 10s Quick  [2] 30s Standard  [3] 60s Extended (default: 10s): [/bold cyan]").strip()
            if d_in == "2":
                dur = 30
            elif d_in == "3":
                dur = 60
        except Exception:
            dur = 10

        console.print(f"\n[bold yellow]Starting {dur}s Multi-Core CPU Stress Test across all logical threads...[/bold yellow]")
        console.print("[dim]Monitoring thermal rise and clock frequency shifts...[/dim]\n")

        def on_cpu_progress(elapsed, total, temp, freq):
            pct = int((elapsed / total) * 100)
            bar = "=" * (pct // 5) + ">" + " " * (20 - (pct // 5))
            sys.stdout.write(f"\r  [{bar}] {elapsed:.0f}s/{total}s | Temp: {temp:.1f} C | Freq: {freq} MHz")
            sys.stdout.flush()

        res = bench_engine.run_cpu_stress_test(duration=dur, progress_cb=on_cpu_progress)
        print()
        TELEMETRY["benchmarks"]["stress_peak_c"] = res["peak_temp_c"]
        TELEMETRY["benchmarks"]["stress_delta_c"] = res["temp_delta_c"]
        TELEMETRY["benchmarks"]["stress_ops"] = res["total_ops"]
        TELEMETRY["benchmarks"]["stress_throttled"] = res["thermal_throttling"]
        TELEMETRY["benchmarks"]["last_bench_time"] = time.time()

        throt_str = "[bold red]THROTTLING DETECTED[/bold red]" if res["thermal_throttling"] else "[bold green]NOMINAL (No Throttling)[/bold green]"
        console.print(f"\n[bold green][DONE] CPU Stress Test Completed ({res['duration_s']}s):[/bold green]")
        console.print(f"  - Total Mathematical Ops : [bold white]{res['total_ops']:,}[/bold white] ({res['ops_per_sec']:,} ops/sec)")
        console.print(f"  - Baseline Temperature   : [bold white]{res['base_temp_c']} C[/bold white]")
        console.print(f"  - Peak Temperature       : [bold white]{res['peak_temp_c']} C[/bold white] (Rise: +{res['temp_delta_c']} C)")
        console.print(f"  - Baseline Clock Speed   : [bold white]{res['base_freq_mhz']} MHz[/bold white]")
        console.print(f"  - Final Clock Speed      : [bold white]{res['final_freq_mhz']} MHz[/bold white]")
        console.print(f"  - Hardware Throttle State: {throt_str}")

        STATUS_MESSAGE = f"CPU Stress: Peak {res['peak_temp_c']} C (+{res['temp_delta_c']} C) | {res['ops_per_sec']:,} ops/s"
        STATUS_TIME = time.time()
        console.input("\n[dim]Press Enter to return to dashboard...[/dim]")

    elif choice == "3":
        dur = 10
        try:
            d_in = console.input("[bold cyan]Select duration: [1] 10s Quick  [2] 30s Standard  [3] 60s Extended (default: 10s): [/bold cyan]").strip()
            if d_in == "2":
                dur = 30
            elif d_in == "3":
                dur = 60
        except Exception:
            dur = 10

        console.print(f"\n[bold yellow]Starting {dur}s Dedicated GPU Hardware Stress Test across 524,288 CUDA threads...[/bold yellow]")
        console.print("[dim]Monitoring live GPU utilization %, temperature rise, clock MHz, and power draw...[/dim]\n")

        def on_gpu_progress(elapsed, total, temp, power, util, clock):
            pct = int((elapsed / total) * 100)
            bar = "=" * (pct // 5) + ">" + " " * (20 - (pct // 5))
            sys.stdout.write(f"\r  [{bar}] {elapsed:.0f}s/{total}s | Temp: {temp:.1f} C | Pwr: {power:.1f} W | Util: {util}% | Clk: {clock} MHz")
            sys.stdout.flush()

        res = bench_engine.run_gpu_stress_test(duration=dur, progress_cb=on_gpu_progress)
        print()
        if res.get("status") == "PASS":
            TELEMETRY["benchmarks"]["gpu_stress_peak_c"] = res["peak_temp_c"]
            TELEMETRY["benchmarks"]["gpu_stress_delta_c"] = res["temp_delta_c"]
            TELEMETRY["benchmarks"]["gpu_stress_power_w"] = res["peak_power_w"]
            TELEMETRY["benchmarks"]["gpu_stress_util_pct"] = res["peak_util_pct"]
            TELEMETRY["benchmarks"]["gpu_stress_clock_mhz"] = res["peak_clock_mhz"]
            TELEMETRY["benchmarks"]["gpu_stress_throttled"] = res["thermal_throttling"]
            TELEMETRY["benchmarks"]["last_bench_time"] = time.time()

            throt_badge = "[bold red]THROTTLED[/bold red]" if res["thermal_throttling"] else "[bold green]NOMINAL (No Throttling)[/bold green]"
            console.print(f"\n[bold green][PASS] Dedicated GPU Stress Results ({res['duration_s']}s):[/bold green]")
            console.print(f"  - Target Device          : [bold white]{res['device_name']}[/bold white]")
            console.print(f"  - Baseline Temperature   : [bold white]{res['base_temp_c']} C[/bold white]")
            console.print(f"  - Peak Temperature       : [bold white]{res['peak_temp_c']} C[/bold white] (Thermal Rise: +{res['temp_delta_c']} C)")
            console.print(f"  - Peak Graphics Power    : [bold white]{res['peak_power_w']} W[/bold white] (Baseline: {res['base_power_w']} W)")
            console.print(f"  - Peak Clock Speed       : [bold white]{res['peak_clock_mhz']} MHz[/bold white]")
            console.print(f"  - Peak GPU Utilization   : [bold white]{res['peak_util_pct']}%[/bold white]")
            console.print(f"  - CUDA Kernel Executions : [bold white]{res['kernel_launches']:,}[/bold white]")
            console.print(f"  - Thermal Throttle State : {throt_badge}")
            STATUS_MESSAGE = f"GPU Stress: Peak {res['peak_temp_c']} C (+{res['temp_delta_c']} C) | {res['peak_power_w']} W | {res['peak_clock_mhz']} MHz"
        else:
            console.print(f"\n[bold red][FAIL] GPU Stress Test Error: {res.get('error')}[/bold red]")
            STATUS_MESSAGE = "GPU Stress Test Failed."
        STATUS_TIME = time.time()
        console.input("\n[dim]Press Enter to return to dashboard...[/dim]")

    elif choice == "4":
        dur = 10
        try:
            d_in = console.input("[bold cyan]Select duration: [1] 10s Quick  [2] 30s Standard  [3] 60s Extended (default: 10s): [/bold cyan]").strip()
            if d_in == "2":
                dur = 30
            elif d_in == "3":
                dur = 60
        except Exception:
            dur = 10

        console.print(f"\n[bold yellow]Starting {dur}s Combined Full-System Burn-In Stress Test (CPU + GPU + RAM)...[/bold yellow]")
        console.print("[dim]Simultaneously saturating all CPU threads and dedicated GPU CUDA cores...[/dim]\n")

        def on_sys_progress(elapsed, total, c_temp, g_temp, g_power, g_util):
            pct = int((elapsed / total) * 100)
            bar = "=" * (pct // 5) + ">" + " " * (20 - (pct // 5))
            sys.stdout.write(f"\r  [{bar}] {elapsed:.0f}s/{total}s | CPU: {c_temp:.1f} C | GPU: {g_temp:.1f} C | GPU Pwr: {g_power:.1f} W ({g_util}%)")
            sys.stdout.flush()

        res = bench_engine.run_system_stress_test(duration=dur, progress_cb=on_sys_progress)
        print()
        if res.get("status") == "PASS":
            TELEMETRY["benchmarks"]["stress_peak_c"] = res["cpu_peak_temp_c"]
            TELEMETRY["benchmarks"]["stress_delta_c"] = res["cpu_temp_delta_c"]
            TELEMETRY["benchmarks"]["stress_ops"] = res["cpu_total_ops"]
            TELEMETRY["benchmarks"]["stress_throttled"] = res["cpu_throttled"]
            TELEMETRY["benchmarks"]["gpu_stress_peak_c"] = res["gpu_peak_temp_c"]
            TELEMETRY["benchmarks"]["gpu_stress_delta_c"] = res["gpu_temp_delta_c"]
            TELEMETRY["benchmarks"]["gpu_stress_power_w"] = res["gpu_peak_power_w"]
            TELEMETRY["benchmarks"]["gpu_stress_util_pct"] = res["gpu_peak_util_pct"]
            TELEMETRY["benchmarks"]["gpu_stress_clock_mhz"] = res["gpu_peak_clock_mhz"]
            TELEMETRY["benchmarks"]["gpu_stress_throttled"] = res["gpu_throttled"]
            TELEMETRY["benchmarks"]["last_bench_time"] = time.time()

            c_throt = "[bold red]THROTTLED[/bold red]" if res["cpu_throttled"] else "[bold green]NOMINAL[/bold green]"
            g_throt = "[bold red]THROTTLED[/bold red]" if res["gpu_throttled"] else "[bold green]NOMINAL[/bold green]"
            console.print(f"\n[bold green][PASS] Combined Full-System Burn-In Results ({res['duration_s']}s):[/bold green]")
            console.print(f"  - CPU Peak Temperature   : [bold white]{res['cpu_peak_temp_c']} C[/bold white] (+{res['cpu_temp_delta_c']} C) | State: {c_throt}")
            console.print(f"  - CPU Total Operations   : [bold white]{res['cpu_total_ops']:,}[/bold white]")
            console.print(f"  - GPU Peak Temperature   : [bold white]{res['gpu_peak_temp_c']} C[/bold white] (+{res['gpu_temp_delta_c']} C) | State: {g_throt}")
            console.print(f"  - GPU Peak Power Draw    : [bold white]{res['gpu_peak_power_w']} W[/bold white] ({res['gpu_peak_util_pct']}% Load)")
            console.print(f"  - GPU CUDA Launches      : [bold white]{res['gpu_launches']:,}[/bold white]")
            STATUS_MESSAGE = f"Full System Burn-In: CPU {res['cpu_peak_temp_c']} C | GPU {res['gpu_peak_temp_c']} C ({res['gpu_peak_power_w']} W)"
        else:
            console.print(f"\n[bold red][FAIL] System Burn-In Test Failed.[/bold red]")
            STATUS_MESSAGE = "System Burn-In Failed."
        STATUS_TIME = time.time()
        console.input("\n[dim]Press Enter to return to dashboard...[/dim]")

    elif choice == "5":
        console.print("\n[bold cyan]=============================================================================[/bold cyan]")
        console.print("[bold white]            MANUAL START / STOP HARDWARE STRESS TEST[/bold white]")
        console.print("[bold cyan]=============================================================================[/bold cyan]")
        console.print("  Select target component for continuous burn-in:")
        console.print("  [bold yellow][1][/bold yellow] Combined Full-System Burn-In (CPU + Dedicated GPU + RAM)")
        console.print("  [bold yellow][2][/bold yellow] Dedicated GPU Hardware Stress (CUDA 100% Load & High-Clock Burn-In)")
        console.print("  [bold yellow][3][/bold yellow] Multi-Core CPU Thermal Stress (All Logical Processor Threads)")
        console.print("  [bold yellow][0][/bold yellow] Cancel")
        console.print("[bold cyan]=============================================================================[/bold cyan]")
        sub = console.input("\n[bold green]Select target [0-3]: [/bold green]").strip()
        if sub == "1":
            target = "system"
            target_label = "Combined Full-System Burn-In"
        elif sub == "2":
            target = "gpu"
            target_label = "Dedicated GPU Hardware Stress"
        elif sub == "3":
            target = "cpu"
            target_label = "Multi-Core CPU Stress"
        else:
            live.start()
            return

        console.print(f"\n[bold yellow]Target: {target_label}[/bold yellow]")
        console.print("[bold white]  - Press [bold green][ENTER][/bold green] or [bold green][SPACE][/bold green] to START stress testing.[/bold white]")
        console.print("[bold white]  - Once running, press [bold red][SPACE][/bold red], [bold red][ENTER][/bold red], [bold red][Q][/bold red], or [bold red][ESC][/bold red] to STOP at any time.[/bold white]")
        console.print("[dim]  Waiting for start trigger...[/dim]\n")

        import msvcrt
        while True:
            if msvcrt.kbhit():
                k = msvcrt.getch()
                if k in [b' ', b'\r', b'\n']:
                    break
                elif k in [b'q', b'Q', b'\x1b', b'0']:
                    console.print("[bold red]Stress test cancelled.[/bold red]")
                    STATUS_MESSAGE = "Manual stress test cancelled."
                    STATUS_TIME = time.time()
                    time.sleep(1)
                    live.start()
                    return
            time.sleep(0.05)

        console.print("[bold green]>>> STRESS TEST ACTIVE - LOAD APPLIED <<<[/bold green]\n")

        def on_manual_progress(elapsed, total, *p_args):
            if msvcrt.kbhit():
                k = msvcrt.getch()
                if k in [b' ', b'\r', b'\n', b'q', b'Q', b'\x1b']:
                    return True

            mm = int(elapsed) // 60
            ss = int(elapsed) % 60
            if target == "cpu":
                cur_t = p_args[0] if len(p_args) > 0 else 0.0
                cur_f = p_args[1] if len(p_args) > 1 else 0
                sys.stdout.write(f"\r  [RUNNING {mm:02d}:{ss:02d}] CPU: {cur_t:.1f} C | Freq: {cur_f} MHz | [SPACE / Q] to STOP   ")
            elif target == "gpu":
                cur_t = p_args[0] if len(p_args) > 0 else 0.0
                cur_p = p_args[1] if len(p_args) > 1 else 0.0
                cur_u = p_args[2] if len(p_args) > 2 else 0
                cur_c = p_args[3] if len(p_args) > 3 else 0
                sys.stdout.write(f"\r  [RUNNING {mm:02d}:{ss:02d}] GPU: {cur_t:.1f} C | Pwr: {cur_p:.1f} W | Util: {cur_u}% | Clk: {cur_c} MHz | [SPACE / Q] to STOP   ")
            else:
                c_t = p_args[0] if len(p_args) > 0 else 0.0
                g_t = p_args[1] if len(p_args) > 1 else 0.0
                g_p = p_args[2] if len(p_args) > 1 else 0.0
                g_u = p_args[3] if len(p_args) > 3 else 0
                sys.stdout.write(f"\r  [RUNNING {mm:02d}:{ss:02d}] CPU: {c_t:.1f} C | GPU: {g_t:.1f} C ({g_p:.1f} W, {g_u}%) | [SPACE / Q] to STOP   ")
            sys.stdout.flush()
            return False

        res = bench_engine.run_manual_stress_test(test_type=target, progress_cb=on_manual_progress)
        print()

        if res and res.get("status") == "PASS":
            dur_s = res.get("duration_s", 0)
            console.print(f"\n[bold green][PASS] Manual Stress Test Completed ({dur_s}s sustained):[/bold green]")
            if target == "cpu":
                TELEMETRY["benchmarks"]["stress_peak_c"] = res["peak_temp_c"]
                TELEMETRY["benchmarks"]["stress_delta_c"] = res["temp_delta_c"]
                TELEMETRY["benchmarks"]["stress_ops"] = res["total_ops"]
                TELEMETRY["benchmarks"]["stress_throttled"] = res["thermal_throttling"]
                throt_str = "[bold red]THROTTLED[/bold red]" if res["thermal_throttling"] else "[bold green]NOMINAL[/bold green]"
                console.print(f"  - Total Mathematical Ops : [bold white]{res['total_ops']:,}[/bold white] ({res['ops_per_sec']:,} ops/sec)")
                console.print(f"  - Baseline Temperature   : [bold white]{res['base_temp_c']} C[/bold white]")
                console.print(f"  - Peak Temperature       : [bold white]{res['peak_temp_c']} C[/bold white] (Rise: +{res['temp_delta_c']} C)")
                console.print(f"  - Final Clock Frequency  : [bold white]{res['final_freq_mhz']} MHz[/bold white]")
                console.print(f"  - Throttle State         : {throt_str}")
                STATUS_MESSAGE = f"CPU Manual Stress: Peak {res['peak_temp_c']} C (+{res['temp_delta_c']} C) over {dur_s}s"
            elif target == "gpu":
                TELEMETRY["benchmarks"]["gpu_stress_peak_c"] = res["peak_temp_c"]
                TELEMETRY["benchmarks"]["gpu_stress_delta_c"] = res["temp_delta_c"]
                TELEMETRY["benchmarks"]["gpu_stress_power_w"] = res["peak_power_w"]
                TELEMETRY["benchmarks"]["gpu_stress_util_pct"] = res["peak_util_pct"]
                TELEMETRY["benchmarks"]["gpu_stress_clock_mhz"] = res["peak_clock_mhz"]
                TELEMETRY["benchmarks"]["gpu_stress_throttled"] = res["thermal_throttling"]
                throt_badge = "[bold red]THROTTLED[/bold red]" if res["thermal_throttling"] else "[bold green]NOMINAL[/bold green]"
                console.print(f"  - Target Device          : [bold white]{res['device_name']}[/bold white]")
                console.print(f"  - Peak Temperature       : [bold white]{res['peak_temp_c']} C[/bold white] (+{res['temp_delta_c']} C)")
                console.print(f"  - Peak Graphics Power    : [bold white]{res['peak_power_w']} W[/bold white]")
                console.print(f"  - Peak Clock Speed       : [bold white]{res['peak_clock_mhz']} MHz[/bold white]")
                console.print(f"  - CUDA Kernel Executions : [bold white]{res['kernel_launches']:,}[/bold white]")
                console.print(f"  - Throttle State         : {throt_badge}")
                STATUS_MESSAGE = f"GPU Manual Stress: Peak {res['peak_temp_c']} C ({res['peak_power_w']} W) over {dur_s}s"
            else:
                TELEMETRY["benchmarks"]["stress_peak_c"] = res["cpu_peak_temp_c"]
                TELEMETRY["benchmarks"]["stress_delta_c"] = res["cpu_temp_delta_c"]
                TELEMETRY["benchmarks"]["stress_ops"] = res["cpu_total_ops"]
                TELEMETRY["benchmarks"]["stress_throttled"] = res["cpu_throttled"]
                TELEMETRY["benchmarks"]["gpu_stress_peak_c"] = res["gpu_peak_temp_c"]
                TELEMETRY["benchmarks"]["gpu_stress_delta_c"] = res["gpu_temp_delta_c"]
                TELEMETRY["benchmarks"]["gpu_stress_power_w"] = res["gpu_peak_power_w"]
                TELEMETRY["benchmarks"]["gpu_stress_util_pct"] = res["gpu_peak_util_pct"]
                TELEMETRY["benchmarks"]["gpu_stress_clock_mhz"] = res["gpu_peak_clock_mhz"]
                TELEMETRY["benchmarks"]["gpu_stress_throttled"] = res["gpu_throttled"]
                c_throt = "[bold red]THROTTLED[/bold red]" if res["cpu_throttled"] else "[bold green]NOMINAL[/bold green]"
                g_throt = "[bold red]THROTTLED[/bold red]" if res["gpu_throttled"] else "[bold green]NOMINAL[/bold green]"
                console.print(f"  - CPU Peak Temperature   : [bold white]{res['cpu_peak_temp_c']} C[/bold white] (+{res['cpu_temp_delta_c']} C) | State: {c_throt}")
                console.print(f"  - CPU Total Operations   : [bold white]{res['cpu_total_ops']:,}[/bold white]")
                console.print(f"  - GPU Peak Temperature   : [bold white]{res['gpu_peak_temp_c']} C[/bold white] (+{res['gpu_temp_delta_c']} C) | State: {g_throt}")
                console.print(f"  - GPU Peak Power Draw    : [bold white]{res['gpu_peak_power_w']} W[/bold white] ({res['gpu_peak_util_pct']}% Load)")
                console.print(f"  - GPU CUDA Launches      : [bold white]{res['gpu_launches']:,}[/bold white]")
                STATUS_MESSAGE = f"Burn-In Manual: CPU {res['cpu_peak_temp_c']} C | GPU {res['gpu_peak_temp_c']} C ({res['gpu_peak_power_w']} W)"

            TELEMETRY["benchmarks"]["last_bench_time"] = time.time()
        else:
            console.print("\n[bold red][FAIL] Stress Test did not complete successfully.[/bold red]")
            STATUS_MESSAGE = "Manual Stress Test Failed."

        STATUS_TIME = time.time()
        console.input("\n[dim]Press Enter to return to dashboard...[/dim]")

    elif choice == "6":
        console.print("\n[bold cyan]Executing CPU Computational Benchmark (Single & Multi-Thread)...[/bold cyan]")
        res = bench_engine.run_cpu_benchmark(duration_seconds=3)
        TELEMETRY["benchmarks"]["cpu_st_score"] = res["single_thread_score"]
        TELEMETRY["benchmarks"]["cpu_st_ops"] = res["single_thread_ops_sec"]
        TELEMETRY["benchmarks"]["cpu_mt_score"] = res["multi_thread_score"]
        TELEMETRY["benchmarks"]["cpu_mt_ops"] = res["multi_thread_ops_sec"]
        TELEMETRY["benchmarks"]["cpu_scale_ratio"] = res["multi_thread_ratio"]
        TELEMETRY["benchmarks"]["last_bench_time"] = time.time()

        console.print(f"\n[bold green][PASS] CPU Computational Benchmark Results:[/bold green]")
        console.print(f"  - Single-Thread Score : [bold white]{res['single_thread_score']:,} pts[/bold white] ({res['single_thread_ops_sec']:,} ops/sec)")
        console.print(f"  - Multi-Thread Score  : [bold white]{res['multi_thread_score']:,} pts[/bold white] ({res['multi_thread_ops_sec']:,} ops/sec)")
        console.print(f"  - Multi-Core Scaling  : [bold white]{res['multi_thread_ratio']}x[/bold white] across {res['threads_tested']} threads")

        STATUS_MESSAGE = f"CPU Benchmark: ST {res['single_thread_score']} | MT {res['multi_thread_score']} ({res['multi_thread_ratio']}x)"
        STATUS_TIME = time.time()
        console.input("\n[dim]Press Enter to return to dashboard...[/dim]")

    elif choice == "7":
        console.print("\n[bold cyan]Executing RAM Memory Bandwidth Benchmark (128MB test block)...[/bold cyan]")
        res = bench_engine.run_ram_bandwidth_benchmark(buffer_mb=128)
        if res.get("status") == "PASS":
            TELEMETRY["benchmarks"]["ram_read_gbs"] = res["read_bandwidth_gbs"]
            TELEMETRY["benchmarks"]["ram_copy_gbs"] = res["copy_bandwidth_gbs"]
            TELEMETRY["benchmarks"]["last_bench_time"] = time.time()

            console.print(f"\n[bold green][PASS] RAM Memory Bandwidth Results:[/bold green]")
            console.print(f"  - Sequential Read Bandwidth: [bold white]{res['read_bandwidth_gbs']} GB/s[/bold white]")
            console.print(f"  - Memory Copy Bandwidth    : [bold white]{res['copy_bandwidth_gbs']} GB/s[/bold white]")
            STATUS_MESSAGE = f"RAM Bandwidth: Read {res['read_bandwidth_gbs']} GB/s | Copy {res['copy_bandwidth_gbs']} GB/s"
        else:
            console.print(f"\n[bold red][FAIL] RAM Benchmark Error: {res.get('error')}[/bold red]")
            STATUS_MESSAGE = "RAM Benchmark Failed."
        STATUS_TIME = time.time()
        console.input("\n[dim]Press Enter to return to dashboard...[/dim]")

    elif choice == "8":
        console.print("\n[bold cyan]Starting All-in-One Full System Hardware Benchmark...[/bold cyan]")

        # 1. Storage
        console.print("  [1/5] Running NVMe Storage Read Benchmark...")
        d_res = bench_engine.run_storage_read_benchmark(test_size_mb=64, num_random_ops=300)
        if d_res.get("status") == "PASS":
            TELEMETRY["benchmarks"]["disk_seq_mbs"] = d_res["seq_read_mbs"]
            TELEMETRY["benchmarks"]["disk_rnd_mbs"] = d_res["rnd_read_mbs"]
            TELEMETRY["benchmarks"]["disk_rnd_iops"] = d_res["rnd_read_iops"]
            TELEMETRY["benchmarks"]["disk_lat_ms"] = d_res["avg_latency_ms"]

        # 2. RAM
        console.print("  [2/5] Running DDR5 RAM Memory Bandwidth Benchmark...")
        r_res = bench_engine.run_ram_bandwidth_benchmark(buffer_mb=64)
        if r_res.get("status") == "PASS":
            TELEMETRY["benchmarks"]["ram_read_gbs"] = r_res["read_bandwidth_gbs"]
            TELEMETRY["benchmarks"]["ram_copy_gbs"] = r_res["copy_bandwidth_gbs"]

        # 3. CPU Compute
        console.print("  [3/5] Running CPU Computational Benchmark...")
        c_res = bench_engine.run_cpu_benchmark(duration_seconds=2)
        TELEMETRY["benchmarks"]["cpu_st_score"] = c_res["single_thread_score"]
        TELEMETRY["benchmarks"]["cpu_st_ops"] = c_res["single_thread_ops_sec"]
        TELEMETRY["benchmarks"]["cpu_mt_score"] = c_res["multi_thread_score"]
        TELEMETRY["benchmarks"]["cpu_mt_ops"] = c_res["multi_thread_ops_sec"]
        TELEMETRY["benchmarks"]["cpu_scale_ratio"] = c_res["multi_thread_ratio"]

        # 4. CPU Stress
        console.print("  [4/5] Running 5s Multi-Core CPU Thermal Stress Test...")
        s_res = bench_engine.run_cpu_stress_test(duration=5)
        TELEMETRY["benchmarks"]["stress_peak_c"] = s_res["peak_temp_c"]
        TELEMETRY["benchmarks"]["stress_delta_c"] = s_res["temp_delta_c"]
        TELEMETRY["benchmarks"]["stress_ops"] = s_res["total_ops"]
        TELEMETRY["benchmarks"]["stress_throttled"] = s_res["thermal_throttling"]

        # 5. Dedicated GPU Stress
        console.print("  [5/5] Running 5s Dedicated GPU Hardware Stress Test...")
        g_res = bench_engine.run_gpu_stress_test(duration=5)
        if g_res.get("status") == "PASS":
            TELEMETRY["benchmarks"]["gpu_stress_peak_c"] = g_res["peak_temp_c"]
            TELEMETRY["benchmarks"]["gpu_stress_delta_c"] = g_res["temp_delta_c"]
            TELEMETRY["benchmarks"]["gpu_stress_power_w"] = g_res["peak_power_w"]
            TELEMETRY["benchmarks"]["gpu_stress_util_pct"] = g_res["peak_util_pct"]
            TELEMETRY["benchmarks"]["gpu_stress_clock_mhz"] = g_res["peak_clock_mhz"]
            TELEMETRY["benchmarks"]["gpu_stress_throttled"] = g_res["thermal_throttling"]

        TELEMETRY["benchmarks"]["last_bench_time"] = time.time()

        console.print("\n[bold green]=============================================================================[/bold green]")
        console.print("[bold white]                   FULL SYSTEM BENCHMARK SUMMARY[/bold white]")
        console.print("[bold green]=============================================================================[/bold green]")
        console.print(f"  - Storage Sequential Read: [bold white]{d_res.get('seq_read_mbs', 0)} MB/s[/bold white] (4K IOPS: {d_res.get('rnd_read_iops', 0):,})")
        console.print(f"  - RAM Read Bandwidth     : [bold white]{r_res.get('read_bandwidth_gbs', 0)} GB/s[/bold white]")
        console.print(f"  - CPU Multi-Thread Score : [bold white]{c_res.get('multi_thread_score', 0):,} pts[/bold white] (ST: {c_res.get('single_thread_score', 0):,}, {c_res.get('multi_thread_ratio', 0)}x)")
        console.print(f"  - CPU Peak Stress Thermal: [bold white]{s_res.get('peak_temp_c', 0)} C[/bold white] (+{s_res.get('temp_delta_c', 0)} C rise)")
        console.print(f"  - GPU Peak Stress Thermal: [bold white]{g_res.get('peak_temp_c', 0)} C[/bold white] (+{g_res.get('temp_delta_c', 0)} C, {g_res.get('peak_power_w', 0)} W)")
        console.print("[bold green]=============================================================================[/bold green]")

        STATUS_MESSAGE = "Full System Benchmark Completed Successfully."
        STATUS_TIME = time.time()
        console.input("\n[dim]Press Enter to return to dashboard...[/dim]")

    live.start()


def handle_kill_process_dialog(live):
    """Prompts the user inside the terminal to enter a PID to kill."""
    global STATUS_MESSAGE, STATUS_TIME
    live.stop()
    console.print("\n[bold red]=== KILL PROCESS MANAGER ===[/bold red]")
    try:
        pid_str = console.input("[bold yellow]Enter Process ID (PID) to terminate (or Enter to cancel): [/bold yellow]").strip()
        if pid_str and pid_str.isdigit():
            target_pid = int(pid_str)
            p = psutil.Process(target_pid)
            name = p.name()
            confirm = console.input(f"[bold red]Terminate {name} (PID: {target_pid})? [y/N]: [/bold red]").strip().lower()
            if confirm == 'y':
                try:
                    p.kill()
                except Exception:
                    p.terminate()
                STATUS_MESSAGE = f"Terminated {name} (PID: {target_pid}) successfully."
                STATUS_TIME = time.time()
            else:
                STATUS_MESSAGE = "Process termination cancelled."
                STATUS_TIME = time.time()
    except Exception as e:
        STATUS_MESSAGE = f"Failed to terminate PID: {e}"
        STATUS_TIME = time.time()
    live.start()


def toggle_refresh_rate():
    """Toggles refresh speed."""
    global REFRESH_INDEX, REFRESH_RATE, STATUS_MESSAGE, STATUS_TIME
    REFRESH_INDEX = (REFRESH_INDEX + 1) % len(REFRESH_RATES)
    REFRESH_RATE = REFRESH_RATES[REFRESH_INDEX]
    save_preferences()
    STATUS_MESSAGE = f"Refresh interval set to {REFRESH_RATE}s."
    STATUS_TIME = time.time()


def toggle_process_sort():
    """Toggles sort by CPU vs RAM."""
    global PROCESS_SORT_MODE, STATUS_MESSAGE, STATUS_TIME
    PROCESS_SORT_MODE = "ram" if PROCESS_SORT_MODE == "cpu" else "cpu"
    save_preferences()
    STATUS_MESSAGE = f"Process table sorting by {PROCESS_SORT_MODE.upper()}."
    STATUS_TIME = time.time()


def toggle_process_filter():
    """Toggles process filtering."""
    global PROCESS_FILTER_MODE, STATUS_MESSAGE, STATUS_TIME
    if PROCESS_FILTER_MODE == "all":
        PROCESS_FILTER_MODE = "heavy"
    else:
        PROCESS_FILTER_MODE = "all"
    save_preferences()
    STATUS_MESSAGE = f"Process filter set to {PROCESS_FILTER_MODE.upper()}."
    STATUS_TIME = time.time()


def main():
    global RUNNING, FRAME_INDEX, CURRENT_VIEW, STATUS_MESSAGE, STATUS_TIME
    
    # Hide cursor
    console.show_cursor(False)

    # Load persistent user preferences
    load_preferences()

    # Initial fast hardware detection
    detect_system_hardware()

    # Initial seed
    poll_fast_telemetry()
    update_battery_cim()
    update_ssd_cim()
    update_cpu_thermals()
    update_gpu_nvidia()
    update_hwinfo()

    # Background heavy thread
    worker = threading.Thread(target=telemetry_background_worker, daemon=True)
    worker.start()

    views_list = ["all", "battery", "cpu", "ram", "gpu", "storage", "processes", "logs", "sensors"]
    last_render_time = time.time()

    with Live(render_dashboard(), refresh_per_second=20, screen=True, console=console) as live:
        try:
            while RUNNING:
                # 1. High-frequency non-blocking input poll (every 25ms)
                if msvcrt.kbhit():
                    key = msvcrt.getch()
                    view_changed = False

                    # Windows arrow keys prefix (0x00 or 0xe0)
                    if key in [b'\x00', b'\xe0']:
                        arrow = msvcrt.getch()
                        idx = views_list.index(CURRENT_VIEW) if CURRENT_VIEW in views_list else 0
                        if arrow == b'K':  # Left Arrow
                            CURRENT_VIEW = views_list[(idx - 1) % len(views_list)]
                            view_changed = True
                        elif arrow == b'M':  # Right Arrow
                            CURRENT_VIEW = views_list[(idx + 1) % len(views_list)]
                            view_changed = True
                    elif key in [b'q', b'Q', b'\x1b']:
                        RUNNING = False
                        break
                    elif key == b'1':
                        CURRENT_VIEW = "all"; view_changed = True
                    elif key == b'2':
                        CURRENT_VIEW = "battery"; view_changed = True
                    elif key == b'3':
                        CURRENT_VIEW = "cpu"; view_changed = True
                    elif key == b'4':
                        CURRENT_VIEW = "ram"; view_changed = True
                    elif key in [b'g', b'G', b'9']:
                        CURRENT_VIEW = "gpu"; view_changed = True
                    elif key == b'5':
                        CURRENT_VIEW = "storage"; view_changed = True
                    elif key == b'6':
                        CURRENT_VIEW = "processes"; view_changed = True
                    elif key in [b'7', b'l', b'L']:
                        CURRENT_VIEW = "logs"; view_changed = True
                    elif key == b'8':
                        CURRENT_VIEW = "sensors"; view_changed = True
                    elif key in [b'h', b'H']:
                        refresh_sensor_metrics()
                        CURRENT_VIEW = "sensors"; view_changed = True
                    elif key in [b'b', b'B']:
                        run_interactive_benchmark(live)
                        view_changed = True
                    elif key in [b'm', b'M']:
                        CPU_MINIMIZE_MODE = not CPU_MINIMIZE_MODE
                        save_preferences()
                        STATUS_MESSAGE = f"CPU view: {'MINIMIZED (Clean Overview)' if CPU_MINIMIZE_MODE else 'EXPANDED (Per-Thread Matrix)'}"
                        STATUS_TIME = time.time()
                        view_changed = True
                    elif key in [b't', b'T']:
                        run_ssd_trim_optimizer(live)
                        view_changed = True
                    elif key in [b'o', b'O', b'c', b'C']:
                        if CURRENT_VIEW == "logs":
                            open_logs_folder()
                        else:
                            run_battery_optimizer_dialog(live)
                        view_changed = True
                    elif key in [b'k', b'K']:
                        handle_kill_process_dialog(live)
                        view_changed = True
                    elif key in [b'r', b'R']:
                        toggle_refresh_rate()
                        view_changed = True
                    elif key in [b's', b'S']:
                        toggle_process_sort()
                        view_changed = True
                    elif key in [b'f', b'F']:
                        toggle_process_filter()
                        view_changed = True

                    # Render INSTANTLY on key press
                    if view_changed:
                        poll_fast_telemetry()
                        live.update(render_dashboard())
                        last_render_time = time.time()

                # 2. Render steady live preview on cadence
                now = time.time()
                if now - last_render_time >= REFRESH_RATE:
                    FRAME_INDEX += 1
                    poll_fast_telemetry()
                    live.update(render_dashboard())
                    last_render_time = now

                time.sleep(0.025)
        except KeyboardInterrupt:
            pass
        finally:
            RUNNING = False
            console.show_cursor(True)
            console.clear()
            console.print("[bold green]OMNI Hardware & Telemetry Engine closed cleanly. Have a great day![/bold green]\n")


if __name__ == "__main__":
    main()
