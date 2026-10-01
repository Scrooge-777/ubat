"""
HWiNFO Shared Memory Bridge (v8.x HWiNFO_SENS_SM2)
==================================================
Reads real-time fan RPMs, VRM temperatures, and GPU Hotspot sensors
published by HWiNFO64 via Windows Memory-Mapped File 'Global\\HWiNFO_SENS_SM2'.
"""

import mmap
import struct

HWINFO_SHARED_MEM_NAMES = [
    "Global\\HWiNFO_SENS_SM2",
    "HWiNFO_SENS_SM2",
    "Local\\HWiNFO_SENS_SM2",
]
HWINFO_SIGNATURE = 0x49576948  # 'HiWI'

# Sensor Types
SENSOR_TYPE_NONE = 0
SENSOR_TYPE_TEMP = 1
SENSOR_TYPE_VOLT = 2
SENSOR_TYPE_FAN = 3
SENSOR_TYPE_CURRENT = 4
SENSOR_TYPE_POWER = 5
SENSOR_TYPE_CLOCK = 6
SENSOR_TYPE_USAGE = 7
SENSOR_TYPE_OTHER = 8


def query_hwinfo_sensors():
    """Safely inspects HWiNFO Shared Memory for deep hardware telemetry."""
    data = {
        "active": False,
        "cpu_fan_rpm": 0,
        "gpu_fan_rpm": 0,
        "gpu_hotspot_c": 0,
        "vrm_temp_c": 0,
        "package_power_w": 0.0,
    }

    for tag in HWINFO_SHARED_MEM_NAMES:
        try:
            with mmap.mmap(-1, 0, tagname=tag, access=mmap.ACCESS_READ) as mm:
                if len(mm) < 40:
                    continue

                # Header: signature(4), version(4), revision(4), poll_time(8),
                # offset_sensor(4), size_sensor(4), num_sensors(4),
                # offset_entry(4), size_entry(4), num_entries(4)
                sig, ver, rev, poll_time, off_sensor, sz_sensor, num_sensors, off_entry, sz_entry, num_entries = struct.unpack_from(
                    "<IIIqIIIIII", mm, 0
                )

                if sig != HWINFO_SIGNATURE:
                    continue

                data["active"] = True

                # Scan entries
                for i in range(num_entries):
                    entry_offset = off_entry + (i * sz_entry)
                    if entry_offset + sz_entry > len(mm):
                        break

                    s_type, s_idx, s_id = struct.unpack_from("<III", mm, entry_offset)
                    raw_label = struct.unpack_from("<128s", mm, entry_offset + 12)[0]
                    label = raw_label.split(b"\x00")[0].decode("ascii", errors="ignore").strip().lower()

                    raw_unit = struct.unpack_from("<16s", mm, entry_offset + 12 + 128 + 128)[0]
                    unit = raw_unit.split(b"\x00")[0].decode("ascii", errors="ignore").strip()

                    val_offset = entry_offset + 12 + 128 + 128 + 16
                    val = struct.unpack_from("<d", mm, val_offset)[0]

                    # Match fan sensors
                    if s_type == SENSOR_TYPE_FAN or "rpm" in unit.lower() or "fan" in label:
                        if "cpu" in label:
                            data["cpu_fan_rpm"] = int(val)
                        elif "gpu" in label:
                            data["gpu_fan_rpm"] = int(val)
                        elif data["cpu_fan_rpm"] == 0:
                            data["cpu_fan_rpm"] = int(val)
                        elif data["gpu_fan_rpm"] == 0 and int(val) != data["cpu_fan_rpm"]:
                            data["gpu_fan_rpm"] = int(val)

                    # Match temperature sensors
                    elif s_type == SENSOR_TYPE_TEMP or "c" in unit.lower() or "\xb0c" in unit.lower():
                        if "hotspot" in label:
                            data["gpu_hotspot_c"] = int(val)
                        elif "vrm" in label or "mosfet" in label:
                            data["vrm_temp_c"] = int(val)

                    # Match package power
                    elif s_type == SENSOR_TYPE_POWER and ("package" in label or "cpu power" in label):
                        data["package_power_w"] = round(float(val), 1)

                return data
        except Exception:
            continue

    return data


if __name__ == "__main__":
    res = query_hwinfo_sensors()
    print("HWiNFO Shared Memory State:", res)
