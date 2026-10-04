#!/usr/bin/env python3
"""
ubat - Web Dashboard & Telemetry API Server
===========================================
Lightweight zero-dependency HTTP server delivering real-time laptop
hardware telemetry, process management endpoints, and power profiling
to the modern HTML/JS/CSS web dashboard.
"""

import os
import sys
import time
import json
import socket
import threading
import subprocess
import psutil
from http.server import HTTPServer, SimpleHTTPRequestHandler

PORT = 5050
HOST = "127.0.0.1"
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Cached Hardware Info
HARDWARE_INFO = {
    "manufacturer": "HP",
    "model": "OMEN Gaming Laptop 16-am0xxx",
    "cpu_name": "Intel(R) Core(TM) i7-14650HX",
    "cpu_cores": psutil.cpu_count(logical=True) or 16,
    "total_ram_gb": round(psutil.virtual_memory().total / (1024**3), 1),
}

# Disk delta tracking
LAST_DISK_TIME = 0.0
LAST_DISK_READ = 0
LAST_DISK_WRITE = 0
CACHED_DISK_R_MBS = 0.0
CACHED_DISK_W_MBS = 0.0

# GPU Telemetry Cache
CACHED_GPU = {
    "name": "NVIDIA GeForce RTX 5050 Laptop GPU",
    "util": 0,
    "temp": 43,
    "power": 18.2,
    "updated_at": 0.0
}


def detect_system():
    """Detects system model and CPU."""
    global HARDWARE_INFO
    try:
        cmd = 'powershell.exe -NoProfile -Command "Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model | ConvertTo-Json -Compress"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2).strip()
        data = json.loads(out)
        HARDWARE_INFO["manufacturer"] = data.get("Manufacturer", "HP").strip()
        HARDWARE_INFO["model"] = data.get("Model", "OMEN Laptop").strip()
    except Exception:
        pass

    try:
        cmd = 'powershell.exe -NoProfile -Command "Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2).strip()
        if out:
            HARDWARE_INFO["cpu_name"] = out.strip()
    except Exception:
        pass


def poll_gpu():
    """Queries nvidia-smi with a 1.5s cache."""
    global CACHED_GPU
    now = time.time()
    if now - CACHED_GPU["updated_at"] < 1.5:
        return CACHED_GPU
    try:
        out = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=name,utilization.gpu,temperature.gpu,power.draw", "--format=csv,noheader,nounits"],
            text=True, timeout=1.5
        ).strip()
        parts = [p.strip() for p in out.split(",")]
        if len(parts) >= 4:
            CACHED_GPU["name"] = parts[0]
            CACHED_GPU["util"] = int(parts[1])
            CACHED_GPU["temp"] = int(parts[2])
            CACHED_GPU["power"] = float(parts[3])
            CACHED_GPU["updated_at"] = now
    except Exception:
        pass
    return CACHED_GPU


# Cached CIM Battery Telemetry
CACHED_BATTERY_CIM = {
    "full_mwh": 80122,
    "remaining_mwh": 65000,
    "wattage": 0.0,
}
LAST_BATTERY_CIM_FETCH = 0.0


def get_battery_telemetry():
    """Compiles complete battery status and ACPI health telemetry with intelligent caching."""
    global CACHED_BATTERY_CIM, LAST_BATTERY_CIM_FETCH
    batt = psutil.sensors_battery()
    pct = batt.percent if batt else 80
    plugged = batt.power_plugged if batt else True
    secsleft = batt.secsleft if batt else -2

    # Default design & full capacity
    design_mwh = 83028
    full_mwh = CACHED_BATTERY_CIM["full_mwh"]
    remaining_mwh = int(round(full_mwh * (pct / 100.0)))
    wattage = CACHED_BATTERY_CIM["wattage"]

    now = time.time()
    if now - LAST_BATTERY_CIM_FETCH > 15.0:
        LAST_BATTERY_CIM_FETCH = now
        try:
            cmd = 'powershell.exe -NoProfile -Command "$f = (Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue).FullChargedCapacity; $s = (Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue); [PSCustomObject]@{ Full = $f; Rem = $s.RemainingCapacity; Rate = $s.DischargeRate } | ConvertTo-Json -Compress"'
            out = subprocess.check_output(cmd, shell=True, text=True, timeout=2).strip()
            data = json.loads(out)
            if data.get("Full"):
                full_mwh = int(data["Full"])
                CACHED_BATTERY_CIM["full_mwh"] = full_mwh
            if data.get("Rem"):
                remaining_mwh = int(data["Rem"])
                CACHED_BATTERY_CIM["remaining_mwh"] = remaining_mwh
            if data.get("Rate"):
                wattage = round(abs(int(data["Rate"])) / 1000.0, 2)
                CACHED_BATTERY_CIM["wattage"] = wattage
        except Exception:
            pass

    wear_pct = max(0.0, round((1.0 - (full_mwh / design_mwh)) * 100.0, 1)) if design_mwh > 0 else 3.5
    grade = "GRADE S (Pristine)" if wear_pct < 2.0 else "GRADE A (Very Good)" if wear_pct < 10.0 else "GRADE B (Good)"

    secsleft_str = "AC Powered (Protected)" if plugged else f"{int(secsleft // 3600)}h {int((secsleft % 3600) // 60):02d}m" if secsleft > 0 else "Calculating..."

    return {
        "pct": pct,
        "plugged": plugged,
        "wattage": wattage,
        "secsleft": secsleft,
        "secsleft_str": secsleft_str,
        "full_mwh": full_mwh,
        "design_mwh": design_mwh,
        "remaining_mwh": remaining_mwh,
        "wear_pct": wear_pct,
        "health_grade": grade,
    }


def get_disk_telemetry():
    """Computes instantaneous disk read/write throughput in MB/s."""
    global LAST_DISK_TIME, LAST_DISK_READ, LAST_DISK_WRITE, CACHED_DISK_R_MBS, CACHED_DISK_W_MBS
    now = time.time()
    disk_io = psutil.disk_io_counters()
    if disk_io:
        if LAST_DISK_TIME > 0:
            dt = now - LAST_DISK_TIME
            if dt > 0.4:
                r_bytes = disk_io.read_bytes - LAST_DISK_READ
                w_bytes = disk_io.write_bytes - LAST_DISK_WRITE
                CACHED_DISK_R_MBS = round((r_bytes / (1024 * 1024)) / dt, 1)
                CACHED_DISK_W_MBS = round((w_bytes / (1024 * 1024)) / dt, 1)
                LAST_DISK_READ = disk_io.read_bytes
                LAST_DISK_WRITE = disk_io.write_bytes
                LAST_DISK_TIME = now
        else:
            LAST_DISK_READ = disk_io.read_bytes
            LAST_DISK_WRITE = disk_io.write_bytes
            LAST_DISK_TIME = now

    return {
        "read_mbs": CACHED_DISK_R_MBS,
        "write_mbs": CACHED_DISK_W_MBS
    }


def get_top_processes(limit=25):
    """Gathers top active processes sorted by CPU and memory."""
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
    procs.sort(key=lambda x: (x['cpu'], x['mem_mb']), reverse=True)
    return procs[:limit]


class UbatRequestHandler(SimpleHTTPRequestHandler):
    """Custom HTTP handler serving dashboard and JSON telemetry endpoints."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BASE_DIR, **kwargs)

    def do_GET(self):
        if self.path == '/api/telemetry':
            self.handle_telemetry()
        else:
            super().do_GET()

    def do_POST(self):
        if self.path == '/api/kill':
            self.handle_kill_process()
        elif self.path == '/api/power-profile':
            self.handle_power_profile()
        else:
            self.send_error(404, "Endpoint not found")

    def handle_telemetry(self):
        vmem = psutil.virtual_memory()
        telemetry_payload = {
            "system": HARDWARE_INFO,
            "battery": get_battery_telemetry(),
            "cpu": {
                "pct": psutil.cpu_percent(interval=None),
            },
            "ram": {
                "pct": vmem.percent,
                "used_gb": round(vmem.used / (1024**3), 1),
                "total_gb": round(vmem.total / (1024**3), 1),
            },
            "gpu": poll_gpu(),
            "disk": get_disk_telemetry(),
            "processes": get_top_processes(30),
            "timestamp": time.time(),
        }

        data = json.dumps(telemetry_payload).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        origin = self.headers.get('Origin', '')
        allowed_origin = origin if origin in ['http://127.0.0.1:5050', 'http://localhost:5050'] else 'http://127.0.0.1:5050'
        self.send_header('Access-Control-Allow-Origin', allowed_origin)
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.end_headers()
        self.wfile.write(data)

    def handle_kill_process(self):
        try:
            origin = self.headers.get('Origin', '')
            if origin and origin not in ['http://127.0.0.1:5050', 'http://localhost:5050']:
                self.send_response(403)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"success": false, "error": "Cross-origin requests forbidden"}')
                return

            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            payload = json.loads(post_data.decode('utf-8'))
            pid = int(payload.get('pid'))

            proc = psutil.Process(pid)
            name = proc.name()
            proc.terminate()

            response = json.dumps({"success": True, "pid": pid, "name": name}).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', 'http://127.0.0.1:5050')
            self.end_headers()
            self.wfile.write(response)
        except Exception as e:
            err_resp = json.dumps({"success": False, "error": str(e)}).encode('utf-8')
            self.send_response(400)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(err_resp)

    def handle_power_profile(self):
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            payload = json.loads(post_data.decode('utf-8'))
            profile = payload.get('profile', 'balanced')

            # Power schemes GUIDs
            guids = {
                "balanced": "381b4222-f694-41f0-9685-ff5bb260df2e",
                "eco": "a1841308-3541-4fab-bc81-f71556f20b4a",
                "performance": "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c",
                "gaming": "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
            }
            target_guid = guids.get(profile, guids["balanced"])
            subprocess.run(["powercfg", "/setactive", target_guid], capture_output=True)

            response = json.dumps({"success": True, "profile": profile}).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(response)
        except Exception as e:
            err_resp = json.dumps({"success": False, "error": str(e)}).encode('utf-8')
            self.send_response(400)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(err_resp)


def check_port_open(port):
    """Checks if a local port is already in use."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex((HOST, port)) != 0


def main():
    detect_system()
    port = PORT
    if not check_port_open(port):
        port = 5051

    server = HTTPServer((HOST, port), UbatRequestHandler)
    url = f"http://localhost:{port}"
    print(f"\n=======================================================")
    print(f"  UBAT PRO - WEB TELEMETRY DASHBOARD SERVER ONLINE")
    print(f"=======================================================")
    print(f" Dashboard URL : {url}")
    print(f" Static Files  : {BASE_DIR}")
    print(f" Hardware      : {HARDWARE_INFO['manufacturer']} {HARDWARE_INFO['model']}")
    print(f" Status        : Press Ctrl+C in this terminal to stop.")
    print(f"=======================================================\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping UBAT Web Server...")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
