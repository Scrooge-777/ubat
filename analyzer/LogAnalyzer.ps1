<#
.SYNOPSIS
    Universal Battery Drain Log Analyzer Module
.DESCRIPTION
    Analyzes battery-drain-log.csv from the logs/ directory and generates
    detailed statistical reports for any laptop.
#>
param(
    [string]$CustomLogPath = ""
)

$ModuleDir = $PSScriptRoot
$RootDir = Split-Path $ModuleDir -Parent
$LogsDir = Join-Path $RootDir "logs"
$LogFile = if ($CustomLogPath) { $CustomLogPath } else { Join-Path $LogsDir "current-session.csv" }

if (-not (Test-Path $LogFile)) {
    Write-Host "Log file not found: $LogFile" -ForegroundColor Red
    exit 1
}

$rawLines = Get-Content -Path $LogFile | Where-Object { $_ -notmatch "^#" -and $_ -match "," }
$csvData = $rawLines | ConvertFrom-Csv

if ($csvData.Count -lt 2) {
    Write-Host "Log contains only $($csvData.Count) entry so far. Need at least 2 entries to calculate drain rate." -ForegroundColor Yellow
    exit 0
}

$first = $csvData[0]
$last = $csvData[-1]

$startTime = [datetime]::Parse($first.Timestamp)
$endTime = [datetime]::Parse($last.Timestamp)
$duration = $endTime - $startTime
$totalMinutes = [math]::Round($duration.TotalMinutes, 1)
$totalHours = [math]::Round($duration.TotalHours, 2)

$startPct = [double]$first.BatteryPercent
$endPct = [double]$last.BatteryPercent
$pctDrop = [math]::Round($startPct - $endPct, 1)

$startCap = [double]$first.Remaining_mWh
$endCap = [double]$last.Remaining_mWh
$mWhConsumed = [math]::Round($startCap - $endCap, 1)

$avgWatts = 0
$discharges = $csvData | Where-Object { [double]$_.DischargeRate_Watts -gt 0 }
if ($discharges.Count -gt 0) {
    $avgWatts = [math]::Round(($discharges | Measure-Object -Property DischargeRate_Watts -Average).Average, 2)
}

$avgCpu = [math]::Round(($csvData | Measure-Object -Property Cpu_Percent -Average).Average, 1)
$avgRam = [math]::Round(($csvData | Measure-Object -Property RamUsed_GB -Average).Average, 2)

# Auto-detect battery capacity from system
$fullCap = Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue
$capacityWh = if ($fullCap) { [math]::Round($fullCap.FullChargedCapacity / 1000, 1) } else { 80.0 }

# Projected total runtime from full charge at this burn rate:
$projectedFullLifeHours = 0
if ($avgWatts -gt 0) {
    $projectedFullLifeHours = [math]::Round($capacityWh / $avgWatts, 2)
}

# Projected remaining runtime from current level:
$projectedRemainingHours = 0
if ($avgWatts -gt 0) {
    $projectedRemainingHours = [math]::Round(($endCap / 1000) / $avgWatts, 2)
}

# App frequency
$topCpuApps = $csvData | Group-Object TopCpuApp | Sort-Object Count -Descending | Select-Object -First 3
$topMemApps = $csvData | Group-Object TopMemApp | Sort-Object Count -Descending | Select-Object -First 3

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "                UNIVERSAL BATTERY DRAIN TEST ANALYSIS REPORT                    " -ForegroundColor Yellow
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " Log File:              $LogFile" -ForegroundColor DarkGray
Write-Host " Test Interval:         $($first.Timestamp)  -->  $($last.Timestamp)" -ForegroundColor Gray
Write-Host " Elapsed Test Time:     $totalMinutes mins ($totalHours hours)" -ForegroundColor White
Write-Host ""
Write-Host " [DRAIN METRICS]" -ForegroundColor Green
Write-Host "   Starting Battery:    $startPct % ($startCap mWh)"
Write-Host "   Current Battery:     $endPct % ($endCap mWh)"
Write-Host "   Total Battery Used:  $pctDrop % ($mWhConsumed mWh consumed)" -ForegroundColor Yellow
Write-Host "   Average Power Draw:  $avgWatts Watts" -ForegroundColor $(if ($avgWatts -le 20) { 'Green' } else { 'Red' })
Write-Host ""
Write-Host " [RUN-TIME PROJECTIONS]" -ForegroundColor Green
Write-Host "   Battery Full Size:   $capacityWh Wh"
Write-Host "   Projected Full Life: $projectedFullLifeHours hours (if started at 100%)" -ForegroundColor $(if ($projectedFullLifeHours -ge 4) { 'Green' } else { 'Yellow' })
Write-Host "   Projected Remaining: $projectedRemainingHours hours (from current $endPct%)"
Write-Host "   4-Hour Target:       $(if ($projectedFullLifeHours -ge 4) { '[PASS] Meets or exceeds 4 hours!' } else { '[FAIL] Exceeds power budget. Run optimize-battery.bat.' })" -ForegroundColor $(if ($projectedFullLifeHours -ge 4) { 'Green' } else { 'Red' })
Write-Host ""
Write-Host " [SYSTEM LOAD DURING TEST]" -ForegroundColor Green
Write-Host "   Average CPU Load:    $avgCpu %"
Write-Host "   Average RAM Used:    $avgRam GB"
Write-Host "   Most Active CPU App: $($topCpuApps[0].Name) ($($topCpuApps[0].Count) samples)"
Write-Host "   Top Memory Hog:      $($topMemApps[0].Name) ($($topMemApps[0].Count) samples)"
Write-Host "================================================================================" -ForegroundColor Cyan

# Save Markdown report copy in logs/
$ReportMdPath = Join-Path $LogsDir "last-report.md"
$mdContent = @"
# Battery Drain Benchmark Report
*Generated on: $(Get-Date)*

### Test Summary
- **Test Period:** $($first.Timestamp) to $($last.Timestamp)
- **Duration:** $totalMinutes mins ($totalHours hours)
- **Starting Level:** $startPct % ($startCap mWh)
- **Ending Level:** $endPct % ($endCap mWh)
- **Battery Consumed:** $pctDrop % ($mWhConsumed mWh)
- **Average Discharge Rate:** $avgWatts Watts
- **Projected Total Runtime (100%):** $projectedFullLifeHours hours
- **4-Hour Feasibility Target:** $(if ($projectedFullLifeHours -ge 4) { 'PASS' } else { 'WARNING / HIGH DRAW' })

### Hardware Load During Session
- **Average CPU Load:** $avgCpu %
- **Average RAM Usage:** $avgRam GB
- **Top CPU Drainer:** $($topCpuApps[0].Name)
- **Top Memory Consumer:** $($topMemApps[0].Name)
"@
Set-Content -Path $ReportMdPath -Value $mdContent -Encoding utf8
Write-Host "Saved detailed markdown report to: $ReportMdPath" -ForegroundColor DarkGray
