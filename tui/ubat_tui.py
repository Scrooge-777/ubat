#!/usr/bin/env python3
"""
ubat - Universal Battery & Hardware Telemetry Terminal UI (Rich Edition)
=========================================================================
High-performance terminal dashboard with smooth ANSI animations,
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

# Global state
RUNNING = True
CURRENT_VIEW = "all"  # 'all', 'battery', 'cpu', 'ram', 'gpu_ssd', 'processes'
STATUS_MESSAGE = ""
STATUS_TIME = 0

# Animation spinners
SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
PULSE_FRAMES = ["●", "◐", "◓", "◑", "◒"]
FRAME_INDEX = 0

# Hardware Profile Cache
HARDWARE_INFO = {
    "manufacturer": "Universal",
    "model": "Laptop",
    "cpu_name": "Multi-Core Processor",
    "cpu_cores": psutil.cpu_count(logical=True) or 8,
    "total_ram_gb": round(psutil.virtual_memory().total / (1024**3), 1),
}

# Real-time Telemetry Cache
TELEMETRY = {
    "battery_pct": 0,
    "battery_plugged": True,
    "battery_secsleft": -1,
    "battery_wattage": 0.0,
    "battery_mwh_remaining": 0,
    "battery_mwh_full": 80122,
    "battery_mwh_design": 83028,
    "battery_wear_pct": 3.5,
    "battery_health_grade": "A (Very Good)",
    "cpu_pct": 0.0,
    "cpu_per_core": [],
    "ram_pct": 0.0,
    "ram_used_gb": 0.0,
    "gpu_name": "Detecting...",
    "gpu_util": 0,
    "gpu_temp": 0,
    "gpu_power": 0.0,
    "disk_read_mbs": 0.0,
    "disk_write_mbs": 0.0,
    "disk_active_pct": 0.0,
    "processes": [],
    "last_disk_read": 0,
    "last_disk_write": 0,
    "last_disk_time": 0,
}


def detect_system_hardware():
    """Detects laptop model, manufacturer, and CPU name."""
    global HARDWARE_INFO
    try:
        cmd = 'powershell.exe -NoProfile -Command "Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model | ConvertTo-Json -Compress"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=3).strip()
        import json
        data = json.loads(out)
        HARDWARE_INFO["manufacturer"] = data.get("Manufacturer", "HP").strip()
        HARDWARE_INFO["model"] = data.get("Model", "OMEN Laptop").strip()
    except Exception:
        pass

    try:
        cmd = 'powershell.exe -NoProfile -Command "Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=3).strip()
        if out:
            HARDWARE_INFO["cpu_name"] = out
    except Exception:
        pass


def update_battery_cim():
    """Fetches deep battery statistics from Windows ACPI / CIM."""
    global TELEMETRY
    try:
        cmd = 'powershell.exe -NoProfile -Command "$f = (Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue).FullChargedCapacity; $s = (Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue); [PSCustomObject]@{ FullMwh = $f; RemainingMwh = $s.RemainingCapacity; RateMw = $s.DischargeRate } | ConvertTo-Json -Compress"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2).strip()
        import json
        data = json.loads(out)
        if data.get("FullMwh"):
            TELEMETRY["battery_mwh_full"] = int(data["FullMwh"])
        if data.get("RemainingMwh"):
            TELEMETRY["battery_mwh_remaining"] = int(data["RemainingMwh"])
        if data.get("RateMw"):
            TELEMETRY["battery_wattage"] = round(abs(int(data["RateMw"])) / 1000.0, 2)
        
        # Calculate wear
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
            text=True, timeout=2
        ).strip()
        parts = [p.strip() for p in out.split(",")]
        if len(parts) >= 4:
            TELEMETRY["gpu_name"] = parts[0]
            TELEMETRY["gpu_util"] = int(parts[1])
            TELEMETRY["gpu_temp"] = int(parts[2])
            TELEMETRY["gpu_power"] = float(parts[3])
    except Exception:
        TELEMETRY["gpu_name"] = "Integrated / Sleeping (dGPU Off)"
        TELEMETRY["gpu_util"] = 0
        TELEMETRY["gpu_temp"] = 0
        TELEMETRY["gpu_power"] = 0.0


def telemetry_background_worker():
    """Background worker thread for periodic heavy telemetry (GPU, CIM)."""
    global RUNNING
    counter = 0
    while RUNNING:
        try:
            if counter % 3 == 0:
                update_battery_cim()
            if counter % 2 == 0:
                update_gpu_nvidia()
        except Exception:
            pass
        counter += 1
        time.sleep(1.0)


def poll_fast_telemetry():
    """Polls lightweight, instantaneous metrics (CPU, RAM, Disk, Battery)."""
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

    # Disk MB/s
    now = time.time()
    disk_io = psutil.disk_io_counters()
    if disk_io and TELEMETRY["last_disk_time"] > 0:
        dt = now - TELEMETRY["last_disk_time"]
        if dt > 0:
            r_bytes = disk_io.read_bytes - TELEMETRY["last_disk_read"]
            w_bytes = disk_io.write_bytes - TELEMETRY["last_disk_write"]
            TELEMETRY["disk_read_mbs"] = round((r_bytes / (1024 * 1024)) / dt, 1)
            TELEMETRY["disk_write_mbs"] = round((w_bytes / (1024 * 1024)) / dt, 1)
    if disk_io:
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
                procs.append({
                    'pid': info['pid'],
                    'name': info['name'],
                    'cpu': cpu_p,
                    'mem_mb': mem_mb,
                })
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
        # Sort by CPU then RAM
        procs.sort(key=lambda x: (x['cpu'], x['mem_mb']), reverse=True)
        TELEMETRY["processes"] = procs[:12]
    except Exception:
        pass


def make_progress_bar(pct, width=20, fill_char="█", empty_char="░", color="green"):
    """Generates an ANSI/Rich styled progress bar."""
    pct = max(0.0, min(100.0, pct))
    filled_len = int(round(width * pct / 100.0))
    bar = fill_char * filled_len + empty_char * (width - filled_len)
    return f"[{color}]{bar}[/{color}] [bold]{pct:.1f}%[/bold]"


def format_secs(secs):
    """Formats seconds into human readable duration."""
    if secs < 0:
        return "Calculating / Unlimited"
    hrs = int(secs // 3600)
    mins = int((secs % 3600) // 60)
    return f"{hrs}h {mins:02d}m"


def build_header_panel():
    """Creates the glowing cyberpunk master header banner."""
    global FRAME_INDEX
    spinner = SPINNER_FRAMES[FRAME_INDEX % len(SPINNER_FRAMES)]
    pulse = PULSE_FRAMES[FRAME_INDEX % len(PULSE_FRAMES)]

    mfg = HARDWARE_INFO["manufacturer"].upper()
    model = HARDWARE_INFO["model"].upper()
    cpu = HARDWARE_INFO["cpu_name"]

    title_text = Text()
    title_text.append(f" {spinner} ", style="bold cyan")
    title_text.append("UBAT UNIVERSAL POWER & HARDWARE TELEMETRY ENGINE", style="bold white on #1a1a2e")
    title_text.append(f" {pulse}\n", style="bold magenta")
    title_text.append(f" SYSTEM: ", style="bold cyan")
    title_text.append(f"{mfg} {model}", style="bold yellow")
    title_text.append(f"  |  CPU: ", style="bold cyan")
    title_text.append(f"{cpu}", style="bold green")
    title_text.append(f"  |  STATUS: ", style="bold cyan")
    title_text.append("ONLINE (ACTIVE)", style="bold #00ff88")

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
    wear = TELEMETRY["battery_wear_pct"]
    grade = TELEMETRY["battery_health_grade"]
    secs = TELEMETRY["battery_secsleft"]

    # Color grading
    batt_color = "green" if pct >= 60 else "yellow" if pct >= 30 else "red"

    table = Table(box=None, expand=True, show_header=False, padding=(0, 1))
    table.add_column("Key", style="bold cyan", width=18)
    table.add_column("Value", style="bold white")

    power_src = "[bold #00ff88]⚡ AC ADAPTER CONNECTED[/bold #00ff88]" if plugged else "[bold yellow]🔋 ON BATTERY POWER[/bold yellow]"
    table.add_row("Power Source", power_src)
    table.add_row("Charge Level", make_progress_bar(pct, width=22, color=batt_color))
    table.add_row("Health Grade", f"[bold green]{grade}[/bold green] (Wear: [bold yellow]{wear}%[/bold yellow])")
    table.add_row("Usable Capacity", f"{full_mwh:,} mWh [dim](Design: {design_mwh:,} mWh)[/dim]")
    
    rate_str = f"{wattage:.2f} W" if wattage > 0 else "0.00 W (Full / Idle)"
    table.add_row("Charge/Drain", f"[bold magenta]{rate_str}[/bold magenta]")
    table.add_row("Estimated Time", format_secs(secs) if not plugged else "Plugged In (Protected)")

    return Panel(table, title="[bold cyan]🔋 Battery & Power Health[/bold cyan]", border_style="cyan", box=box.ROUNDED)


def build_cpu_ram_panel():
    """Renders CPU and RAM real-time performance and core metrics."""
    cpu_pct = TELEMETRY["cpu_pct"]
    ram_pct = TELEMETRY["ram_pct"]
    ram_used = TELEMETRY["ram_used_gb"]
    ram_total = HARDWARE_INFO["total_ram_gb"]

    cpu_color = "green" if cpu_pct < 50 else "yellow" if cpu_pct < 80 else "red"
    ram_color = "green" if ram_pct < 65 else "yellow" if ram_pct < 85 else "red"

    table = Table(box=None, expand=True, show_header=False, padding=(0, 1))
    table.add_column("Metric", style="bold cyan", width=14)
    table.add_column("Status", style="bold white")

    table.add_row("CPU Load", make_progress_bar(cpu_pct, width=18, color=cpu_color))
    table.add_row("RAM Usage", make_progress_bar(ram_pct, width=18, color=ram_color))
    table.add_row("RAM Volume", f"[bold white]{ram_used:.1f} GB[/bold white] / [dim]{ram_total:.1f} GB[/dim]")
    
    # Per core mini visualizer
    cores = TELEMETRY["cpu_per_core"]
    if cores:
        core_sparks = ""
        for c in cores[:16]:
            char = " " if c < 15 else "▂" if c < 35 else "▃" if c < 55 else "▅" if c < 75 else "█"
            col = "green" if c < 50 else "yellow" if c < 80 else "red"
            core_sparks += f"[{col}]{char}[/{col}]"
        table.add_row("Core Visualizer", f"{core_sparks} [dim]({len(cores)} Cores)[/dim]")

    return Panel(table, title="[bold cyan]⚡ CPU & Memory Hub[/bold cyan]", border_style="cyan", box=box.ROUNDED)


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

    table.add_row("GPU Model", f"[bold yellow]{gpu_name}[/bold yellow]")
    gpu_status = f"[bold green]{gpu_util}% Load[/bold green] | [bold yellow]{gpu_temp}°C[/bold yellow] | [bold magenta]{gpu_power:.1f}W[/bold magenta]"
    table.add_row("GPU Telemetry", gpu_status)
    table.add_row("NVMe Read", f"[bold green]{read_mb:.1f} MB/s[/bold green] [dim]throughput[/dim]")
    table.add_row("NVMe Write", f"[bold cyan]{write_mb:.1f} MB/s[/bold cyan] [dim]throughput[/dim]")

    return Panel(table, title="[bold cyan]🎮 GPU & NVMe Storage Telemetry[/bold cyan]", border_style="cyan", box=box.ROUNDED)


def build_process_table(limit=7):
    """Renders active processes in Task Manager style with resource columns."""
    table = Table(box=box.SIMPLE_HEAD, expand=True, header_style="bold cyan", padding=(0, 1))
    table.add_column("PID", justify="right", style="dim", width=7)
    table.add_column("Application Name", style="bold white", width=24)
    table.add_column("CPU %", justify="right", style="bold yellow", width=10)
    table.add_column("Memory (MB)", justify="right", style="bold green", width=14)

    procs = TELEMETRY["processes"][:limit]
    if not procs:
        table.add_row("-", "Scanning active processes...", "0.0%", "0.0 MB")
    else:
        for p in procs:
            table.add_row(
                str(p['pid']),
                p['name'][:24],
                f"{p['cpu']:.1f}%",
                f"{p['mem_mb']:.1f} MB",
            )

    return Panel(table, title="[bold cyan]📊 Top Resource Consuming Processes (Live Task Manager)[/bold cyan]", border_style="cyan", box=box.ROUNDED)


def build_footer_panel():
    """Generates the interactive command shortcut strip and status banner."""
    global STATUS_MESSAGE, STATUS_TIME

    footer_text = Text()
    # Hotkeys
    footer_text.append(" [1] All-in-One ", style="bold white on #2563eb")
    footer_text.append(" [2] Battery ", style="bold white on #1e293b")
    footer_text.append(" [3] CPU ", style="bold white on #1e293b")
    footer_text.append(" [4] RAM ", style="bold white on #1e293b")
    footer_text.append(" [5] GPU/SSD ", style="bold white on #1e293b")
    footer_text.append(" [6] Processes ", style="bold white on #1e293b")
    footer_text.append(" [K] Kill Process ", style="bold white on #dc2626")
    footer_text.append(" [W] Launch Web Dashboard ", style="bold white on #7c3aed")
    footer_text.append(" [Q] Quit ", style="bold white on #475569")

    if STATUS_MESSAGE and (time.time() - STATUS_TIME < 4.0):
        footer_text.append(f"\n 🔔 {STATUS_MESSAGE}", style="bold yellow")

    return Panel(Align.center(footer_text), box=box.ROUNDED, border_style="dim white", padding=(0, 0))


def render_dashboard():
    """Assembles all components into a coherent, responsive layout."""
    layout = Layout()
    layout.split_column(
        Layout(name="header", size=4),
        Layout(name="body"),
        Layout(name="footer", size=3),
    )

    layout["header"].update(build_header_panel())
    layout["footer"].update(build_footer_panel())

    if CURRENT_VIEW == "all":
        layout["body"].split_column(
            Layout(name="top_cards", size=9),
            Layout(name="process_table"),
        )
        layout["top_cards"].split_row(
            Layout(build_battery_panel(), ratio=1),
            Layout(build_cpu_ram_panel(), ratio=1),
            Layout(build_gpu_ssd_panel(), ratio=1),
        )
        layout["process_table"].update(build_process_table(limit=6))

    elif CURRENT_VIEW == "battery":
        layout["body"].update(build_battery_panel())

    elif CURRENT_VIEW == "cpu":
        layout["body"].update(build_cpu_ram_panel())

    elif CURRENT_VIEW == "gpu_ssd":
        layout["body"].update(build_gpu_ssd_panel())

    elif CURRENT_VIEW == "processes":
        layout["body"].update(build_process_table(limit=18))

    return layout


def handle_kill_process_dialog(live):
    """Prompts the user inside the terminal to enter a PID to kill."""
    global STATUS_MESSAGE, STATUS_TIME
    live.stop()
    console.print("\n[bold red]═══ KILL PROCESS MANAGER ═══[/bold red]")
    try:
        pid_str = console.input("[bold yellow]Enter Process ID (PID) to terminate (or Enter to cancel): [/bold yellow]").strip()
        if pid_str and pid_str.isdigit():
            target_pid = int(pid_str)
            p = psutil.Process(target_pid)
            name = p.name()
            confirm = console.input(f"[bold red]Are you sure you want to kill {name} (PID: {target_pid})? [y/N]: [/bold red]").strip().lower()
            if confirm == 'y':
                p.terminate()
                STATUS_MESSAGE = f"Successfully terminated {name} (PID: {target_pid})"
                STATUS_TIME = time.time()
            else:
                STATUS_MESSAGE = "Process kill cancelled."
                STATUS_TIME = time.time()
    except Exception as e:
        STATUS_MESSAGE = f"Failed to kill PID: {e}"
        STATUS_TIME = time.time()
    live.start()


def launch_web_ui_background():
    """Launches the modern web server and opens the browser."""
    global STATUS_MESSAGE, STATUS_TIME
    try:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        web_server_path = os.path.join(os.path.dirname(script_dir), "web", "server.py")
        subprocess.Popen([sys.executable, web_server_path], creationflags=subprocess.CREATE_NEW_CONSOLE if os.name == 'nt' else 0)
        import webbrowser
        webbrowser.open("http://localhost:5050")
        STATUS_MESSAGE = "Web Dashboard launched at http://localhost:5050"
        STATUS_TIME = time.time()
    except Exception as e:
        STATUS_MESSAGE = f"Could not launch Web UI: {e}"
        STATUS_TIME = time.time()


def main():
    global RUNNING, FRAME_INDEX, CURRENT_VIEW, STATUS_MESSAGE, STATUS_TIME
    
    # Hide terminal cursor if possible
    console.show_cursor(False)
    console.clear()

    # Hardware profile detection
    detect_system_hardware()

    # Initial telemetry seed
    poll_fast_telemetry()
    update_battery_cim()
    update_gpu_nvidia()

    # Start background telemetry thread
    worker = threading.Thread(target=telemetry_background_worker, daemon=True)
    worker.start()

    with Live(render_dashboard(), refresh_per_second=4, screen=True, console=console) as live:
        try:
            while RUNNING:
                FRAME_INDEX += 1
                poll_fast_telemetry()
                live.update(render_dashboard())

                # Check non-blocking keyboard input
                if msvcrt.kbhit():
                    key = msvcrt.getch()
                    # Handle special arrow keys or standard keys
                    if key in [b'q', b'Q', b'\x1b']:
                        RUNNING = False
                        break
                    elif key == b'1':
                        CURRENT_VIEW = "all"
                    elif key == b'2':
                        CURRENT_VIEW = "battery"
                    elif key == b'3':
                        CURRENT_VIEW = "cpu"
                    elif key == b'4':
                        CURRENT_VIEW = "cpu"
                    elif key == b'5':
                        CURRENT_VIEW = "gpu_ssd"
                    elif key == b'6':
                        CURRENT_VIEW = "processes"
                    elif key in [b'k', b'K']:
                        handle_kill_process_dialog(live)
                    elif key in [b'w', b'W']:
                        launch_web_ui_background()

                time.sleep(0.25)
        except KeyboardInterrupt:
            pass
        finally:
            RUNNING = False
            console.show_cursor(True)
            console.clear()
            console.print("[bold green]UBAT Telemetry Monitor closed cleanly. Have a great day![/bold green]\n")


if __name__ == "__main__":
    main()
