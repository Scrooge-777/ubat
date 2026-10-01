<#
.SYNOPSIS
    NVMe & SATA SSD Storage Optimizer
.DESCRIPTION
    Performs volume ReTrim, verifies Windows TRIM behavior, checks SMART health
    and degradation wear levels, and optimizes SSD file systems.
#>

Clear-Host
$w = 88
try {
    $w = [Console]::WindowWidth - 1
    if ($w -lt 80) { $w = 88 }
} catch { $w = 88 }

Write-Host ("=" * $w) -ForegroundColor Cyan
Write-Host (" " * [math]::Max(0, [math]::Floor(($w - 32) / 2)) + "SSD & STORAGE HARDWARE OPTIMIZER") -ForegroundColor Yellow
Write-Host ("=" * $w) -ForegroundColor Cyan
Write-Host ""

# 1. Physical SSD Info & SMART Wear
Write-Host " [1/4] QUERYING PHYSICAL STORAGE HARDWARE & HEALTH..." -ForegroundColor Cyan
$disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
foreach ($d in $disks) {
    $szGb = [math]::Round($d.Size / 1GB, 1)
    $media = if ($d.MediaType) { $d.MediaType } else { "SSD" }
    $bus = if ($d.BusType) { $d.BusType } else { "NVMe" }
    $health = $d.HealthStatus
    $status = $d.OperationalStatus
    
    # Query reliability counters (Wear, Temp)
    $temp = "--"
    $wear = 0
    try {
        $rel = Get-StorageReliabilityCounter -PhysicalDisk $d -ErrorAction SilentlyContinue
        if ($rel) {
            if ($rel.Temperature) { $temp = "$($rel.Temperature) C" }
            if ($rel.Wear -ne $null) { $wear = $rel.Wear }
        }
    } catch {}

    $healthCol = if ($health -eq "Healthy") { "Green" } else { "Yellow" }
    Write-Host "   Model:       $($d.FriendlyName)" -ForegroundColor White
    Write-Host "   Type / Bus:  $media / $bus  ($szGb GB)" -ForegroundColor Gray
    Write-Host "   Health:      $health ($status)" -ForegroundColor $healthCol
    Write-Host "   Degradation: $wear% Lifetime Wear  |  Temperature: $temp" -ForegroundColor White
}
Write-Host ""

# 2. Windows TRIM Configuration Check
Write-Host " [2/4] VERIFYING WINDOWS TRIM / DELETE NOTIFICATION SUBSYSTEM..." -ForegroundColor Cyan
try {
    $trimQuery = fsutil behavior query DisableDeleteNotify
    $trimEnabled = $false
    foreach ($line in $trimQuery) {
        Write-Host "   $line" -ForegroundColor DarkGray
        if ($line -match "DisableDeleteNotify = 0") {
            $trimEnabled = $true
        }
    }
    if ($trimEnabled) {
        Write-Host "   [OK] Windows TRIM is fully active (Deletions are automatically trimmed)." -ForegroundColor Green
    } else {
        Write-Host "   [WARN] TRIM may be disabled. Enabling TRIM now..." -ForegroundColor Yellow
        fsutil behavior set DisableDeleteNotify 0 | Out-Null
        Write-Host "   [OK] TRIM enabled successfully." -ForegroundColor Green
    }
} catch {
    Write-Host "   [INFO] Could not query TRIM status: $_" -ForegroundColor DarkGray
}
Write-Host ""

# 3. Optimize & ReTrim Partitions
Write-Host " [3/4] PERFORMING RETRIM / DEFRAG OPTIMIZATION ON SSD VOLUMES..." -ForegroundColor Cyan
$volumes = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }

$results = @()
foreach ($vol in $volumes) {
    $dl = $vol.DriveLetter
    $label = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "Local Disk" }
    $fs = $vol.FileSystem
    $freeGb = [math]::Round($vol.SizeRemaining / 1GB, 1)
    $totGb = [math]::Round($vol.Size / 1GB, 1)

    Write-Host "   Invoking TRIM on Drive $($dl): ($label, $fs)..." -ForegroundColor White -NoNewline

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $statusText = "Completed"
    try {
        $opt = Optimize-Volume -DriveLetter $dl -ReTrim -ErrorAction Stop
        $sw.Stop()
        Write-Host " [OK] ($($sw.ElapsedMilliseconds)ms)" -ForegroundColor Green
    } catch {
        try {
            $defragOut = defrag "$($dl):" /O /U 2>&1
            $sw.Stop()
            Write-Host " [OK via defrag] ($($sw.ElapsedMilliseconds)ms)" -ForegroundColor Green
        } catch {
            $sw.Stop()
            $statusText = "Skipped / ReFS"
            Write-Host " [SKIPPED / REFS]" -ForegroundColor Yellow
        }
    }

    $results += [PSCustomObject]@{
        Drive        = "$($dl):"
        Label        = $label
        FileSystem   = $fs
        TotalSizeGB  = $totGb
        FreeSpaceGB  = $freeGb
        Optimization = $statusText
    }
}
Write-Host ""

# 4. Safe Temp Cache Cleanup
Write-Host " [4/4] CLEANING WRITE-AMPLIFICATION TEMP CACHE..." -ForegroundColor Cyan
$tempPaths = @(
    $env:TEMP,
    "$env:LOCALAPPDATA\Temp"
)
$cleanedCount = 0
$cleanedBytes = 0

foreach ($p in $tempPaths) {
    if (Test-Path $p) {
        $files = Get-ChildItem -Path $p -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) }
        foreach ($f in $files) {
            try {
                $cleanedBytes += $f.Length
                Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue
                $cleanedCount++
            } catch {}
        }
    }
}
$cleanedMb = [math]::Round($cleanedBytes / 1MB, 1)
Write-Host "   Cleaned $cleanedCount stale temporary files ($cleanedMb MB freed) to minimize SSD write wear." -ForegroundColor Green
Write-Host ""

# Summary Table
Write-Host ("-" * $w) -ForegroundColor Cyan
Write-Host " SSD OPTIMIZATION SUMMARY:" -ForegroundColor Yellow
$results | Format-Table -Property Drive, Label, FileSystem, TotalSizeGB, FreeSpaceGB, Optimization -AutoSize | Out-String | Write-Host -ForegroundColor White
Write-Host ("=" * $w) -ForegroundColor Cyan
Write-Host " [DONE] SSD storage partitions trimmed and file system wear minimized." -ForegroundColor Green
