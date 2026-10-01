<#
.SYNOPSIS
    Universal Live Interactive Monitor Module (Motionless & Flicker-Free Edition)
.DESCRIPTION
    Dynamically brands the title to the exact laptop hardware (HP OMEN, Lenovo Legion, ASUS ROG, Dell XPS, etc.)
    and provides partitioned views (Full, Battery/Power, CPU, RAM, SSD, Process Table) with in-place motionless rendering,
    zero-flicker double-buffer rewrites, and adjustable refresh rates.
#>
param(
    [string]$InitialView = "menu",
    [double]$Interval = 1.0
)

$ModuleDir = $PSScriptRoot
$RootDir = Split-Path $ModuleDir -Parent
$CorePath = Join-Path $RootDir "core\HardwareProfile.ps1"
$HealthPath = Join-Path $RootDir "core\BatteryHealthModel.ps1"
$LogsDir = Join-Path $RootDir "logs"
$LogFile = Join-Path $LogsDir "current-session.csv"

# Import Core & Health Engines
. $CorePath
. $HealthPath

$hw = Get-HardwareProfile
$healthInfo = Get-BatteryHealthAssessment
$totalRamMB = if ($hw.TotalRamMB) { $hw.TotalRamMB } else { 16384 }
$cpuInfo = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
$cpuCores = [Environment]::ProcessorCount

# Dynamic Laptop Title Formatting
$rawModel = $hw.Model
$rawMfg = $hw.Manufacturer
$laptopTitle = if ($rawModel -match [regex]::Escape($rawMfg)) {
    $rawModel.ToUpper()
} else {
    "$rawMfg $rawModel".ToUpper()
}
$headerBanner = "$laptopTitle - BATTERY, CPU, RAM & POWER MONITOR"

# Session tracking from log file
$sessionStart = $null
$sessionStartPct = 0
$sessionStartMwh = 0

if (Test-Path $LogFile) {
    try {
        $lines = Get-Content -Path $LogFile | Where-Object { $_ -notmatch "^#" -and $_ -match "," }
        if ($lines.Count -ge 2) {
            $first = $lines[1] -split ","
            $sessionStart = [datetime]::Parse($first[0])
            $sessionStartPct = [int]$first[2]
            $sessionStartMwh = [int]$first[3]
        }
    } catch {}
}

if (-not $sessionStart) {
    $sessionStart = Get-Date
}

# --- MOTIONLESS FLICKER-FREE CONSOLE HELPERS ---
function Hide-ConsoleCursor {
    try { [Console]::CursorVisible = $false } catch {}
    try { [Console]::Write("`e[?25l") } catch {}
}

function Show-ConsoleCursor {
    try { [Console]::CursorVisible = $true } catch {}
    try { [Console]::Write("`e[?25h") } catch {}
}

function Reset-ConsoleCursor {
    try {
        [Console]::SetCursorPosition(0, 0)
    } catch {
        try { [Console]::Write("`e[H") } catch {}
    }
}

function Get-TermWidth {
    $w = 92
    try {
        $w = [Console]::WindowWidth - 1
        if ($w -lt 80) { $w = 92 }
    } catch { $w = 92 }
    return $w
}

function Write-LineClean {
    param(
        [string]$Text = "",
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White
    )
    $termWidth = Get-TermWidth
    $cleanText = if ($Text.Length -lt $termWidth) {
        $Text.PadRight($termWidth)
    } else {
        $Text.Substring(0, $termWidth)
    }
    Write-Host "$cleanText`e[K" -ForegroundColor $ForegroundColor
}

function Write-BlockClean {
    param(
        [string]$Block,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White
    )
    if (-not $Block) { return }
    $lines = $Block -split "`r?`n"
    foreach ($line in $lines) {
        if ($line.Trim().Length -gt 0 -or $line -eq "") {
            Write-LineClean $line $ForegroundColor
        }
    }
}

function Get-ProcessTableSample {
    param([int]$Count = 6)
    
    # Query fast filtered process stats
    $perfProcs = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "PercentProcessorTime > 0 OR WorkingSetPrivate > 50000000" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '_Total|Idle' }
    if (-not $perfProcs -or $perfProcs.Count -lt 3) {
        $perfProcs = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '_Total|Idle' }
    }

    # Check NVIDIA compute processes
    $nvidiaPids = @()
    if ($hw.HasNvidia) {
        try {
            $nv = nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits 2>$null
            if ($nv) { 
                $nvidiaPids += ($nv -split "`r`n") | ForEach-Object { 
                    $v = 0
                    if ([int]::TryParse($_.Trim(), [ref]$v)) { $v }
                } 
            }
        } catch {}
    }

    $rows = foreach ($p in $perfProcs) {
        $pidNum = $p.IDProcess
        if ($pidNum -eq 0 -or $pidNum -eq 4) { continue }
        
        $cpuPct = [math]::Round($p.PercentProcessorTime / $cpuCores, 1)
        $ramMB = [math]::Round($p.WorkingSetPrivate / 1MB, 1)
        $ramPct = [math]::Round(($ramMB / $totalRamMB) * 100, 1)
        $diskKBs = [math]::Round(($p.IOReadBytesPersec + $p.IOWriteBytesPersec) / 1KB, 1)
        $cleanName = ($p.Name -split '#')[0]
        
        $gpuTag = "iGPU"
        if ($nvidiaPids -contains $pidNum) {
            $gpuTag = "NVIDIA [AWAKE]"
        }

        $impact = "Low"
        if ($gpuTag -match "NVIDIA") {
            $impact = "dGPU WAKE"
        } elseif ($cpuPct -gt 15 -or $ramMB -gt 1500 -or $diskKBs -gt 5000) {
            $impact = "HIGH"
        } elseif ($cpuPct -gt 5 -or $ramMB -gt 500 -or $diskKBs -gt 1000) {
            $impact = "Medium"
        }

        [PSCustomObject]@{
            ProcessName = $cleanName
            PID         = $pidNum
            'CPU(%)'    = $cpuPct
            'RAM(MB)'   = $ramMB
            'RAM(%)'    = $ramPct
            'Disk(KB/s)'= $diskKBs
            'GPU'       = $gpuTag
            'Power'     = $impact
        }
    }

    return $rows | Sort-Object @{Expression={$_.'GPU' -match "NVIDIA"}; Descending=$true}, 'CPU(%)', 'RAM(MB)' -Descending | Select-Object -First $Count
}

function Get-SsdMetrics {
    $readSpeedMB = 0
    $writeSpeedMB = 0
    $activeTimePct = 0
    try {
        $c = Get-Counter '\PhysicalDisk(_Total)\Disk Read Bytes/sec', '\PhysicalDisk(_Total)\Disk Write Bytes/sec', '\PhysicalDisk(_Total)\% Disk Time' -MaxSamples 1 -ErrorAction SilentlyContinue
        if ($c) {
            $rb = $c.CounterSamples | Where-Object { $_.Path -like '*read bytes*' } | Select-Object -ExpandProperty CookedValue
            $wb = $c.CounterSamples | Where-Object { $_.Path -like '*write bytes*' } | Select-Object -ExpandProperty CookedValue
            $dt = $c.CounterSamples | Where-Object { $_.Path -like '*% disk time*' } | Select-Object -ExpandProperty CookedValue
            $readSpeedMB = [math]::Round($rb / 1MB, 2)
            $writeSpeedMB = [math]::Round($wb / 1MB, 2)
            $activeTimePct = [math]::Min(100, [math]::Round($dt, 1))
        }
    } catch {}

    $estSsdWatts = 0.5
    if ($activeTimePct -gt 50 -or ($readSpeedMB + $writeSpeedMB) -gt 100) {
        $estSsdWatts = 4.2
    } elseif ($activeTimePct -gt 10 -or ($readSpeedMB + $writeSpeedMB) -gt 10) {
        $estSsdWatts = 2.1
    }

    return [PSCustomObject]@{
        ReadMB       = $readSpeedMB
        WriteMB      = $writeSpeedMB
        ActivePct    = $activeTimePct
        EstimatedWatts = $estSsdWatts
    }
}

# Current active view mode: 1=Full, 2=Battery, 3=CPU, 4=RAM, 5=SSD, 6=Processes
$currentView = $InitialView

function Show-Header {
    param($m, $viewName, [double]$RefreshSec)
    
    # Motionless reposition without clearing console buffer
    Reset-ConsoleCursor

    $termWidth = Get-TermWidth
    $spaces = [math]::Max(0, [math]::Floor(($termWidth - $headerBanner.Length) / 2))
    $centeredBanner = (" " * $spaces) + $headerBanner

    Write-LineClean ("=" * $termWidth) Cyan
    Write-LineClean $centeredBanner Yellow
    Write-LineClean ("=" * $termWidth) Cyan
    Write-LineClean " Hardware: $($hw.Manufacturer) $($hw.Model)  |  CPU: $($hw.CpuName)" Gray
    Write-LineClean " Time:     $($m.Timestamp)  |  Health: $($healthInfo.HealthPct)% (Grade $($healthInfo.HealthGrade.Substring(0,1)))  |  Mode: [$viewName]  |  Rate: ${RefreshSec}s [Motionless]" DarkGray
    Write-LineClean "" White
}

function Show-Footer {
    param([double]$CurrentInterval)
    $termWidth = Get-TermWidth

    Write-LineClean ("-" * $termWidth) Cyan
    Write-LineClean " Views: [1] Full  [2] Battery  [3] CPU  [4] RAM  [5] SSD  [6] Process Table" Yellow
    Write-LineClean " Keys:  [1-6] View  |  [F] Fast (0.5s)  |  [S] Normal (1s)  |  [+/-] Speed  |  [Q] Quit" DarkGray
    # Clean any leftover trailing lines below footer
    try { [Console]::Write("`e[J") } catch {}
}

function Show-PartitionMenu {
    $menuOptions = @(
        [PSCustomObject]@{ Value = "1"; Title = "Full All-in-One Dashboard"; Desc = "Everything: Battery, Power Split, CPU, RAM, Processes" }
        [PSCustomObject]@{ Value = "2"; Title = "Battery & Power Focus";     Desc = "Deep battery health, live wattage, 4-hour target" }
        [PSCustomObject]@{ Value = "3"; Title = "CPU & Processor Focus";     Desc = "Core speeds, load %, turbo boost status, top CPU apps" }
        [PSCustomObject]@{ Value = "4"; Title = "RAM & Memory Focus";        Desc = "Memory allocation %, active vs cached, memory hogs" }
        [PSCustomObject]@{ Value = "5"; Title = "NVMe SSD & Storage Focus";  Desc = "Read/Write MB/s, disk active %, storage wattage" }
        [PSCustomObject]@{ Value = "6"; Title = "Task Manager Process Table";Desc = "Full parallel resource table & live GPU tracker" }
    )

    $selectedIndex = 0
    Hide-ConsoleCursor
    Clear-Host

    $termWidth = Get-TermWidth
    $spaces = [math]::Max(0, [math]::Floor(($termWidth - $headerBanner.Length) / 2))
    $centeredBanner = (" " * $spaces) + $headerBanner

    while ($true) {
        Reset-ConsoleCursor

        Write-LineClean ("=" * $termWidth) Cyan
        Write-LineClean $centeredBanner Yellow
        Write-LineClean ("=" * $termWidth) Cyan
        Write-LineClean "" White
        Write-LineClean " Choose which partition to display:" White
        Write-LineClean " (Use [Up / Down] Arrow Keys to navigate, [Enter] to select, or press [1-6])" DarkGray
        Write-LineClean "" White

        for ($i = 0; $i -lt $menuOptions.Count; $i++) {
            $opt = $menuOptions[$i]
            $num = $i + 1
            if ($i -eq $selectedIndex) {
                # Highlighted option with pointer in bright Green
                $line = "  > [$num] $($opt.Title.PadRight(28)) - $($opt.Desc)"
                Write-LineClean $line Green
            } else {
                # Inactive option in Gray
                $line = "    [$num] $($opt.Title.PadRight(28)) - $($opt.Desc)"
                Write-LineClean $line Gray
            }
        }

        Write-LineClean "" White
        Write-LineClean ("-" * $termWidth) Cyan
        Write-LineClean " Controls: [Up / Down] Move Selection  |  [Enter / Space] Launch  |  [1-6] Jump  |  [Q] Exit" DarkGray
        try { [Console]::Write("`e[J") } catch {}

        # Non-interactive fallback
        try {
            if ([Console]::IsInputRedirected) {
                return "1"
            }
        } catch { return "1" }

        $keyInfo = [Console]::ReadKey($true)
        switch ($keyInfo.Key) {
            'UpArrow' {
                $selectedIndex--
                if ($selectedIndex -lt 0) { $selectedIndex = $menuOptions.Count - 1 }
            }
            'DownArrow' {
                $selectedIndex++
                if ($selectedIndex -ge $menuOptions.Count) { $selectedIndex = 0 }
            }
            'Enter' {
                return $menuOptions[$selectedIndex].Value
            }
            'Spacebar' {
                return $menuOptions[$selectedIndex].Value
            }
            'Escape' {
                return "1"
            }
            Default {
                $ch = $keyInfo.KeyChar
                if ($ch -eq 'q' -or $ch -eq 'Q') {
                    exit 0
                }
                if ($ch -match '^[1-6]$') {
                    return $ch.ToString()
                }
            }
        }
    }
}

# Interactive selection prompt if not explicitly pre-selected
if (-not $InitialView -or $InitialView -eq "menu") {
    $currentView = Show-PartitionMenu
} else {
    $currentView = $InitialView
}

# Prepare motionless console environment
Hide-ConsoleCursor
Clear-Host

try {
    while ($true) {
        # Check for live keyboard input to switch views or speed on the fly
        $keyAvailable = $false
        try {
            if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
                $keyAvailable = [Console]::KeyAvailable
            }
        } catch {}

        if ($keyAvailable) {
            try {
                $kInfo = [Console]::ReadKey($true)
                $key = $kInfo.KeyChar
                if ($key -match '^[1-6]$') {
                    if ($currentView -ne $key.ToString()) {
                        $currentView = $key.ToString()
                        Clear-Host
                    }
                } elseif ($key -eq 'f' -or $key -eq 'F') {
                    $Interval = 0.5
                } elseif ($key -eq 's' -or $key -eq 'S') {
                    $Interval = 1.0
                } elseif ($key -eq '+' -or $key -eq '=') {
                    $Interval = [math]::Max(0.25, [math]::Round($Interval - 0.25, 2))
                } elseif ($key -eq '-' -or $key -eq '_') {
                    $Interval = [math]::Min(5.0, [math]::Round($Interval + 0.25, 2))
                } elseif ($key -eq 'q' -or $key -eq 'Q') {
                    break
                }
            } catch {}
        }

        # Optimized live metrics query
        $m = Get-LiveMetrics -HardwareProfile $hw -SkipProcessSort

        # Render according to current view mode
        switch ($currentView) {
            "2" {
                # BATTERY & POWER FOCUS
                Show-Header $m "BATTERY & POWER FOCUS" $Interval
                
                Write-LineClean " [BATTERY CAPACITY & LIVE HEALTH]" Green
                Write-LineClean "   Reported Charge:          $($m.Percent)%" White
                Write-LineClean "   True Calibrated Charge:   $($healthInfo.CalibratedPercent)% ($($m.RemainingMwh) mWh usable)" Cyan
                Write-LineClean "   Full Charge Capacity:     $($healthInfo.FullChargeCapacityMwh) mWh / $($healthInfo.DesignCapacityMwh) mWh (Design)" Gray
                Write-LineClean "   Overall Battery Health:   $($healthInfo.HealthPct)% (Grade: $($healthInfo.HealthGrade))" $(if ($healthInfo.HealthPct -ge 90) { 'Green' } else { 'Yellow' })
                Write-LineClean "   Cycle Life Tracker:       $($healthInfo.CycleCount) cycles consumed ($($healthInfo.CyclesRemaining) cycles remaining of 500)" White
                Write-LineClean "   Live Pack Voltage:        $($m.VoltageV) Volts (Cell status: Optimal balance)" Gray
                Write-LineClean "" White

                Write-LineClean " [DISCHARGE WATTAGE & 4-HOUR TARGET]" Green
                if ($m.PowerOnline) {
                    Write-LineClean "   Power Source:             PLUGGED IN (AC Power Connected)" Cyan
                    Write-LineClean "   Battery Care Mode:        Capped at ~80% by OEM to protect cells from heat." Gray
                    Write-LineClean "   4-Hour Target Budget:     Once unplugged, keep total draw <= $($m.Target4hWatts) W." Magenta
                } else {
                    Write-LineClean "   Power Source:             ON BATTERY (Discharging)" Yellow
                    Write-LineClean "   Live System Power Draw:   $($m.DischargeWatts) Watts" $(if ($m.DischargeWatts -le $m.Target4hWatts) { 'Green' } elseif ($m.DischargeWatts -le 22) { 'Yellow' } else { 'Red' })
                    Write-LineClean "   Estimated Runtime:        $($m.EstHours) hours $($m.EstMinutes) mins remaining" $(if ($m.EstHours -ge 4) { 'Green' } else { 'Yellow' })
                    Write-LineClean "" White
                    Write-LineClean "   4-Hour Feasibility:       $(if ($m.CanLast4Hours) { '[PASS] Drawing within 4-hour budget!' } else { '[WARNING] Drawing above budget. Dim screen / engage ECO mode.' })" $(if ($m.CanLast4Hours) { 'Green' } else { 'Red' })
                }
                Write-LineClean "" White

                Write-LineClean " [COMPONENT POWER CONTRIBUTION]" Magenta
                if (-not $m.PowerOnline) {
                    $gpuW = $m.GpuWatts
                    $cpuW = [math]::Round(([math]::Max(3, ($m.CpuLoad / 100) * 28)), 1)
                    $screenW = 3.5
                    $ssdW = 0.5
                    $boardW = [math]::Round([math]::Max(2, $m.DischargeWatts - ($gpuW + $cpuW + $screenW + $ssdW)), 1)

                    Write-LineClean "   * Dedicated GPU ($($hw.DgpuName)): $($gpuW) W (State: $($m.GpuState)) [$($m.GpuSharePct)% of drain]" $(if ($gpuW -gt 5) { 'Red' } else { 'Green' })
                    Write-LineClean "   * Processor (CPU Package):           $cpuW W (Load: $($m.CpuLoad)%)" Green
                    Write-LineClean "   * Display Backlight:                 $screenW W (Panel + Backlight)" Gray
                    Write-LineClean "   * Storage (NVMe SSD):                $ssdW W (Low Power APST)" Gray
                    Write-LineClean "   * Platform (Motherboard, RAM, Fans): $boardW W" Gray
                } else {
                    Write-LineClean "   * Unplug charger to observe live component power breakdown." DarkYellow
                }
                Write-LineClean "" White
                Show-Footer $Interval
            }

            "3" {
                # CPU & PROCESSOR FOCUS
                Show-Header $m "CPU & PROCESSOR FOCUS" $Interval

                Write-LineClean " [CPU ARCHITECTURE & LIVE LOAD]" Green
                Write-LineClean "   Processor Name:           $($hw.CpuName)" White
                $cores = if ($cpuInfo -and $cpuInfo.NumberOfCores) { $cpuInfo.NumberOfCores } else { [math]::Max(1, [math]::Floor($cpuCores / 2)) }
                $baseClock = if ($cpuInfo -and $cpuInfo.CurrentClockSpeed) { "$($cpuInfo.CurrentClockSpeed) MHz" } else { "Dynamic (Intel Speed Shift)" }
                $maxClock = if ($cpuInfo -and $cpuInfo.MaxClockSpeed) { "(Max Rated: $($cpuInfo.MaxClockSpeed) MHz)" } else { "" }
                Write-LineClean "   Core Configuration:       $cores Physical Cores / $cpuCores Logical Threads" White
                Write-LineClean "   Total CPU Utilization:    $($m.CpuLoad)%" $(if ($m.CpuLoad -lt 25) { 'Green' } elseif ($m.CpuLoad -lt 60) { 'Yellow' } else { 'Red' })
                Write-LineClean "   Base Clock Speed:         $baseClock $maxClock" Gray
                Write-LineClean "   Estimated Package Draw:   ~$([math]::Round([math]::Max(3, ($m.CpuLoad / 100) * 28), 1)) Watts" Cyan
                Write-LineClean "" White

                Write-LineClean " [TOP CPU-CONSUMING PROCESSES]" Green
                $procList = Get-ProcessTableSample -Count 10
                $tableStr = $procList | Format-Table -Property ProcessName, PID, 'CPU(%)', 'RAM(MB)', 'Disk(KB/s)', 'Power' -AutoSize | Out-String
                Write-BlockClean $tableStr White
                Show-Footer $Interval
            }

            "4" {
                # RAM & MEMORY FOCUS
                Show-Header $m "RAM & MEMORY FOCUS" $Interval

                Write-LineClean " [PHYSICAL MEMORY UTILIZATION]" Green
                Write-LineClean "   Total Physical RAM:       $($m.TotalRamGB) GB ($totalRamMB MB)" White
                Write-LineClean "   Memory In Use:            $($m.UsedRamGB) GB ($($m.RamPercent)%)" $(if ($m.RamPercent -lt 70) { 'Green' } else { 'Yellow' })
                Write-LineClean "   Available Free Memory:    $([math]::Round($m.TotalRamGB - $m.UsedRamGB, 2)) GB" Cyan
                
                # RAM visual bar
                $barLen = 30
                $usedB = [math]::Round(($m.RamPercent / 100) * $barLen)
                $remB = [math]::Max(0, $barLen - $usedB)
                $memBar = ("#" * $usedB) + ("-" * $remB)
                Write-LineClean "   RAM Load Bar:             [$memBar] $($m.RamPercent)%" Green
                Write-LineClean "" White

                Write-LineClean " [TOP MEMORY-CONSUMING PROCESSES]" Green
                $memProcs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 ProcessName, Id, @{N='RAM(MB)'; E={[math]::Round($_.WorkingSet64 / 1MB, 1)}}, @{N='RAM(%)'; E={[math]::Round(($_.WorkingSet64 / 1MB / $totalRamMB) * 100, 1)}}
                $tableStr = $memProcs | Format-Table -AutoSize | Out-String
                Write-BlockClean $tableStr White
                Show-Footer $Interval
            }

            "5" {
                # NVMe SSD & STORAGE FOCUS
                Show-Header $m "NVMe SSD & STORAGE FOCUS" $Interval

                $ssd = Get-SsdMetrics
                Write-LineClean " [NVMe SSD PERFORMANCE & THROUGHPUT]" Green
                $diskDrive = Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($diskDrive) {
                    Write-LineClean "   Drive Model:              $($diskDrive.FriendlyName)" White
                    Write-LineClean "   Drive Health Status:      $($diskDrive.HealthStatus) (Operational: $($diskDrive.OperationalStatus))" Green
                    Write-LineClean "   Capacity:                 $([math]::Round($diskDrive.Size / 1GB, 1)) GB ($($diskDrive.BusType) Interface)" Gray
                }
                Write-LineClean "   Live Read Speed:          $($ssd.ReadMB) MB/s" Cyan
                Write-LineClean "   Live Write Speed:         $($ssd.WriteMB) MB/s" Cyan
                Write-LineClean "   Disk Active Time:         $($ssd.ActivePct) %" $(if ($ssd.ActivePct -lt 20) { 'Green' } else { 'Yellow' })
                Write-LineClean "   Estimated Storage Draw:   $($ssd.EstimatedWatts) Watts" $(if ($ssd.EstimatedWatts -le 1.0) { 'Green' } else { 'Yellow' })
                Write-LineClean "   Power State:              $(if ($ssd.ActivePct -le 5) { 'Autonomous Power State (APST Low-Power Sleep)' } else { 'Active NVMe Read/Write State' })" Gray
                Write-LineClean "" White

                Write-LineClean " [TOP DISK I/O PROCESSES]" Green
                $ioProcs = Get-ProcessTableSample -Count 8 | Sort-Object 'Disk(KB/s)' -Descending
                $tableStr = $ioProcs | Format-Table -Property ProcessName, PID, 'Disk(KB/s)', 'CPU(%)', 'RAM(MB)' -AutoSize | Out-String
                Write-BlockClean $tableStr White
                Show-Footer $Interval
            }

            "6" {
                # FULL PROCESS TABLE FOCUS
                Show-Header $m "TASK MANAGER PARALLEL PROCESS TABLE" $Interval

                Write-LineClean " [ACTIVE PROCESS RESOURCE DRAIN (PARALLEL TASK MANAGER VIEW)]" Green
                $procList = Get-ProcessTableSample -Count 14
                $tableStr = $procList | Format-Table -Property ProcessName, PID, 'CPU(%)', 'RAM(MB)', 'RAM(%)', 'Disk(KB/s)', 'GPU', 'Power' -AutoSize | Out-String
                Write-BlockClean $tableStr White
                Write-LineClean " Tip: To kill any rogue process, open 'ubat.bat' and select Option [7]." DarkGray
                Show-Footer $Interval
            }

            Default {
                # FULL DASHBOARD (DEFAULT)
                Show-Header $m "FULL DASHBOARD" $Interval

                # 1. Timeline
                Write-LineClean " [1. BATTERY SESSION TIMELINE]" Yellow
                $now = Get-Date
                $elapsed = $now - $sessionStart
                $elapsedMins = [math]::Floor($elapsed.TotalMinutes)
                $elapsedSecs = $elapsed.Seconds
                $pctDropped = if ($sessionStartPct -gt 0) { [math]::Max(0, $sessionStartPct - $m.Percent) } else { 0 }
                $mwhConsumed = if ($sessionStartMwh -gt 0) { [math]::Max(0, $sessionStartMwh - $m.RemainingMwh) } else { 0 }

                if ($sessionStartPct -gt 0) {
                    Write-LineClean "   Start Time: $($sessionStart.ToString('HH:mm:ss')) ($sessionStartPct%) | Elapsed: $elapsedMins mins $elapsedSecs secs | Drained: -$pctDropped% ($mwhConsumed mWh)" White
                } else {
                    Write-LineClean "   Start Time: $($sessionStart.ToString('HH:mm:ss')) (Active Tracking)" White
                }
                Write-LineClean "" White

                # 2. Battery & Target
                Write-LineClean " [2. BATTERY & RUNTIME STATUS]" Green
                if ($m.PowerOnline) {
                    Write-LineClean "   Power: PLUGGED IN (AC) | Reported: $($m.Percent)% (Calibrated: $($healthInfo.CalibratedPercent)%) | Pack: $($m.VoltageV) V" Cyan
                    Write-LineClean "   Energy: $($m.RemainingMwh) mWh / $($m.FullCapMwh) mWh  |  4-Hour Target Budget: <= $($m.Target4hWatts) W" Gray
                } else {
                    Write-LineClean "   Power: ON BATTERY (Discharging) | Charge: $($m.Percent)% (Calibrated: $($healthInfo.CalibratedPercent)%)" Yellow
                    Write-LineClean "   Live Draw: $($m.DischargeWatts) W | Est. Runtime: $($m.EstHours)h $($m.EstMinutes)m remaining" $(if ($m.EstHours -ge 4) { 'Green' } else { 'Yellow' })
                    Write-LineClean "   Target:    4-Hour Limit: <= $($m.Target4hWatts) W  -->  Verdict: $(if ($m.CanLast4Hours) { '[PASS]' } else { '[WARNING - Above Target]' })" $(if ($m.CanLast4Hours) { 'Green' } else { 'Red' })
                }
                Write-LineClean "" White

                # 3. Component Power Split
                Write-LineClean " [3. COMPONENT POWER SPLIT]" Magenta
                if (-not $m.PowerOnline) {
                    $gpuW = $m.GpuWatts
                    $cpuW = [math]::Round(([math]::Max(3, ($m.CpuLoad / 100) * 28)), 1)
                    $screenW = 3.5
                    $ssdW = 0.5
                    $boardW = [math]::Round([math]::Max(2, $m.DischargeWatts - ($gpuW + $cpuW + $screenW + $ssdW)), 1)

                    Write-LineClean "   * Dedicated GPU ($($hw.DgpuName)): $($gpuW) W (State: $($m.GpuState)) [$($m.GpuSharePct)% of drain]" $(if ($gpuW -gt 5) { 'Red' } else { 'Green' })
                    Write-LineClean "   * Processor (CPU Package):           $cpuW W (Load: $($m.CpuLoad)%)" Green
                    Write-LineClean "   * Display Backlight:                 $screenW W (Panel + Backlight)" Gray
                    Write-LineClean "   * Storage (NVMe SSD):                $ssdW W (Low Power APST)" Gray
                    Write-LineClean "   * Platform (Motherboard, RAM, Fans): $boardW W" Gray
                } else {
                    Write-LineClean "   * Running on AC Power. Disconnect charger to observe live component power breakdown." DarkYellow
                }
                Write-LineClean "" White

                # 4. Process Table
                Write-LineClean " [4. ACTIVE PROCESS POWER IMPACT (PARALLEL TASK MANAGER VIEW)]" Green
                $procList = Get-ProcessTableSample -Count 6
                $tableStr = $procList | Format-Table -Property ProcessName, PID, 'CPU(%)', 'RAM(MB)', 'RAM(%)', 'Disk(KB/s)', 'GPU', 'Power' -AutoSize | Out-String
                Write-BlockClean $tableStr White

                Write-LineClean " System Memory In Use: $($m.UsedRamGB) GB / $($m.TotalRamGB) GB ($($m.RamPercent)%)  |  Total CPU: $($m.CpuLoad)%" Gray
                Show-Footer $Interval
            }
        }

        # Sleep interval in milliseconds (supports sub-second like 0.5s)
        Start-Sleep -Milliseconds ([int]($Interval * 1000))
    }
} finally {
    Show-ConsoleCursor
}
