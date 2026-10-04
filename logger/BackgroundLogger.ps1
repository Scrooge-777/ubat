<#
.SYNOPSIS
    Universal Background Drain Logger Module
.DESCRIPTION
    Logs battery metrics, discharge wattage, CPU, RAM, and active processes
    every 30 seconds directly to the dedicated logs/ directory.
    Includes log rotation (5,000 row cap), session header with machine info,
    and a critical battery guard at 5% (fires before Windows hibernation).
#>

$ModuleDir = $PSScriptRoot
$RootDir = Split-Path $ModuleDir -Parent
$LogsDir = Join-Path $RootDir "logs"
$ArchiveDir = Join-Path $LogsDir "archive"

if (-not (Test-Path $LogsDir))    { New-Item -ItemType Directory -Path $LogsDir    -Force | Out-Null }
if (-not (Test-Path $ArchiveDir)) { New-Item -ItemType Directory -Path $ArchiveDir -Force | Out-Null }

$CurrentSessionFile = Join-Path $LogsDir "current-session.csv"
$TimestampTag       = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
$ArchiveSessionFile = Join-Path $ArchiveDir "session-$TimestampTag.csv"
$PidFile            = Join-Path $LogsDir "battery-logger.pid"

# ── Constants ───────────────────────────────────────────────────────────────
$MAX_LOG_ROWS   = 5000   # rotate current-session.csv when it exceeds this
$BATTERY_GUARD  = 5      # warn/stop at 5% (Windows hibernates around here)
$LOG_INTERVAL_S = 30     # seconds between entries

# Save current PID so StopLogger.ps1 can terminate this process
$PID | Out-File -FilePath $PidFile -Encoding ascii -Force

$header = "Timestamp,PowerOnline,BatteryPercent,Remaining_mWh,DischargeRate_Watts,Voltage_V,Cpu_Percent,RamUsed_GB,RamTotal_GB,Ram_Percent,TopCpuApp,TopMemApp"

# ── Machine info for session header ─────────────────────────────────────────
$machineInfo = "Unknown"
$designCap   = 0
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($cs) { $machineInfo = "$($cs.Manufacturer) $($cs.Model)".Trim() }
} catch {}
try {
    $sd = Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue
    if ($sd -and $sd.DesignedCapacity) { $designCap = $sd.DesignedCapacity }
} catch {}

$sessionHeader = "# Session Started : $TimestampTag | Machine : $machineInfo | DesignCap : $designCap mWh"

# ── Helper: rotate log if needed ─────────────────────────────────────────────
function Invoke-LogRotation {
    if (-not (Test-Path $CurrentSessionFile)) { return }
    try {
        $lineCount = (Get-Content -Path $CurrentSessionFile -ErrorAction SilentlyContinue).Count
        if ($lineCount -gt ($MAX_LOG_ROWS + 3)) {
            # Archive current and start fresh
            $rotTag    = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
            $rotDest   = Join-Path $ArchiveDir "session-rotated-$rotTag.csv"
            Copy-Item -Path $CurrentSessionFile -Destination $rotDest -Force -ErrorAction SilentlyContinue
            Set-Content -Path $CurrentSessionFile -Value $sessionHeader  -Encoding utf8
            Add-Content -Path $CurrentSessionFile -Value $header         -Encoding utf8
            Add-Content -Path $CurrentSessionFile -Value "# LOG ROTATED AT $rotTag (prev: $lineCount rows)" -Encoding utf8
        }
    } catch {}
}

# ── Initialize session files ──────────────────────────────────────────────────
if (-not (Test-Path $CurrentSessionFile)) {
    Set-Content -Path $CurrentSessionFile -Value $sessionHeader -Encoding utf8
    Add-Content -Path $CurrentSessionFile -Value $header        -Encoding utf8
}
Set-Content -Path $ArchiveSessionFile -Value $sessionHeader -Encoding utf8
Add-Content -Path $ArchiveSessionFile -Value $header        -Encoding utf8

# ── Metrics snapshot ──────────────────────────────────────────────────────────
function Get-MetricsSnapshot {
    $status  = Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus              -ErrorAction SilentlyContinue
    $batt    = Get-CimInstance -ClassName Win32_Battery                                  -ErrorAction SilentlyContinue
    $os      = Get-CimInstance -ClassName Win32_OperatingSystem                          -ErrorAction SilentlyContinue
    $cpu     = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $fullCap = Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue

    $fullCapMwh    = if ($fullCap) { $fullCap.FullChargedCapacity } else { 80000 }
    $powerOnline   = if ($status)  { $status.PowerOnline }          else { $false }
    $remainingMwh  = if ($status)  { $status.RemainingCapacity }    else { 0 }
    $dischargeWatts= if ($status -and $status.DischargeRate) { [math]::Round($status.DischargeRate / 1000, 2) } else { 0 }
    $voltageV      = if ($status -and $status.Voltage)       { [math]::Round($status.Voltage / 1000, 2) }       else { 0 }

    $percent = if ($batt) { $batt.EstimatedChargeRemaining } else { 0 }
    if ($percent -eq 0 -and $remainingMwh -gt 0 -and $fullCapMwh -gt 0) {
        $percent = [math]::Round(($remainingMwh / $fullCapMwh) * 100)
    }

    $cpuLoad    = if ($cpu) { $cpu.LoadPercentage } else { 0 }
    $totalRamGB = if ($os)  { [math]::Round($os.TotalVisibleMemorySize / 1MB, 2) } else { 0 }
    $freeRamGB  = if ($os)  { [math]::Round($os.FreePhysicalMemory / 1MB, 2) }    else { 0 }
    $usedRamGB  = [math]::Round($totalRamGB - $freeRamGB, 2)
    $ramPercent = if ($totalRamGB -gt 0) { [math]::Round(($usedRamGB / $totalRamGB) * 100, 1) } else { 0 }

    $topCpu = (Get-Process | Sort-Object CPU          -Descending | Select-Object -First 1 ProcessName).ProcessName
    $topMem = (Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 1 ProcessName).ProcessName

    return [PSCustomObject]@{
        Timestamp       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        PowerOnline     = $powerOnline
        BatteryPercent  = $percent
        Remaining_mWh   = $remainingMwh
        Discharge_Watts = $dischargeWatts
        Voltage_V       = $voltageV
        Cpu_Percent     = $cpuLoad
        RamUsed_GB      = $usedRamGB
        RamTotal_GB     = $totalRamGB
        Ram_Percent     = $ramPercent
        TopCpuApp       = $topCpu
        TopMemApp       = $topMem
    }
}

# ── Main recording loop ───────────────────────────────────────────────────────
try {
    while ($true) {
        Invoke-LogRotation

        $m = Get-MetricsSnapshot
        $csvLine = "$($m.Timestamp),$($m.PowerOnline),$($m.BatteryPercent),$($m.Remaining_mWh),$($m.Discharge_Watts),$($m.Voltage_V),$($m.Cpu_Percent),$($m.RamUsed_GB),$($m.RamTotal_GB),$($m.Ram_Percent),`"$($m.TopCpuApp)`",`"$($m.TopMemApp)`""

        # Write to both current session and archive file
        Add-Content -Path $CurrentSessionFile  -Value $csvLine -Encoding utf8
        Add-Content -Path $ArchiveSessionFile  -Value $csvLine -Encoding utf8

        # Critical battery guard (5% — fires before Windows hibernation at ~3-4%)
        if ($m.BatteryPercent -gt 0 -and $m.BatteryPercent -le $BATTERY_GUARD -and -not $m.PowerOnline) {
            $msg = "# CRITICAL BATTERY THRESHOLD ($BATTERY_GUARD%) REACHED AT $($m.Timestamp)"
            Add-Content -Path $CurrentSessionFile -Value $msg -Encoding utf8
            Add-Content -Path $ArchiveSessionFile -Value $msg -Encoding utf8
            break
        }

        Start-Sleep -Seconds $LOG_INTERVAL_S
    }
} finally {
    if (Test-Path $PidFile) {
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    }
}
