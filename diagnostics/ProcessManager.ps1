<#
.SYNOPSIS
    Fast Interactive Process Power Manager & Killer
.DESCRIPTION
    High-speed, low-latency process manager using direct .NET/Process APIs.
    Identifies high-resource applications, allows instant termination by PID,
    and monitors memory/CPU drain without WMI latency.
#>

$ScriptDir = Split-Path $PSScriptRoot -Parent
$cpuCount = [Environment]::ProcessorCount
$totalRamMB = 16384
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os -and $os.TotalVisibleMemorySize) { $totalRamMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 0) }
} catch {}

$sortMode = "CPU"
$statusMsg = ""

function Get-FastProcessTable {
    param([string]$Sort = "CPU")

    # Fast process snapshot
    $procs = [System.Diagnostics.Process]::GetProcesses()
    $rows = @()

    foreach ($p in $procs) {
        $pidNum = $p.Id
        if ($pidNum -le 4) { continue }

        try {
            $name = $p.ProcessName
            $memMb = [math]::Round($p.WorkingSet64 / 1MB, 1)
            $memPct = [math]::Round(($memMb / $totalRamMB) * 100, 1)
            
            # Approximate CPU from TotalProcessorTime
            $cpuPct = 0.0
            try {
                $cpuSec = $p.TotalProcessorTime.TotalSeconds
                # Relative indicator
                $cpuPct = [math]::Round($cpuSec, 1)
            } catch {}

            # Resource status tier
            $tier = "Normal"
            if ($memMb -ge 1000 -or $name -match "chrome|edge|python|node|blender|unreal|game") {
                $tier = "Elevated"
            }
            if ($memMb -ge 2000) {
                $tier = "High"
            }

            $rows += [PSCustomObject]@{
                PID       = $pidNum
                Name      = $name
                RAM_MB    = $memMb
                RAM_Pct   = $memPct
                CPUTime_s = $cpuPct
                Status    = $tier
            }
        } catch {}
    }

    if ($Sort -eq "RAM") {
        return $rows | Sort-Object RAM_MB -Descending | Select-Object -First 18
    } else {
        return $rows | Sort-Object CPUTime_s, RAM_MB -Descending | Select-Object -First 18
    }
}

while ($true) {
    Clear-Host
    $w = 88
    try {
        if ([Console]::WindowWidth -gt 1) {
            $w = [Console]::WindowWidth - 1
            if ($w -lt 35) { $w = 35 }
        }
    } catch { $w = 88 }

    Write-Host ("=" * $w) -ForegroundColor Cyan
    $title = "PROCESS MANAGER & RESORUCE KILLER"
    $spaces = [math]::Max(0, [math]::Floor(($w - $title.Length) / 2))
    $titleText = if ($title.Length -gt $w) { $title.Substring(0, $w) } else { (" " * $spaces) + $title }
    Write-Host $titleText -ForegroundColor Yellow
    Write-Host ("=" * $w) -ForegroundColor Cyan
    Write-Host " Total RAM: $totalRamMB MB  |  Logical Threads: $cpuCount  |  Sort: $sortMode" -ForegroundColor Gray

    if ($statusMsg) {
        Write-Host " [NOTICE] $statusMsg" -ForegroundColor Yellow
        $statusMsg = ""
    }
    Write-Host ""

    $table = Get-FastProcessTable -Sort $sortMode
    
    # Formatted Header
    $hdr = " {0,-7} | {1,-26} | {2,10} | {3,8} | {4,10} | {5,-10}" -f "PID", "APPLICATION NAME", "RAM (MB)", "RAM %", "CPU TIME", "STATUS"
    Write-Host $hdr -ForegroundColor Cyan
    Write-Host ("-" * [math]::Min($w, $hdr.Length + 2)) -ForegroundColor DarkGray

    foreach ($r in $table) {
        $tierCol = if ($r.Status -eq "High") { "Red" } elseif ($r.Status -eq "Elevated") { "Yellow" } else { "Green" }
        $line = " {0,-7} | {1,-26} | {2,10} | {3,7}% | {4,9}s | {5,-10}" -f $r.PID, $r.Name, $r.RAM_MB, $r.RAM_Pct, $r.CPUTime_s, $r.Status
        Write-Host $line -ForegroundColor $tierCol
    }

    Write-Host ""
    Write-Host ("-" * $w) -ForegroundColor Cyan
    Write-Host " Commands: [PID] Kill Process  |  [S] Toggle Sort ($sortMode)  |  [R / Enter] Refresh  |  [Q] Exit" -ForegroundColor Yellow
    Write-Host ("=" * $w) -ForegroundColor Cyan

    # Non-interactive check
    try {
        if ([Console]::IsInputRedirected) { return }
    } catch { return }

    $input = Read-Host " Enter Command or PID"
    $input = $input.Trim()

    if ($input -eq "" -or $input -eq "r" -or $input -eq "R") {
        continue
    }
    if ($input -eq "q" -or $input -eq "Q" -or $input -eq "0" -or $input -eq "exit") {
        break
    }
    if ($input -eq "s" -or $input -eq "S") {
        $sortMode = if ($sortMode -eq "CPU") { "RAM" } else { "CPU" }
        $statusMsg = "Sorted list by $sortMode."
        continue
    }

    if ($input -match '^\d+$') {
        $targetPid = [int]$input
        try {
            $targetProc = Get-Process -Id $targetPid -ErrorAction Stop
            $procName = $targetProc.ProcessName
            $confirm = Read-Host " Confirm terminate $procName (PID: $targetPid)? [y/N]"
            if ($confirm -match '^[yY]') {
                $targetProc.Kill()
                $statusMsg = "Successfully terminated $procName (PID: $targetPid)."
            } else {
                $statusMsg = "Kill operation cancelled."
            }
        } catch {
            $statusMsg = "Failed to terminate PID $($targetPid): $_"
        }
    } else {
        $statusMsg = "Invalid command. Enter a numeric PID or 'S' / 'Q'."
    }
}
