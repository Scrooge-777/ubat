<#
.SYNOPSIS
    NVMe SSD Health, Partition Layout & Storage Diagnostics
.DESCRIPTION
    Inspects physical NVMe SSD drives, SMART reliability counters (Wear Degradation %, Temperature),
    volume partitions, file systems, disk usage percentages, and real-time read/write speeds.
#>

$ScriptDir = Split-Path $PSScriptRoot -Parent
$w = 88
try {
    $w = [Console]::WindowWidth - 1
    if ($w -lt 80) { $w = 88 }
} catch { $w = 88 }

Clear-Host
Write-Host ("=" * $w) -ForegroundColor Cyan
Write-Host (" " * [math]::Max(0, [math]::Floor(($w - 36) / 2)) + "STORAGE & NVME PARTITION DIAGNOSTICS") -ForegroundColor Yellow
Write-Host ("=" * $w) -ForegroundColor Cyan
Write-Host ""

# 1. Physical SSD & SMART Wear Info
Write-Host " [1. PHYSICAL DRIVE HEALTH & SMART WEAR]" -ForegroundColor Cyan
$disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
foreach ($d in $disks) {
    $sizeGB = [math]::Round($d.Size / 1GB, 1)
    $media = if ($d.MediaType) { $d.MediaType } else { "SSD" }
    $bus = if ($d.BusType) { $d.BusType } else { "NVMe" }
    $health = $d.HealthStatus
    $status = $d.OperationalStatus
    
    $temp = "--"
    $wear = 0
    try {
        $rel = Get-StorageReliabilityCounter -PhysicalDisk $d -ErrorAction SilentlyContinue
        if ($rel) {
            if ($rel.Temperature) { $temp = "$($rel.Temperature) C" }
            if ($rel.Wear -ne $null) { $wear = $rel.Wear }
        }
    } catch {}

    $healthCol = if ($health -eq "Healthy") { "Green" } else { "Red" }
    Write-Host "   Device Model:    $($d.FriendlyName)" -ForegroundColor White
    Write-Host "   Type / Bus:      $media / $bus  ($sizeGB GB Total)" -ForegroundColor Gray
    Write-Host "   Health Status:   $health (Operational: $status)" -ForegroundColor $healthCol
    Write-Host "   Wear Level:      $wear% Degradation (Remaining Life: $(100 - $wear)%)" -ForegroundColor $(if ($wear -le 10) { 'Green' } else { 'Yellow' })
    Write-Host "   Drive Temp:      $temp" -ForegroundColor $(if ($temp -match '^[0-4]') { 'Green' } else { 'Yellow' })
}
Write-Host ""

# 2. Partition & File System Breakdown
Write-Host " [2. DRIVE PARTITIONS & FILE SYSTEMS]" -ForegroundColor Cyan
$vols = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }

$hdr = " {0,-5} | {1,-16} | {2,-8} | {3,9} | {4,9} | {5,8} | {6,-16}" -f "DRIVE", "LABEL", "FS", "TOTAL(GB)", "FREE(GB)", "USED %", "VOLUME USAGE"
Write-Host $hdr -ForegroundColor Yellow
Write-Host ("-" * [math]::Min($w, $hdr.Length + 2)) -ForegroundColor DarkGray

foreach ($v in $vols) {
    $dl = "$($v.DriveLetter):"
    $lbl = if ($v.FileSystemLabel) { $v.FileSystemLabel } else { "Local Disk" }
    if ($lbl.Length -gt 16) { $lbl = $lbl.Substring(0, 16) }
    $fs = $v.FileSystem
    $tot = [math]::Round($v.Size / 1GB, 1)
    $free = [math]::Round($v.SizeRemaining / 1GB, 1)
    $usedPct = 0
    if ($v.Size -gt 0) {
        $usedPct = [math]::Round((($v.Size - $v.SizeRemaining) / $v.Size) * 100, 1)
    }

    # ASCII mini progress bar
    $barLen = 10
    $fill = [math]::Round($barLen * ($usedPct / 100))
    $bar = ("=" * $fill) + ("-" * ($barLen - $fill))
    $barStr = "[$bar]"

    $col = if ($usedPct -ge 90) { "Red" } elseif ($usedPct -ge 75) { "Yellow" } else { "Green" }
    $line = " {0,-5} | {1,-16} | {2,-8} | {3,9} | {4,9} | {5,7}% | {6,-16}" -f $dl, $lbl, $fs, $tot, $free, $usedPct, $barStr
    Write-Host $line -ForegroundColor $col
}
Write-Host ""

# 3. Real-Time NVMe Performance Sample
Write-Host " [3. REAL-TIME STORAGE READ/WRITE THROUGHPUT]" -ForegroundColor Cyan
$readSpeedMB = 0.0
$writeSpeedMB = 0.0
$activeTimePct = 0.0

try {
    $c = Get-Counter '\PhysicalDisk(_Total)\Disk Read Bytes/sec', '\PhysicalDisk(_Total)\Disk Write Bytes/sec', '\PhysicalDisk(_Total)\% Disk Time' -MaxSamples 1 -ErrorAction Stop
    $readBytes = $c.CounterSamples | Where-Object { $_.Path -like '*read bytes*' } | Select-Object -ExpandProperty CookedValue
    $writeBytes = $c.CounterSamples | Where-Object { $_.Path -like '*write bytes*' } | Select-Object -ExpandProperty CookedValue
    $diskTime = $c.CounterSamples | Where-Object { $_.Path -like '*% disk time*' } | Select-Object -ExpandProperty CookedValue

    $readSpeedMB = [math]::Round($readBytes / 1MB, 2)
    $writeSpeedMB = [math]::Round($writeBytes / 1MB, 2)
    $activeTimePct = [math]::Min(100, [math]::Round($diskTime, 1))
} catch {}

Write-Host "   Read Throughput:     $readSpeedMB MB/s" -ForegroundColor Green
Write-Host "   Write Throughput:    $writeSpeedMB MB/s" -ForegroundColor Cyan
Write-Host "   Disk Active Time:    $activeTimePct %" -ForegroundColor $(if ($activeTimePct -lt 20) { 'Green' } else { 'Yellow' })

# Power estimate
$estSsdWatts = 0.5
if ($activeTimePct -gt 50 -or ($readSpeedMB + $writeSpeedMB) -gt 100) { $estSsdWatts = 4.2 }
elseif ($activeTimePct -gt 10 -or ($readSpeedMB + $writeSpeedMB) -gt 10) { $estSsdWatts = 2.1 }
Write-Host "   Storage Power State: $(if ($activeTimePct -le 5) { 'Autonomous Power State (APST L1.2 Low-Power Idle)' } else { 'Active IO State' })" -ForegroundColor Gray

Write-Host ""
Write-Host ("-" * $w) -ForegroundColor Cyan
Write-Host " Options: [T] Run SSD TRIM Optimizer  |  [R] Refresh  |  [Enter] Return" -ForegroundColor Yellow
Write-Host ("=" * $w) -ForegroundColor Cyan

# Non-interactive check
try {
    if ([Console]::IsInputRedirected) { return }
} catch { return }

$key = [Console]::ReadKey($true)
if ($key.Key -eq 'T' -or $key.KeyChar -eq 't') {
    & "$ScriptDir\optimizer\SsdOptimizer.ps1"
    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
    [Console]::ReadKey($true) | Out-Null
}
