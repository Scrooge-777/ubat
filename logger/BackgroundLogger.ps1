<#
.SYNOPSIS
    Universal Background Drain Logger Module
.DESCRIPTION
    Logs battery metrics, discharge wattage, CPU, RAM, and active processes
    every 30 seconds directly to the dedicated logs/ directory.
#>

$ModuleDir = $PSScriptRoot
$RootDir = Split-Path $ModuleDir -Parent
$LogsDir = Join-Path $RootDir "logs"
$ArchiveDir = Join-Path $LogsDir "archive"

if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null }
if (-not (Test-Path $ArchiveDir)) { New-Item -ItemType Directory -Path $ArchiveDir -Force | Out-Null }

$CurrentSessionFile = Join-Path $LogsDir "current-session.csv"
$TimestampTag = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
$ArchiveSessionFile = Join-Path $ArchiveDir "session-$TimestampTag.csv"
$PidFile = Join-Path $LogsDir "battery-logger.pid"

# Save current PID
$PID | Out-File -FilePath $PidFile -Encoding ascii -Force

$header = "Timestamp,PowerOnline,BatteryPercent,Remaining_mWh,DischargeRate_Watts,Voltage_V,Cpu_Percent,RamUsed_GB,RamTotal_GB,Ram_Percent,TopCpuApp,TopMemApp"

# Initialize current session if not existing
if (-not (Test-Path $CurrentSessionFile)) {
    Set-Content -Path $CurrentSessionFile -Value $header -Encoding utf8
}
# Initialize archive session
Set-Content -Path $ArchiveSessionFile -Value $header -Encoding utf8

function Get-MetricsSnapshot {
    $status = Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue
    $batt = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $fullCap = Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue

    $fullCapMwh = if ($fullCap) { $fullCap.FullChargedCapacity } else { 80000 }
    $powerOnline = if ($status) { $status.PowerOnline } else { $false }
    $remainingMwh = if ($status) { $status.RemainingCapacity } else { 0 }
    $dischargeWatts = if ($status -and $status.DischargeRate) { [math]::Round($status.DischargeRate / 1000, 2) } else { 0 }
    $voltageV = if ($status -and $status.Voltage) { [math]::Round($status.Voltage / 1000, 2) } else { 0 }
    
    $percent = if ($batt) { $batt.EstimatedChargeRemaining } else { 0 }
    if ($percent -eq 0 -and $remainingMwh -gt 0 -and $fullCapMwh -gt 0) {
        $percent = [math]::Round(($remainingMwh / $fullCapMwh) * 100)
    }

    $cpuLoad = if ($cpu) { $cpu.LoadPercentage } else { 0 }

    $totalRamGB = if ($os) { [math]::Round($os.TotalVisibleMemorySize / 1MB, 2) } else { 0 }
    $freeRamGB = if ($os) { [math]::Round($os.FreePhysicalMemory / 1MB, 2) } else { 0 }
    $usedRamGB = [math]::Round($totalRamGB - $freeRamGB, 2)
    $ramPercent = if ($totalRamGB -gt 0) { [math]::Round(($usedRamGB / $totalRamGB) * 100, 1) } else { 0 }

    # Top processes
    $topCpu = (Get-Process | Sort-Object CPU -Descending | Select-Object -First 1 ProcessName).ProcessName
    $topMem = (Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 1 ProcessName).ProcessName

    return [PSCustomObject]@{
        Timestamp        = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        PowerOnline      = $powerOnline
        BatteryPercent   = $percent
        Remaining_mWh    = $remainingMwh
        Discharge_Watts  = $dischargeWatts
        Voltage_V        = $voltageV
        Cpu_Percent      = $cpuLoad
        RamUsed_GB       = $usedRamGB
        RamTotal_GB      = $totalRamGB
        Ram_Percent      = $ramPercent
        TopCpuApp        = $topCpu
        TopMemApp        = $topMem
    }
}

try {
    while ($true) {
        $m = Get-MetricsSnapshot
        $csvLine = "$($m.Timestamp),$($m.PowerOnline),$($m.BatteryPercent),$($m.Remaining_mWh),$($m.Discharge_Watts),$($m.Voltage_V),$($m.Cpu_Percent),$($m.RamUsed_GB),$($m.RamTotal_GB),$($m.Ram_Percent),`"$($m.TopCpuApp)`",`"$($m.TopMemApp)`""
        
        # Write to both current session and archive file
        Add-Content -Path $CurrentSessionFile -Value $csvLine -Encoding utf8
        Add-Content -Path $ArchiveSessionFile -Value $csvLine -Encoding utf8

        # Critical battery auto-shutdown guard (<= 3%)
        if ($m.BatteryPercent -gt 0 -and $m.BatteryPercent -le 3) {
            $msg = "# CRITICAL BATTERY THRESHOLD (3%) REACHED AT $($m.Timestamp)"
            Add-Content -Path $CurrentSessionFile -Value $msg -Encoding utf8
            Add-Content -Path $ArchiveSessionFile -Value $msg -Encoding utf8
            break
        }

        Start-Sleep -Seconds 30
    }
} finally {
    if (Test-Path $PidFile) {
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    }
}
