<#
.SYNOPSIS
    Task Manager-Style Process Power Manager & Interactive Killer
.DESCRIPTION
    Displays a parallel tabular column view of active processes sorted by resource drain,
    identifies which apps are locking the NVIDIA GPU or spiking CPU/RAM/Disk,
    and provides an interactive prompt to kill rogue processes instantly.
#>

$totalRamMB = 16384
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os -and $os.TotalVisibleMemorySize) { $totalRamMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 0) }
} catch {}
$cpuCount = [Environment]::ProcessorCount

function Get-ProcessTable {
    # Query live performance proc metrics
    $perfProcs = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '_Total|Idle' }
    
    # Query NVIDIA active processes if available
    $nvidiaPids = @()
    try {
        $nv = nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits 2>$null
        if ($nv) { $nvidiaPids += ($nv -split "`r`n") | ForEach-Object { [int]$_.Trim() } }
    } catch {}

    $rows = foreach ($p in $perfProcs) {
        $pidNum = $p.IDProcess
        if ($pidNum -eq 0 -or $pidNum -eq 4) { continue } # skip System / Idle for kill list
        
        $cpuPct = [math]::Round($p.PercentProcessorTime / $cpuCount, 1)
        $ramMB = [math]::Round($p.WorkingSetPrivate / 1MB, 1)
        $ramPct = [math]::Round(($ramMB / $totalRamMB) * 100, 1)
        $diskKBs = [math]::Round(($p.IOReadBytesPersec + $p.IOWriteBytesPersec) / 1KB, 1)
        
        $cleanName = ($p.Name -split '#')[0]
        
        $gpuTag = "iGPU / Idle"
        if ($nvidiaPids -contains $pidNum) {
            $gpuTag = "NVIDIA dGPU [AWAKE]"
        }

        # Power Impact heuristic
        $impact = "Very Low"
        if ($gpuTag -match "NVIDIA") {
            $impact = "HIGH (dGPU Active)"
        } elseif ($cpuPct -gt 15 -or $ramMB -gt 1500 -or $diskKBs -gt 5000) {
            $impact = "HIGH"
        } elseif ($cpuPct -gt 5 -or $ramMB -gt 500 -or $diskKBs -gt 1000) {
            $impact = "Moderate"
        }

        [PSCustomObject]@{
            ProcessName = $cleanName
            PID         = $pidNum
            'CPU(%)'    = $cpuPct
            'RAM(MB)'   = $ramMB
            'RAM(%)'    = $ramPct
            'Disk(KB/s)'= $diskKBs
            'GPU Engine'= $gpuTag
            'Power Tier'= $impact
        }
    }

    # Filter to notable processes and sort by CPU then RAM
    return $rows | Where-Object { $_.'CPU(%)' -gt 0 -or $_.'RAM(MB)' -gt 100 -or $_.'GPU Engine' -match "NVIDIA" } | Sort-Object @{Expression={$_.'GPU Engine' -match "NVIDIA"}; Descending=$true}, 'CPU(%)', 'RAM(MB)' -Descending | Select-Object -First 15
}

while ($true) {
    Clear-Host
    Write-Host "==========================================================================================" -ForegroundColor Cyan
    Write-Host "                  TASK MANAGER PROCESS POWER MONITOR & PROCESS KILLER                     " -ForegroundColor Yellow
    Write-Host "==========================================================================================" -ForegroundColor Cyan
    Write-Host " System Memory: $totalRamMB MB Total  |  Logical CPU Cores: $cpuCount" -ForegroundColor Gray
    Write-Host ""

    $table = Get-ProcessTable
    $table | Format-Table -Property ProcessName, PID, 'CPU(%)', 'RAM(MB)', 'RAM(%)', 'Disk(KB/s)', 'GPU Engine', 'Power Tier' -AutoSize | Out-String | Write-Host -ForegroundColor White

    Write-Host "------------------------------------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host " Commands:" -ForegroundColor Yellow
    Write-Host "   - Type a PID number and press Enter to KILL that process instantly." -ForegroundColor Red
    Write-Host "   - Press [Enter] without typing anything to REFRESH the list." -ForegroundColor White
    Write-Host "   - Type '0' or 'q' and press Enter to RETURN to the main menu." -ForegroundColor Gray
    Write-Host "------------------------------------------------------------------------------------------" -ForegroundColor Cyan
    
    $inputChoice = Read-Host " Enter PID to Kill or Action"
    if ($inputChoice -eq '0' -or $inputChoice -eq 'q' -or $inputChoice -eq 'exit') {
        break
    }
    if ([string]::IsNullOrWhiteSpace($inputChoice)) {
        continue
    }

    $targetPid = $null
    if ([int]::TryParse($inputChoice, [ref]$targetPid)) {
        try {
            $pToKill = Get-Process -Id $targetPid -ErrorAction Stop
            $pName = $pToKill.ProcessName
            Stop-Process -Id $targetPid -Force -ErrorAction Stop
            Write-Host " [SUCCESS] Process '$pName' (PID $targetPid) was terminated!" -ForegroundColor Green
            Start-Sleep -Seconds 2
        } catch {
            Write-Host " [ERROR] Failed to kill process PID $targetPid: $($_.Exception.Message)" -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    } else {
        Write-Host " [!] Invalid PID entered." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }
}
