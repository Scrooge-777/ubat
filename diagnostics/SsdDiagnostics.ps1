<#
.SYNOPSIS
    NVMe SSD Health, Speed & Power Diagnostics
.DESCRIPTION
    Analyzes physical SSD drives, health status, real-time read/write throughput,
    disk activity time %, and estimated storage power consumption.
#>

Clear-Host
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "                NVMe SSD HEALTH, PERFORMANCE & POWER DIAGNOSTICS                " -ForegroundColor Yellow
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Physical Disk Inspection
Write-Host " [1. DETECTED STORAGE DRIVES]" -ForegroundColor Green
$disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
foreach ($d in $disks) {
    $sizeGB = [math]::Round($d.Size / 1GB, 1)
    Write-Host "   Device Model:        $($d.FriendlyName)" -ForegroundColor White
    Write-Host "   Media Type:          $($d.MediaType)" -ForegroundColor White
    Write-Host "   Total Capacity:      $sizeGB GB" -ForegroundColor White
    Write-Host "   Health Status:       $($d.HealthStatus) (Operational: $($d.OperationalStatus))" -ForegroundColor $(if ($d.HealthStatus -eq 'Healthy') { 'Green' } else { 'Red' })
    Write-Host "   Bus Type:            $($d.BusType)" -ForegroundColor Gray
}

Write-Host ""
# 2. Real-Time NVMe Performance & Throughput
Write-Host " [2. REAL-TIME THROUGHPUT & ACTIVITY (1-SECOND SAMPLE)]" -ForegroundColor Green

$readSpeedMB = 0
$writeSpeedMB = 0
$activeTimePct = 0

try {
    $c = Get-Counter '\PhysicalDisk(_Total)\Disk Read Bytes/sec', '\PhysicalDisk(_Total)\Disk Write Bytes/sec', '\PhysicalDisk(_Total)\% Disk Time' -MaxSamples 1 -ErrorAction Stop
    $readBytes = $c.CounterSamples | Where-Object { $_.Path -like '*read bytes*' } | Select-Object -ExpandProperty CookedValue
    $writeBytes = $c.CounterSamples | Where-Object { $_.Path -like '*write bytes*' } | Select-Object -ExpandProperty CookedValue
    $diskTime = $c.CounterSamples | Where-Object { $_.Path -like '*% disk time*' } | Select-Object -ExpandProperty CookedValue

    $readSpeedMB = [math]::Round($readBytes / 1MB, 2)
    $writeSpeedMB = [math]::Round($writeBytes / 1MB, 2)
    $activeTimePct = [math]::Min(100, [math]::Round($diskTime, 1))
} catch {
    Write-Host "   [!] Performance counters unavailable." -ForegroundColor Yellow
}

Write-Host "   Read Throughput:     $readSpeedMB MB/s" -ForegroundColor Cyan
Write-Host "   Write Throughput:    $writeSpeedMB MB/s" -ForegroundColor Cyan
Write-Host "   Disk Active Time:    $activeTimePct %" -ForegroundColor $(if ($activeTimePct -lt 20) { 'Green' } else { 'Yellow' })

Write-Host ""
# 3. Estimated Storage Power Impact
Write-Host " [3. STORAGE POWER IMPACT]" -ForegroundColor Green
# Modern Gen4 NVMe draws ~0.3W - 0.6W at idle (APST/ASPM active), and ~3.5W - 5.5W under sustained IO
$estSsdWatts = 0.5
if ($activeTimePct -gt 50 -or ($readSpeedMB + $writeSpeedMB) -gt 100) {
    $estSsdWatts = 4.2
} elseif ($activeTimePct -gt 10 -or ($readSpeedMB + $writeSpeedMB) -gt 10) {
    $estSsdWatts = 2.1
}

Write-Host "   Estimated SSD Draw:  $estSsdWatts Watts" -ForegroundColor $(if ($estSsdWatts -le 1.0) { 'Green' } else { 'Yellow' })
Write-Host "   Power State:         $(if ($activeTimePct -le 5) { 'Autonomous Power State (APST Idle / Sleep)' } else { 'Active Read/Write IO State' })" -ForegroundColor Gray

# 4. Storage Optimization Tip
Write-Host ""
Write-Host " [4. BATTERY SAVING STORAGE TIP]" -ForegroundColor Yellow
Write-Host "   * Windows background indexing or cloud sync (OneDrive, etc.) can cause persistent" -ForegroundColor White
Write-Host "     SSD wakeups, preventing the NVMe controller from staying in low-power L1.2 state." -ForegroundColor Gray
Write-Host "================================================================================" -ForegroundColor Cyan
