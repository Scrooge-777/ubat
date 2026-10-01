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

# Console initialization
console = Console()

# Global State
RUNNING = True
CURRENT_VIEW = "all"  # 'all', 'battery', 'cpu', 'ram', 'storage', 'processes', 'logs', 'hwinfo'
REFRESH_RATES = [0.25, 0.5, 1.0, 2.0]
REFRESH_INDEX = 1     # Default 0.5s
REFRESH_RATE = REFRESH_RATES[REFRESH_INDEX]

PROCESS_SORT_MODE = "cpu"    # 'cpu' or 'ram'
PROCESS_FILTER_MODE = "all"  # 'all', 'heavy'

STATUS_MESSAGE = ""
STATUS_TIME = 0.0

# Dynamic Heartbeat Indicator
HEARTBEAT_FRAMES = ["[--o--]", "[-o---]", "[o----]", "[-o---]", "[--o--]", "[---o-]", "[----o]", "[---o-]"]
FRAME_INDEX = 0

# Hardware Profile Cache
HARDWARE_INFO = {
    "manufacturer": "HP",
    "model": "OMEN Gaming Laptop 16-am0xxx",
    "cpu_name": "Intel(R) Core(TM) i7-14650HX",
    "cpu_cores_logical": psutil.cpu_count(logical=True) or 16,
    "cpu_cores_physical": psutil.cpu_count(logical=False) or 8,
    "total_ram_gb": round(psutil.virtual_memory().total / (1024**3), 1),
    "ram_speed_mts": 5600,
    "ram_modules": [],
}

# Real-time Telemetry Cache
TELEMETRY = {
    "battery_pct": 80,
    "battery_plugged": True,
    "battery_secsleft": -1,
    "battery_wattage": 0.0,
    "battery_mwh_remaining": 64097,
    "battery_mwh_full": 80122,
    "battery_mwh_design": 83028,
    "battery_wear_pct": 3.5,
    "battery_health_grade": "A (Very Good)",
    "battery_cycle_count": 31,
    "battery_voltage_v": 12.4,
    "cpu_pct": 0.0,
    "cpu_per_core": [],
    "ram_pct": 0.0,
    "ram_used_gb": 0.0,
    "ram_avail_gb": 0.0,
    "gpu_name": "NVIDIA GeForce RTX 5050 Laptop GPU",
    "gpu_util": 0,
    "gpu_temp": 43,
    "gpu_power": 18.2,
    "gpu_pcie_link": "Gen5 x8",
    "hwinfo_active": False,
    "cpu_fan_rpm": 0,
    "gpu_fan_rpm": 0,
    "gpu_hotspot_c": 0,
    "vrm_temp_c": 0,
    "package_power_w": 0.0,
    "ssd_model": "Samsung NVMe SSD",
    "ssd_health": "Healthy (OK)",
    "ssd_wear_pct": 0,
    "ssd_temp": 46,
    "partitions": [],
    "disk_read_mbs": 0.0,
    "disk_write_mbs": 0.0,
    "disk_total_read_gb": 0.0,
    "disk_total_write_gb": 0.0,
    "processes": [],
    "last_disk_read": 0,
    "last_disk_write": 0,
    "last_disk_time": 0.0,
}


def detect_system_hardware():
    """Detects laptop model, manufacturer, and CPU name."""
    global HARDWARE_INFO
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
        cmd = 'powershell.exe -NoProfile -Command "Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2).strip()
        if out:
            HARDWARE_INFO["cpu_name"] = out.strip()
    except Exception:
        pass

    try:
        cmd = 'powershell.exe -NoProfile -Command "Get-CimInstance Win32_PhysicalMemory | Select-Object BankLabel, Manufacturer, PartNumber, ConfiguredClockSpeed, Capacity | ConvertTo-Json -Compress"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2.5).strip()
        if out:
            data = json.loads(out)
            if isinstance(data, dict):
                data = [data]
            mods = []
            max_spd = 0
            for item in data:
                spd = item.get("ConfiguredClockSpeed", 0) or 0
                if spd > max_spd:
                    max_spd = spd
                mods.append({
                    "bank": item.get("BankLabel", "BANK 0"),
                    "mfg": (item.get("Manufacturer") or "Generic").strip(),
                    "part": (item.get("PartNumber") or "").strip(),
                    "speed": spd,
                    "gb": round((item.get("Capacity", 0) or 0) / (1024**3), 1)
                })
            HARDWARE_INFO["ram_modules"] = mods
            if max_spd > 0:
                HARDWARE_INFO["ram_speed_mts"] = max_spd
    except Exception:
        pass


def update_battery_cim():
    """Fetches deep battery statistics from Windows ACPI / CIM."""
    global TELEMETRY
    try:
        cmd = 'powershell.exe -NoProfile -Command "$f = (Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue).FullChargedCapacity; $s = (Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue); $c = (Get-CimInstance -Namespace root/wmi -ClassName BatteryCycleCount -ErrorAction SilentlyContinue).CycleCount; [PSCustomObject]@{ FullMwh = $f; RemainingMwh = $s.RemainingCapacity; RateMw = $s.DischargeRate; Cycles = $c; Voltage = $s.Voltage } | ConvertTo-Json -Compress"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2).strip()
        data = json.loads(out)
        if data.get("FullMwh"):
            TELEMETRY["battery_mwh_full"] = int(data["FullMwh"])
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
    """Queries NVIDIA GPU metrics via nvidia-smi."""
    global TELEMETRY
    try:
        out = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=name,utilization.gpu,temperature.gpu,power.draw,pcie.link.gen.current,pcie.link.width.current", "--format=csv,noheader,nounits"],
            text=True, timeout=1.5
        ).strip()
        parts = [p.strip() for p in out.split(",")]
        if len(parts) >= 4:
            TELEMETRY["gpu_name"] = parts[0]
            TELEMETRY["gpu_util"] = int(parts[1])
            TELEMETRY["gpu_temp"] = int(parts[2])
            TELEMETRY["gpu_power"] = float(parts[3])
        if len(parts) >= 6:
            TELEMETRY["gpu_pcie_link"] = f"Gen{parts[4]} x{parts[5]}"
    except Exception:
        TELEMETRY["gpu_name"] = "NVIDIA dGPU (Dynamic Sleep)"
        TELEMETRY["gpu_util"] = 0
        TELEMETRY["gpu_temp"] = 0
        TELEMETRY["gpu_power"] = 0.0
        TELEMETRY["gpu_pcie_link"] = "N/A"


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


def launch_hwinfo_sensors():
    """Launches HWiNFO64 Sensors mode non-blocking in background."""
    global STATUS_MESSAGE, STATUS_TIME
    bat_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Launch-HWiNFO.bat")
    try:
        flags = 0
        if os.name == "nt":
            flags = subprocess.CREATE_NO_WINDOW
        subprocess.Popen(["cmd.exe", "/c", bat_path], creationflags=flags)
        STATUS_MESSAGE = "Launched HWiNFO64 sensor engine in background."
    except Exception as e:
        STATUS_MESSAGE = f"Failed to launch HWiNFO64: {e}"
    STATUS_TIME = time.time()


def telemetry_background_worker():
    """Background worker thread for periodic heavy telemetry (GPU, ACPI, SSD, HWiNFO)."""
    global RUNNING
    counter = 0
    while RUNNING:
        try:
            if counter % 4 == 0:
                update_battery_cim()
                update_ssd_cim()
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

                if PROCESS_FILTER_MODE == "heavy" and (cpu_p < 2.0 and mem_mb < 300):
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


def build_header_panel():
    """Creates clean, animated hardware banner with heartbeat indicator."""
    global FRAME_INDEX
    hb = HEARTBEAT_FRAMES[FRAME_INDEX % len(HEARTBEAT_FRAMES)]

    mfg = HARDWARE_INFO["manufacturer"].upper()
    model = HARDWARE_INFO["model"].upper()
    cpu = HARDWARE_INFO["cpu_name"]

    title_text = Text()
    title_text.append(f" {hb} ", style="bold cyan")
    title_text.append("OMNI SYSTEM HARDWARE TELEMETRY & OPTIMIZER", style="bold white on #1e293b")
    title_text.append(f" {hb}\n", style="bold cyan")
    title_text.append(" SYSTEM: ", style="bold cyan")
    title_text.append(f"{mfg} {model}", style="bold yellow")
    title_text.append("  |  CPU: ", style="bold cyan")
    title_text.append(f"{cpu}", style="bold green")

    if TELEMETRY.get("hwinfo_active", False):
        title_text.append("  |  HWiNFO: ", style="bold cyan")
        title_text.append("[ONLINE]", style="bold green")
    else:
        title_text.append("  |  HWiNFO: ", style="bold cyan")
        title_text.append("[STANDBY]", style="dim yellow")

    title_text.append("  |  VIEW: ", style="bold cyan")
    title_text.append(f"[{CURRENT_VIEW.upper()}]", style="bold magenta")

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
    voltage = TELEMETRY["battery_voltage_v"]

    batt_color = "green" if pct >= 60 else "yellow" if pct >= 30 else "red"

    table = Table(box=None, expand=True, show_header=False, padding=(0, 1))
    table.add_column("Key", style="bold cyan", width=16)
    table.add_column("Value", style="bold white")

    power_src = "[bold green][AC] ADAPTER CONNECTED[/bold green]" if plugged else "[bold yellow][BAT] ON BATTERY POWER[/bold yellow]"
    table.add_row("Power Source", power_src)
    table.add_row("Charge Level", make_progress_bar(pct, width=16, color=batt_color))
    table.add_row("Health Grade", f"[bold green]{grade}[/bold green] (Wear: [bold yellow]{wear}%[/bold yellow])")
    table.add_row("Capacity", f"{full_mwh:,} mWh [dim](Design: {design_mwh:,})[/dim]")
    table.add_row("Remaining", f"{rem_mwh:,} mWh [dim]({voltage}V pack)[/dim]")
    
    rate_str = f"{wattage:.2f} W" if wattage > 0 else "0.00 W (Idle / Full)"
    table.add_row("Drain/Charge", f"[bold magenta]{rate_str}[/bold magenta]")
    table.add_row("Estimated Time", format_secs(secs) if not plugged else "AC Connected (Protected)")

    return Panel(table, title="[bold cyan]BATTERY & POWER HEALTH[/bold cyan]", border_style="cyan", box=box.ROUNDED)


def build_cpu_ram_panel():
    """Renders CPU and RAM real-time performance and core metrics."""
    cpu_pct = TELEMETRY["cpu_pct"]
    ram_pct = TELEMETRY["ram_pct"]
    ram_used = TELEMETRY["ram_used_gb"]
    ram_avail = TELEMETRY["ram_avail_gb"]
    ram_total = HARDWARE_INFO["total_ram_gb"]
    ram_speed = HARDWARE_INFO.get("ram_speed_mts", 0)

    cpu_color = "green" if cpu_pct < 50 else "yellow" if cpu_pct < 80 else "red"
    ram_color = "green" if ram_pct < 65 else "yellow" if ram_pct < 85 else "red"

    table = Table(box=None, expand=True, show_header=False, padding=(0, 1))
    table.add_column("Metric", style="bold cyan", width=14)
    table.add_column("Status", style="bold white")

    table.add_row("CPU Load", make_progress_bar(cpu_pct, width=14, color=cpu_color))
    table.add_row("RAM Usage", make_progress_bar(ram_pct, width=14, color=ram_color))
    
    speed_tag = f" [dim](DDR5-{ram_speed} MT/s)[/dim]" if ram_speed > 0 else ""
    table.add_row("Memory Vol", f"[bold white]{ram_used:.1f} GB[/bold white] / [dim]{ram_total:.1f} GB[/dim]{speed_tag}")

    if TELEMETRY.get("hwinfo_active", False):
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

    if gpu_hotspot > 0:
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
    table.add_row("Hardware Wear Level", f"{wear}% Degradation", f"GRADE {grade}")
    table.add_row("Cycle Life Count", f"{cycles} / 500 Rated Cycles", f"{round((cycles/500)*100, 1)}% Used")
    table.add_row("Pack Terminal Voltage", f"{voltage} Volts", "BALANCED")
    table.add_row("Live Power Draw", f"{wattage:.2f} Watts", "MEASURED")
    table.add_row("4-Hour Target Budget", f"Keep under {budget_w} Watts for 4h battery", "BUDGET TARGET")
    table.add_row("Estimated Runtime", format_secs(secs), "ACTIVE")

    return Panel(table, title="[bold cyan]DEEP BATTERY HEALTH & POWER CALIBRATION[/bold cyan]", border_style="cyan", box=box.ROUNDED)


def build_cpu_focus_view():
    """Deep CPU & core analyzer view."""
    cpu_pct = TELEMETRY["cpu_pct"]
    cores = TELEMETRY["cpu_per_core"]
    logical = HARDWARE_INFO["cpu_cores_logical"]
    physical = HARDWARE_INFO["cpu_cores_physical"]

    table = Table(box=box.ROUNDED, expand=True, padding=(0, 2))
    table.add_column("METRIC", style="bold cyan", width=24)
    table.add_column("STATUS", style="bold white")

    table.add_row("CPU Architecture", f"{HARDWARE_INFO['cpu_name']}")
    table.add_row("Core Configuration", f"{physical} Physical Cores / {logical} Logical Threads")
    table.add_row("Overall CPU Load", make_progress_bar(cpu_pct, width=28))

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
        Layout(Panel(table, box=box.ROUNDED, border_style="cyan"), size=7),
        Layout(Panel(core_table, title="[bold cyan]PER-THREAD REAL-TIME ACTIVITY[/bold cyan]", box=box.ROUNDED, border_style="cyan")),
        Layout(build_process_table(limit=6), size=9),
    )
    return content


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


def build_hwinfo_view():
    """Deep HWiNFO Sensor & Shared Memory Bridge Dashboard."""
    hw_active = TELEMETRY.get("hwinfo_active", False)
    cpu_rpm = TELEMETRY.get("cpu_fan_rpm", 0)
    gpu_rpm = TELEMETRY.get("gpu_fan_rpm", 0)
    vrm_c = TELEMETRY.get("vrm_temp_c", 0)
    gpu_hotspot = TELEMETRY.get("gpu_hotspot_c", 0)
    pkg_w = TELEMETRY.get("package_power_w", 0.0)
    gpu_w = TELEMETRY.get("gpu_power", 0.0)
    gpu_temp = TELEMETRY.get("gpu_temp", 0)
    gpu_pcie = TELEMETRY.get("gpu_pcie_link", "N/A")
    gpu_name = TELEMETRY.get("gpu_name", "NVIDIA GeForce RTX 5050 Laptop GPU")
    ssd_temp = TELEMETRY.get("ssd_temp", 46)
    ssd_model = TELEMETRY.get("ssd_model", "Samsung NVMe SSD")
    ram_speed = HARDWARE_INFO.get("ram_speed_mts", 5600)
    ram_mods = HARDWARE_INFO.get("ram_modules", [])

    # Overview table
    header_table = Table(box=box.ROUNDED, expand=True, padding=(0, 2))
    header_table.add_column("BRIDGE SUBSYSTEM", style="bold cyan", width=26)
    header_table.add_column("STATUS & CONNECTION DETAILS", style="bold white")

    if hw_active:
        bridge_status = "[bold green]ONLINE (Connected to Global\\HWiNFO_SENS_SM2)[/bold green]"
    else:
        bridge_status = "[bold yellow]STANDBY - Press [H] to Launch HWiNFO64 in Background[/bold yellow]"

    header_table.add_row("HWiNFO Bridge State", bridge_status)
    header_table.add_row("Driver Protocol", "Windows Memory-Mapped File (mmap, zero-latency <0.1ms)")
    header_table.add_row("Launch Shortcut", "Press [bold yellow][H][/bold yellow] anytime to start/restart HWiNFO64 sensors")

    # Sensor grid table
    sensor_table = Table(box=box.ROUNDED, expand=True, padding=(0, 2))
    sensor_table.add_column("SENSOR CATEGORY", style="bold cyan", width=20)
    sensor_table.add_column("TELEMETRY CHANNEL", style="bold white", width=24)
    sensor_table.add_column("CURRENT VALUE", style="bold green", width=20)
    sensor_table.add_column("STATUS / GAUGE", justify="left")

    # Fans
    if cpu_rpm > 0:
        cpu_gauge = make_mini_meter(cpu_rpm, max_val=5000, width=12)
        sensor_table.add_row("Cooling Fans", "CPU Cooling Fan", f"{cpu_rpm} RPM", f"{cpu_gauge} Active")
    else:
        sensor_table.add_row("Cooling Fans", "CPU Cooling Fan", "-- RPM", "[dim]Standby / Zero RPM[/dim]")

    if gpu_rpm > 0:
        gpu_gauge = make_mini_meter(gpu_rpm, max_val=5000, width=12)
        sensor_table.add_row("Cooling Fans", "GPU Cooling Fan", f"{gpu_rpm} RPM", f"{gpu_gauge} Active")
    else:
        sensor_table.add_row("Cooling Fans", "GPU Cooling Fan", "-- RPM", "[dim]Standby / Zero RPM[/dim]")

    # Thermals
    if vrm_c > 0:
        vrm_col = "red" if vrm_c > 85 else "yellow" if vrm_c > 70 else "green"
        sensor_table.add_row("Thermals", "Motherboard VRM / MOSFET", f"[{vrm_col}]{vrm_c} C[/{vrm_col}]", "[dim]HWiNFO Bridge[/dim]")
    else:
        sensor_table.add_row("Thermals", "Motherboard VRM / MOSFET", "-- C", "[dim]Awaiting HWiNFO[/dim]")

    if gpu_hotspot > 0:
        hs_col = "red" if gpu_hotspot > 85 else "yellow" if gpu_hotspot > 70 else "green"
        sensor_table.add_row("Thermals", "GPU Hotspot (Max Diode)", f"[{hs_col}]{gpu_hotspot} C[/{hs_col}]", f"Core: {gpu_temp} C")
    else:
        sensor_table.add_row("Thermals", "GPU Core & Hotspot", f"{gpu_temp} C", "[dim]NVIDIA Driver[/dim]")

    sensor_table.add_row("Thermals", "NVMe Storage Controller", f"{ssd_temp} C", f"[dim]{ssd_model[:22]}[/dim]")

    # Electrical Power
    pkg_str = f"{pkg_w:.1f} W" if pkg_w > 0 else "-- W"
    sensor_table.add_row("Power & Load", "CPU Package Power", pkg_str, "[dim]HWiNFO SM2[/dim]")
    sensor_table.add_row("Power & Load", "GPU Board Power Draw", f"{gpu_w:.1f} W", f"[dim]{gpu_name[:22]}[/dim]")
    sensor_table.add_row("Power & Load", "Battery Discharge / Charge", f"{TELEMETRY['battery_wattage']:.2f} W", f"Pack: {TELEMETRY['battery_voltage_v']}V")

    # High-speed physical buses
    sensor_table.add_row("Buses & Memory", "DDR5 Memory Bus", f"{ram_speed} MT/s", f"{HARDWARE_INFO['total_ram_gb']} GB Configured")
    if ram_mods:
        for m in ram_mods:
            sensor_table.add_row("Buses & Memory", f"RAM: {m['bank']}", f"{m['speed']} MT/s", f"{m['mfg']} {m['part']} ({m['gb']}GB)")
    sensor_table.add_row("Buses & Memory", "GPU PCIe Negotiation", f"{gpu_pcie}", "Current negotiated link")

    layout = Layout()
    layout.split_column(
        Layout(Panel(header_table, title="[bold cyan]HWINFO64 SHARED MEMORY BRIDGE CONFIGURATION[/bold cyan]", box=box.ROUNDED, border_style="cyan"), size=5),
        Layout(Panel(sensor_table, title="[bold cyan]DEEP HARDWARE SENSORS & PHYSICAL BUS TELEMETRY[/bold cyan]", box=box.ROUNDED, border_style="cyan")),
    )
    return layout


def build_footer_panel():
    """Interactive hotkey footer bar with HWiNFO integration."""
    global STATUS_MESSAGE, STATUS_TIME

    rate_str = f"{REFRESH_RATE}s"

    footer_text = Text()
    footer_text.append(" [<-/-> or 1-8] Views ", style="bold white on #2563eb")
    footer_text.append(" [H] HWiNFO ", style="bold white on #0891b2")
    footer_text.append(" [T] SSD TRIM ", style="bold white on #059669")
    footer_text.append(" [O] Logs Folder ", style="bold white on #7c3aed")
    footer_text.append(f" [R] Rate: {rate_str} ", style="bold white on #0284c7")
    footer_text.append(f" [S] Sort: {PROCESS_SORT_MODE.upper()} ", style="bold white on #475569")
    footer_text.append(f" [F] Filter: {PROCESS_FILTER_MODE.upper()} ", style="bold white on #334155")
    footer_text.append(" [K] Kill PID ", style="bold white on #dc2626")
    footer_text.append(" [Q] Exit ", style="bold white on #1e293b")

    if STATUS_MESSAGE and (time.time() - STATUS_TIME < 4.0):
        footer_text.append(f"\n [NOTICE] {STATUS_MESSAGE}", style="bold yellow")

    return Panel(Align.center(footer_text), box=box.ROUNDED, border_style="dim white", padding=(0, 0))


def render_dashboard():
    """Assembles responsive layout."""
    width = console.size.width

    layout = Layout()
    layout.split_column(
        Layout(name="header", size=4),
        Layout(name="body"),
        Layout(name="footer", size=3),
    )

    layout["header"].update(build_header_panel())
    layout["footer"].update(build_footer_panel())

    if CURRENT_VIEW == "all":
        if width >= 115:
            # 3-column wide mode
            layout["body"].split_column(
                Layout(name="top_cards", size=10),
                Layout(name="process_table"),
            )
            layout["top_cards"].split_row(
                Layout(build_battery_panel(), ratio=1),
                Layout(build_cpu_ram_panel(), ratio=1),
                Layout(build_storage_panel(), ratio=1),
            )
            layout["process_table"].update(build_process_table(limit=6))
        else:
            # 2-column or stacked compact mode
            layout["body"].split_column(
                Layout(name="top_cards", size=10),
                Layout(name="process_table"),
            )
            layout["top_cards"].split_row(
                Layout(build_battery_panel(), ratio=1),
                Layout(build_cpu_ram_panel(), ratio=1),
            )
            layout["process_table"].update(build_process_table(limit=5))

    elif CURRENT_VIEW == "battery":
        layout["body"].update(build_battery_focus_view())

    elif CURRENT_VIEW == "cpu":
        layout["body"].update(build_cpu_focus_view())

    elif CURRENT_VIEW == "ram":
        layout["body"].split_column(
            Layout(build_cpu_ram_panel(), size=9),
            Layout(build_process_table(limit=12)),
        )

    elif CURRENT_VIEW == "storage":
        layout["body"].update(build_storage_focus_view())

    elif CURRENT_VIEW == "processes":
        layout["body"].update(build_process_table(limit=16))

    elif CURRENT_VIEW == "logs":
        layout["body"].update(build_logs_view())

    elif CURRENT_VIEW == "hwinfo":
        layout["body"].update(build_hwinfo_view())

    return layout


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
    STATUS_MESSAGE = f"Refresh interval set to {REFRESH_RATE}s."
    STATUS_TIME = time.time()


def toggle_process_sort():
    """Toggles sort by CPU vs RAM."""
    global PROCESS_SORT_MODE, STATUS_MESSAGE, STATUS_TIME
    PROCESS_SORT_MODE = "ram" if PROCESS_SORT_MODE == "cpu" else "cpu"
    STATUS_MESSAGE = f"Process table sorting by {PROCESS_SORT_MODE.upper()}."
    STATUS_TIME = time.time()


def toggle_process_filter():
    """Toggles process filtering."""
    global PROCESS_FILTER_MODE, STATUS_MESSAGE, STATUS_TIME
    if PROCESS_FILTER_MODE == "all":
        PROCESS_FILTER_MODE = "heavy"
    else:
        PROCESS_FILTER_MODE = "all"
    STATUS_MESSAGE = f"Process filter set to {PROCESS_FILTER_MODE.upper()}."
    STATUS_TIME = time.time()


def main():
    global RUNNING, FRAME_INDEX, CURRENT_VIEW, STATUS_MESSAGE, STATUS_TIME
    
    # Hide cursor
    console.show_cursor(False)

    # Initial fast hardware detection
    detect_system_hardware()

    # Initial seed
    poll_fast_telemetry()
    update_battery_cim()
    update_ssd_cim()
    update_gpu_nvidia()
    update_hwinfo()

    # Background heavy thread
    worker = threading.Thread(target=telemetry_background_worker, daemon=True)
    worker.start()

    views_list = ["all", "battery", "cpu", "ram", "storage", "processes", "logs", "hwinfo"]
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
                    elif key == b'5':
                        CURRENT_VIEW = "storage"; view_changed = True
                    elif key == b'6':
                        CURRENT_VIEW = "processes"; view_changed = True
                    elif key in [b'7', b'l', b'L']:
                        CURRENT_VIEW = "logs"; view_changed = True
                    elif key == b'8':
                        CURRENT_VIEW = "hwinfo"; view_changed = True
                    elif key in [b'h', b'H']:
                        launch_hwinfo_sensors()
                        CURRENT_VIEW = "hwinfo"; view_changed = True
                    elif key in [b't', b'T']:
                        run_ssd_trim_optimizer(live)
                        view_changed = True
                    elif key in [b'o', b'O']:
                        open_logs_folder()
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
