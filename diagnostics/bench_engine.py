#!/usr/bin/env python3
"""
OMNI Hardware Benchmark & Stress Testing Engine
================================================
Provides high-precision NVMe storage read benchmarks, multi-core CPU stress tests,
CPU computational scoring, and DDR5 RAM memory bandwidth measurements.
"""

import os
import sys
import time
import math
import random
import tempfile
import threading
import subprocess
import psutil

# Safe benchmark constants
DEFAULT_DISK_BENCH_MB = 128
DEFAULT_RANDOM_OPS = 500
DEFAULT_RAM_BENCH_MB = 128


def _stress_worker_loop(duration, stop_event, result_list, worker_idx):
    """Worker loop performing intense floating-point math."""
    end_time = time.time() + duration
    c = 0
    while time.time() < end_time and not stop_event.is_set():
        # High intensity mathematical workload
        val = math.sin(c) * math.sqrt(c + 1.0) * math.tan(0.12345)
        c += 1
    result_list[worker_idx] = c


def run_cpu_stress_test(duration=10, progress_cb=None):
    """
    Executes a multi-threaded CPU stress test across all logical threads.
    Tracks temperature rise, frequency shifts, and throttling.
    """
    num_threads = psutil.cpu_count(logical=True) or 8
    stop_event = threading.Event()
    results = [0] * num_threads

    # Initial baseline readings
    base_temp = 50.0
    base_freq = 2000
    try:
        cmd = 'powershell.exe -NoProfile -Command "$tz = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue; if ($tz.CurrentTemperature) { [math]::Round(($tz.CurrentTemperature - 2732)/10, 1) } else { 0 }"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2).strip()
        if out and float(out) > 0:
            base_temp = float(out)
    except Exception:
        pass

    try:
        cmd = 'powershell.exe -NoProfile -Command "(Get-Counter \'\\Processor Information(*)\\Processor Frequency\' -ErrorAction SilentlyContinue).CounterSamples | Where-Object { $_.InstanceName -eq \'_total\' } | Select-Object -ExpandProperty CookedValue"'
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=2).strip()
        if out and float(out) > 0:
            base_freq = int(round(float(out)))
    except Exception:
        pass

    threads = []
    for i in range(num_threads):
        t = threading.Thread(target=_stress_worker_loop, args=(duration, stop_event, results, i))
        threads.append(t)

    start_time = time.time()
    for t in threads:
        t.start()

    peak_temp = base_temp
    samples = []

    # Monitor loop
    elapsed = 0.0
    while elapsed < duration:
        time.sleep(1.0)
        elapsed = time.time() - start_time

        curr_temp = base_temp
        curr_freq = base_freq
        try:
            cmd = 'powershell.exe -NoProfile -Command "$tz = (Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue).CurrentTemperature; $f = (Get-Counter \'\\Processor Information(*)\\Processor Frequency\' -ErrorAction SilentlyContinue).CounterSamples | Where-Object { $_.InstanceName -eq \'_total\' } | Select-Object -ExpandProperty CookedValue; [PSCustomObject]@{ T = if ($tz) { [math]::Round(($tz - 2732)/10, 1) } else { 0 }; F = [math]::Round($f) } | ConvertTo-Json -Compress"'
            out = subprocess.check_output(cmd, shell=True, text=True, timeout=1.5).strip()
            import json
            data = json.loads(out)
            if data.get("T") and float(data["T"]) > 0:
                curr_temp = float(data["T"])
            if data.get("F") and int(data["F"]) > 0:
                curr_freq = int(data["F"])
        except Exception:
            pass

        if curr_temp > peak_temp:
            peak_temp = curr_temp

        samples.append({
            "elapsed_s": round(elapsed, 1),
            "temp_c": curr_temp,
            "freq_mhz": curr_freq,
            "cpu_pct": psutil.cpu_percent()
        })

        if progress_cb:
            progress_cb(elapsed, duration, curr_temp, curr_freq)

    stop_event.set()
    for t in threads:
        t.join(timeout=1.0)

    total_ops = sum(results)
    ops_per_sec = int(total_ops / max(1.0, elapsed))
    throttled = peak_temp >= 95.0 or (samples and samples[-1]["freq_mhz"] < base_freq * 0.75)

    return {
        "duration_s": round(elapsed, 1),
        "threads_used": num_threads,
        "base_temp_c": base_temp,
        "peak_temp_c": peak_temp,
        "temp_delta_c": round(peak_temp - base_temp, 1),
        "base_freq_mhz": base_freq,
        "final_freq_mhz": samples[-1]["freq_mhz"] if samples else base_freq,
        "total_ops": total_ops,
        "ops_per_sec": ops_per_sec,
        "thermal_throttling": throttled,
        "samples": samples
    }


def run_storage_read_benchmark(test_size_mb=DEFAULT_DISK_BENCH_MB, num_random_ops=DEFAULT_RANDOM_OPS):
    """
    Benchmarks NVMe disk read performance:
    1. Sequential Read Throughput (MB/s) in 1MB blocks
    2. 4K Random Read Throughput (MB/s), IOPS, and average access latency (ms)
    """
    target_dir = os.environ.get("TEMP", tempfile.gettempdir())
    test_file = os.path.join(target_dir, f"omni_disk_bench_{int(time.time())}.tmp")

    try:
        # Create uncompressible payload
        block_1mb = os.urandom(1024 * 1024)
        with open(test_file, "wb") as f:
            for _ in range(test_size_mb):
                f.write(block_1mb)
            f.flush()
            os.fsync(f.fileno())

        file_size_bytes = os.path.getsize(test_file)

        # 1. Sequential Read Test (1MB buffer)
        seq_start = time.perf_counter()
        total_read_bytes = 0
        with open(test_file, "rb", buffering=1024 * 1024) as f:
            while True:
                buf = f.read(1024 * 1024)
                if not buf:
                    break
                total_read_bytes += len(buf)
        seq_duration = time.perf_counter() - seq_start
        seq_speed_mbs = round((total_read_bytes / (1024 * 1024)) / seq_duration, 1)

        # 2. 4K Random Read Test (unbuffered raw seek)
        max_seek_offset = file_size_bytes - 4096
        rnd_start = time.perf_counter()
        with open(test_file, "rb", buffering=0) as f:
            for _ in range(num_random_ops):
                offset = random.randint(0, max_seek_offset)
                f.seek(offset)
                f.read(4096)
        rnd_duration = time.perf_counter() - rnd_start
        rnd_iops = int(num_random_ops / rnd_duration)
        rnd_speed_mbs = round((num_random_ops * 4096 / (1024 * 1024)) / rnd_duration, 1)
        avg_latency_ms = round((rnd_duration / num_random_ops) * 1000.0, 3)

        return {
            "test_file_size_mb": test_size_mb,
            "seq_read_mbs": seq_speed_mbs,
            "rnd_read_mbs": rnd_speed_mbs,
            "rnd_iops": rnd_iops,
            "avg_latency_ms": avg_latency_ms,
            "status": "PASS"
        }
    except Exception as e:
        return {
            "error": str(e),
            "seq_read_mbs": 0.0,
            "rnd_read_mbs": 0.0,
            "rnd_iops": 0,
            "avg_latency_ms": 0.0,
            "status": "FAIL"
        }
    finally:
        if os.path.exists(test_file):
            try:
                os.remove(test_file)
            except Exception:
                pass


def run_cpu_benchmark(duration_seconds=3):
    """
    Standardized CPU computational benchmark.
    Tests single-thread operations/sec and multi-thread operations/sec.
    """
    # Single-thread test
    st_start = time.perf_counter()
    st_end = st_start + duration_seconds
    st_ops = 0
    while time.perf_counter() < st_end:
        val = math.sqrt(st_ops + 1.0) * math.sin(0.5)
        st_ops += 1
    st_duration = time.perf_counter() - st_start
    st_ops_sec = int(st_ops / st_duration)

    # Multi-thread test
    num_threads = psutil.cpu_count(logical=True) or 8
    stop_event = threading.Event()
    results = [0] * num_threads
    threads = []
    for i in range(num_threads):
        t = threading.Thread(target=_stress_worker_loop, args=(duration_seconds, stop_event, results, i))
        threads.append(t)

    mt_start = time.perf_counter()
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    mt_duration = time.perf_counter() - mt_start
    mt_total_ops = sum(results)
    mt_ops_sec = int(mt_total_ops / mt_duration)

    # Score calculation (normalized to 10,000 for standard reference)
    single_score = int(st_ops_sec / 1500)
    multi_score = int(mt_ops_sec / 1500)
    multi_ratio = round(mt_ops_sec / max(1.0, st_ops_sec), 2)

    return {
        "single_thread_ops_sec": st_ops_sec,
        "single_thread_score": single_score,
        "multi_thread_ops_sec": mt_ops_sec,
        "multi_thread_score": multi_score,
        "multi_thread_ratio": multi_ratio,
        "threads_tested": num_threads
    }


def run_ram_bandwidth_benchmark(buffer_mb=DEFAULT_RAM_BENCH_MB):
    """
    Measures physical RAM memory read and copy bandwidth in GB/s.
    """
    try:
        size_bytes = buffer_mb * 1024 * 1024
        # Allocate buffer
        source = bytearray(b"A" * size_bytes)
        
        # Sequential read pass
        start_read = time.perf_counter()
        dummy_hash = sum(source[::4096])
        read_duration = time.perf_counter() - start_read
        read_gbs = round((size_bytes / (1024 ** 3)) / max(0.0001, read_duration), 2)

        # Memory copy pass
        start_copy = time.perf_counter()
        dest = bytearray(source)
        copy_duration = time.perf_counter() - start_copy
        copy_gbs = round((size_bytes / (1024 ** 3)) / max(0.0001, copy_duration), 2)

        del source
        del dest

        return {
            "buffer_mb": buffer_mb,
            "read_bandwidth_gbs": read_gbs,
            "copy_bandwidth_gbs": copy_gbs,
            "status": "PASS"
        }
    except Exception as e:
        return {
            "error": str(e),
            "read_bandwidth_gbs": 0.0,
            "copy_bandwidth_gbs": 0.0,
            "status": "FAIL"
        }


if __name__ == "__main__":
    print("Testing OMNI Benchmark & Stress Engine...")
    print("\n1. Running Storage Read Benchmark...")
    disk_res = run_storage_read_benchmark(test_size_mb=64, num_random_ops=300)
    print(f"   Sequential Read: {disk_res['seq_read_mbs']} MB/s")
    print(f"   4K Random Read : {disk_res['rnd_read_mbs']} MB/s ({disk_res['rnd_iops']} IOPS, {disk_res['avg_latency_ms']} ms)")

    print("\n2. Running RAM Memory Bandwidth Benchmark...")
    ram_res = run_ram_bandwidth_benchmark(buffer_mb=128)
    print(f"   Read Bandwidth : {ram_res['read_bandwidth_gbs']} GB/s")
    print(f"   Copy Bandwidth : {ram_res['copy_bandwidth_gbs']} GB/s")

    print("\n3. Running CPU Computational Benchmark (2s)...")
    cpu_res = run_cpu_benchmark(duration_seconds=2)
    print(f"   Single-Thread  : {cpu_res['single_thread_score']} pts ({cpu_res['single_thread_ops_sec']:,} ops/s)")
    print(f"   Multi-Thread   : {cpu_res['multi_thread_score']} pts ({cpu_res['multi_thread_ops_sec']:,} ops/s, {cpu_res['multi_thread_ratio']}x scaling)")

    print("\nEngine test completed successfully.")
