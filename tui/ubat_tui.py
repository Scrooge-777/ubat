#!/usr/bin/env python3
"""
ubat - Universal Battery & Hardware Telemetry Terminal Engine (Rich Edition)
=============================================================================
High-performance terminal dashboard with motionless ANSI updating,
real-time multi-core CPU, RAM, NVMe SSD, NVIDIA RTX GPU telemetry,
calibrated battery health algorithms, and interactive process management.
"""

import sys
import os
import time
import math
import msvcrt
import threading
import subprocess
import psutil

from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.layout import Layout
from rich.text import Text
from rich.live import Live
from rich.align import Align
from rich import box

# Console initialization
console = Console()

# Global State
RUNNING = True
CURRENT_VIEW = "all"  # 'all', 'battery', 'cpu', 'ram', 'gpu_ssd', 'processes'
REFRESH_RATES = [0.25, 0.5, 1.0, 2.0]
REFRESH_INDEX = 1     # Default 0.5s
REFRESH_RATE = REFRESH_RATES[REFRESH_INDEX]

PROCESS_SORT_MODE = "cpu"    # 'cpu' or 'ram'
PROCESS_FILTER_MODE = "all"  # 'all', 'nvidia', 'heavy'

POWER_PROFILES = [
    {"name": "UNBUNDLE (HP OMEN)", "guid": "21fcc937-6c5d-45d2-bb4b-1aa53670a42f"},
    {"name": "BALANCED (WINDOWS)", "guid": "381b4222-f694-41f0-9685-ff5bb260df2e"},
]
POWER_PROFILE_INDEX = 0

STATUS_MESSAGE = ""
STATUS_TIME = 0.0

# Animation frames
SPINNER_FRAMES = ["-", "\\", "|", "/"]
PULSE_FRAMES = ["[*]", "[+]", "[#]", "[+]"]
FRAME_INDEX = 0

# Hardware Profile Cache
HARDWARE_INFO = {
    "manufacturer": "HP",
    "model": "OMEN Gaming Laptop 16-am0xxx",
    "cpu_name": "Intel(R) Core(TM) i7-14650HX",
    "cpu_cores_logical": psutil.cpu_count(logical=True) or 16,
    "cpu_cores_physical": psutil.cpu_count(logical=False) or 8,
    "total_ram_gb": round(psutil.virtual_memory().total / (1024**3), 1),
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
        import json
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


def update_battery_cim():
    """Fetches deep battery statistics from Windows ACPI / CIM."""
    global TELEMETRY
    try:
        cmd = 'powershell.exe -NoProfile -Command "$f = (Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue).FullChargedCapacity; $s = (Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue); $c = (Get-CimInstance -Namespace root/wmi -ClassName BatteryCycleCount -ErrorAction SilentlyContinue).CycleCount; [PSCustomObject]@{ FullMwh = $f; RemainingMwh = $s.RemainingCapacity; RateMw = $s.DischargeRate; Cycles = $c; Voltage = $s.Voltage } | ConvertTo-Json -Compress"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2).strip()
        import json
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


def update_gpu_nvidia():
    """Queries NVIDIA GPU metrics via nvidia-smi."""
    global TELEMETRY
    try:
        out = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=name,utilization.gpu,temperature.gpu,power.draw", "--format=csv,noheader,nounits"],
            text=True, timeout=1.5
        ).strip()
        parts = [p.strip() for p in out.split(",")]
        if len(parts) >= 4:
            TELEMETRY["gpu_name"] = parts[0]
            TELEMETRY["gpu_util"] = int(parts[1])
            TELEMETRY["gpu_temp"] = int(parts[2])
            TELEMETRY["gpu_power"] = float(parts[3])
    except Exception:
        TELEMETRY["gpu_name"] = "NVIDIA dGPU (Dynamic Sleep)"
        TELEMETRY["gpu_util"] = 0
        TELEMETRY["gpu_temp"] = 0
        TELEMETRY["gpu_power"] = 0.0


def telemetry_background_worker():
    """Background worker thread for periodic heavy telemetry (GPU, ACPI)."""
    global RUNNING
    counter = 0
    while RUNNING:
        try:
            if counter % 4 == 0:
                update_battery_cim()
            if counter % 2 == 0:
                update_gpu_nvidia()
        except Exception:
            pass
        counter += 1
        time.sleep(1.0)


def poll_fast_telemetry():
    """Polls instantaneous metrics (CPU, RAM, Disk, Processes)."""
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

    # Top Processes
    try:
        procs = []
        for p in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_info']):
            try:
                info = p.info
                mem_mb = round((info['memory_info'].rss or 0) / (1024 * 1024), 1)
                cpu_p = info['cpu_percent'] or 0.0
                name = info['name']

                # Filtering
                if PROCESS_FILTER_MODE == "nvidia" and not ("nv" in name.lower() or "nvidia" in name.lower()):
                    continue
                elif PROCESS_FILTER_MODE == "heavy" and (cpu_p < 2.0 and mem_mb < 300):
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


def make_progress_bar(pct, width=20, fill_char="=", empty_char="-", color="green"):
    """Generates an ANSI/Rich styled progress bar."""
    pct = max(0.0, min(100.0, pct))
    filled_len = int(round(width * pct / 100.0))
    bar = fill_char * filled_len + empty_char * (width - filled_len)
    return f"[{color}][{bar}][/{color}] [bold]{pct:.1f}%[/bold]"


def format_secs(secs):
    """Formats seconds into human readable duration."""
    if secs < 0:
        return "AC Powered (Protected)"
    hrs = int(secs // 3600)
    mins = int((secs % 3600) // 60)
    return f"{hrs}h {mins:02d}m Remaining"


def build_header_panel():
    """Creates master hardware banner."""
    global FRAME_INDEX
    spinner = SPINNER_FRAMES[FRAME_INDEX % len(SPINNER_FRAMES)]
    pulse = PULSE_FRAMES[FRAME_INDEX % len(PULSE_FRAMES)]

    mfg = HARDWARE_INFO["manufacturer"].upper()
    model = HARDWARE_INFO["model"].upper()
    cpu = HARDWARE_INFO["cpu_name"]

    title_text = Text()
    title_text.append(f" {spinner} ", style="bold cyan")
    title_text.append("UBAT UNIVERSAL HARDWARE & BATTERY TELEMETRY ENGINE", style="bold white on #1e293b")
    title_text.append(f" {pulse}\n", style="bold cyan")
    title_text.append(f" SYSTEM: ", style="bold cyan")
    title_text.append(f"{mfg} {model}", style="bold yellow")
    title_text.append(f"  |  CPU: ", style="bold cyan")
    title_text.append(f"{cpu}", style="bold green")
    title_text.append(f"  |  MODE: ", style="bold cyan")
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
    cycles = TELEMETRY["battery_cycle_count"]
    voltage = TELEMETRY["battery_voltage_v"]

    batt_color = "green" if pct >= 60 else "yellow" if pct >= 30 else "red"

    table = Table(box=None, expand=True, show_header=False, padding=(0, 1))
    table.add_column("Key", style="bold cyan", width=17)
    table.add_column("Value", style="bold white")

    power_src = "[bold green][AC] ADAPTER CONNECTED[/bold green]" if plugged else "[bold yellow][BAT] ON BATTERY POWER[/bold yellow]"
    table.add_row("Power Source", power_src)
    table.add_row("Charge Level", make_progress_bar(pct, width=18, color=batt_color))
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

    cpu_color = "green" if cpu_pct < 50 else "yellow" if cpu_pct < 80 else "red"
    ram_color = "green" if ram_pct < 65 else "yellow" if ram_pct < 85 else "red"

    table = Table(box=None, expand=True, show_header=False, padding=(0, 1))
    table.add_column("Metric", style="bold cyan", width=14)
    table.add_column("Status", style="bold white")

    table.add_row("CPU Load", make_progress_bar(cpu_pct, width=16, color=cpu_color))
    table.add_row("RAM Usage", make_progress_bar(ram_pct, width=16, color=ram_color))
    table.add_row("Memory Vol", f"[bold white]{ram_used:.1f} GB[/bold white] / [dim]{ram_total:.1f} GB[/dim]")
    table.add_row("Free Memory", f"[bold green]{ram_avail:.1f} GB[/bold green] [dim]available[/dim]")
    
    # Per core visualizer
    cores = TELEMETRY["cpu_per_core"]
    if cores:
        core_sparks = ""
        for c in cores[:16]:
            char = " " if c < 15 else "_" if c < 35 else "=" if c < 65 else "#"
            col = "green" if c < 50 else "yellow" if c < 80 else "red"
            core_sparks += f"[{col}]{char}[/{col}]"
        table.add_row("Core Sparks", f"{core_sparks} [dim]({len(cores)} Cores)[/dim]")

    return Panel(table, title="[bold cyan]CPU & MEMORY HUB[/bold cyan]", border_style="cyan", box=box.ROUNDED)


def build_gpu_ssd_panel():
    """Renders NVIDIA GPU & NVMe SSD storage throughput."""
    gpu_name = TELEMETRY["gpu_name"]
    gpu_util = TELEMETRY["gpu_util"]
    gpu_temp = TELEMETRY["gpu_temp"]
    gpu_power = TELEMETRY["gpu_power"]
    read_mb = TELEMETRY["disk_read_mbs"]
    write_mb = TELEMETRY["disk_write_mbs"]

    table = Table(box=None, expand=True, show_header=False, padding=(0, 1))
    table.add_column("Device", style="bold cyan", width=14)
    table.add_column("Details", style="bold white")

    table.add_row("GPU Device", f"[bold yellow]{gpu_name[:24]}[/bold yellow]")
    gpu_status = f"[bold green]{gpu_util}%[/bold green] | [bold yellow]{gpu_temp} C[/bold yellow] | [bold magenta]{gpu_power:.1f}W[/bold magenta]"
    table.add_row("GPU Metrics", gpu_status)
    table.add_row("NVMe Read", f"[bold green]{read_mb:.1f} MB/s[/bold green]")
    table.add_row("NVMe Write", f"[bold cyan]{write_mb:.1f} MB/s[/bold cyan]")
    table.add_row("Total I/O", f"R: {TELEMETRY['disk_total_read_gb']:.1f}GB | W: {TELEMETRY['disk_total_write_gb']:.1f}GB")

    return Panel(table, title="[bold cyan]GPU & NVME STORAGE TELEMETRY[/bold cyan]", border_style="cyan", box=box.ROUNDED)


def build_process_table(limit=6):
    """Renders active processes in Task Manager style with resource columns and heatmap shading."""
    table = Table(box=box.SIMPLE_HEAD, expand=True, header_style="bold cyan", padding=(0, 1))
    table.add_column("PID", justify="right", style="dim", width=7)
    table.add_column("APPLICATION NAME", style="bold white", width=22)
    table.add_column("CPU %", justify="right", width=14)
    table.add_column("RAM (MB)", justify="right", width=14)
    table.add_column("POWER HEATMAP", justify="center", width=16)

    procs = TELEMETRY["processes"][:limit]
    if not procs:
        table.add_row("-", "Scanning active processes...", "0.0%", "0.0 MB", "[dim]--[/dim]")
    else:
        for p in procs:
            cpu_val = p['cpu']
            mem_val = p['mem_mb']

            # Task Manager style color heatmap
            if cpu_val >= 6.0:
                cpu_cell = f"[bold white on #b91c1c] {cpu_val:4.1f}% [/bold white on #b91c1c]"
            elif cpu_val >= 2.0:
                cpu_cell = f"[bold black on #f59e0b] {cpu_val:4.1f}% [/bold black on #f59e0b]"
            else:
                cpu_cell = f"[dim green]{cpu_val:4.1f}%[/dim green]"

            if mem_val >= 700.0:
                mem_cell = f"[bold white on #b91c1c] {mem_val:5.1f} MB [/bold white on #b91c1c]"
            elif mem_val >= 300.0:
                mem_cell = f"[bold black on #f59e0b] {mem_val:5.1f} MB [/bold black on #f59e0b]"
            else:
                mem_cell = f"[dim green]{mem_val:5.1f} MB[/dim green]"

            if cpu_val >= 6.0 or mem_val >= 700.0:
                impact_badge = "[bold white on #b91c1c] HIGH DRAIN [/bold white on #b91c1c]"
            elif cpu_val >= 2.0 or mem_val >= 300.0:
                impact_badge = "[bold black on #f59e0b] MODERATE [/bold black on #f59e0b]"
            else:
                impact_badge = "[dim green] LOW/IDLE  [/dim green]"

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

    # 4-hour target budget
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

    # Core grid
    core_table = Table(box=box.SIMPLE, expand=True)
    for col_idx in range(4):
        core_table.add_column(f"Core Group {col_idx+1}", style="bold white")

    rows = []
    chunk_size = 4
    for i in range(0, len(cores), chunk_size):
        chunk = cores[i:i+chunk_size]
        row_cells = []
        for idx, c in enumerate(chunk):
            col = "green" if c < 50 else "yellow" if c < 80 else "red"
            row_cells.append(f"T{i+idx:02d}: [{col}]{c:4.1f}%[/{col}]")
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


def build_footer_panel():
    """Interactive hotkey footer bar."""
    global STATUS_MESSAGE, STATUS_TIME

    active_p = POWER_PROFILES[POWER_PROFILE_INDEX]["name"]
    rate_str = f"{REFRESH_RATE}s"

    footer_text = Text()
    footer_text.append(" [<-/-> or 1-6] Switch Views ", style="bold white on #2563eb")
    footer_text.append(f" [P] Power: {active_p} ", style="bold white on #059669")
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
                Layout(build_gpu_ssd_panel(), ratio=1),
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

    elif CURRENT_VIEW == "gpu_ssd":
        layout["body"].split_column(
            Layout(build_gpu_ssd_panel(), size=9),
            Layout(build_process_table(limit=12)),
        )

    elif CURRENT_VIEW == "processes":
        layout["body"].update(build_process_table(limit=16))

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


def cycle_power_profile():
    """Switches active power scheme via powercfg."""
    global POWER_PROFILE_INDEX, STATUS_MESSAGE, STATUS_TIME
    POWER_PROFILE_INDEX = (POWER_PROFILE_INDEX + 1) % len(POWER_PROFILES)
    profile = POWER_PROFILES[POWER_PROFILE_INDEX]
    try:
        subprocess.run(["powercfg", "/setactive", profile["guid"]], capture_output=True)
        STATUS_MESSAGE = f"Power Profile switched to {profile['name']}."
        STATUS_TIME = time.time()
    except Exception as e:
        STATUS_MESSAGE = f"Could not switch power profile: {e}"
        STATUS_TIME = time.time()


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
        PROCESS_FILTER_MODE = "nvidia"
    elif PROCESS_FILTER_MODE == "nvidia":
        PROCESS_FILTER_MODE = "heavy"
    else:
        PROCESS_FILTER_MODE = "all"
    STATUS_MESSAGE = f"Process filter set to {PROCESS_FILTER_MODE.upper()}."
    STATUS_TIME = time.time()


def run_startup_scan():
    """Optional fast 0.6s progressive hardware scan animation."""
    console.clear()
    console.print("\n[bold cyan]UBAT HARDWARE TELEMETRY ENGINE INITIALIZING...[/bold cyan]")
    steps = [
        ("Probing ACPI Battery Controller & Wear Model...", 0.15),
        ("Sampling Multi-Core CPU Frequencies...", 0.15),
        ("Querying NVIDIA RTX Dedicated GPU Telemetry...", 0.15),
        ("Calibrating NVMe Storage IOPS & APST States...", 0.15),
    ]
    for text, delay in steps:
        time.sleep(delay)
        console.print(f"  [bold green][OK][/bold green] {text}")
    time.sleep(0.2)


def main():
    global RUNNING, FRAME_INDEX, CURRENT_VIEW, STATUS_MESSAGE, STATUS_TIME
    
    # Hide cursor
    console.show_cursor(False)

    # Initial fast scan
    detect_system_hardware()
    run_startup_scan()

    # Initial seed
    poll_fast_telemetry()
    update_battery_cim()
    update_gpu_nvidia()

    # Background heavy thread
    worker = threading.Thread(target=telemetry_background_worker, daemon=True)
    worker.start()

    views_list = ["all", "battery", "cpu", "ram", "gpu_ssd", "processes"]
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
                        CURRENT_VIEW = "gpu_ssd"; view_changed = True
                    elif key == b'6':
                        CURRENT_VIEW = "processes"; view_changed = True
                    elif key in [b'k', b'K']:
                        handle_kill_process_dialog(live)
                        view_changed = True
                    elif key in [b'p', b'P']:
                        cycle_power_profile()
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

                    # Render INSTANTLY on key press without waiting for cadence
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
            console.print("[bold green]UBAT Telemetry Monitor closed cleanly. Have a great day![/bold green]\n")


if __name__ == "__main__":
    main()
