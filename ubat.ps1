<#
.SYNOPSIS
    OMNI - Master System Hardware & Optimization Suite
.DESCRIPTION
    Hierarchical modular interactive menu supporting seamless arrow-key navigation (Up/Down),
    sub-menu hubs ("option inside an option" & "all option in one option"), and zero-flicker rendering.
#>

$ScriptDir = $PSScriptRoot
$CoreDir = Join-Path $ScriptDir "core"
$HwPath = Join-Path $CoreDir "HardwareProfile.ps1"
$HelpersPath = Join-Path $CoreDir "ConsoleHelpers.ps1"

. $HwPath
. $HelpersPath
$hw = Get-HardwareProfile

# Dynamic laptop banner
$rawModel = $hw.Model
$rawMfg = $hw.Manufacturer
$laptopTitle = if ($rawModel -match [regex]::Escape($rawMfg)) {
    $rawModel.ToUpper()
} else {
    "$rawMfg $rawModel".ToUpper()
}
$bannerTitle = "OMNI HARDWARE TELEMETRY & SYSTEM MONITOR - $laptopTitle"

# Console helper functions are provided by core\ConsoleHelpers.ps1 (dot-sourced above)

function Format-MenuOptionLine {
    param(
        [object]$Option,
        [bool]$IsSelected,
        [int]$TermWidth
    )
    $prefix = if ($IsSelected) { "  > [$($Option.Key)] " } else { "    [$($Option.Key)] " }
    $avail = $TermWidth - $prefix.Length
    if ($avail -le 20) {
        return "$prefix$($Option.Title)"
    }
    if ($avail -lt 55) {
        $title = $Option.Title
        $rem = $avail - $title.Length - 3
        if ($rem -gt 8) {
            $desc = if ($Option.Desc.Length -gt $rem) { $Option.Desc.Substring(0, $rem - 3) + "..." } else { $Option.Desc }
            return "$prefix$title - $desc"
        } else {
            return "$prefix$title"
        }
    } else {
        $pad = [math]::Min(28, [math]::Max(18, [int]($avail * 0.32)))
        $rem = $avail - $pad - 3
        $desc = if ($Option.Desc.Length -gt $rem) { $Option.Desc.Substring(0, [math]::Max(0, $rem - 3)) + "..." } else { $Option.Desc }
        return "$prefix$($Option.Title.PadRight($pad)) - $desc"
    }
}

function Show-SubMenu {
    param(
        [string]$HubTitle,
        [array]$Options
    )

    $subIndex = 0
    $lastWidth = 0
    $lastHeight = 0

    while ($true) {
        Hide-Cursor
        $termWidth = Get-Width
        $termHeight = try { [Console]::WindowHeight } catch { 25 }
        $lastWidth = $termWidth
        $lastHeight = $termHeight
        try { Clear-Host } catch {}

        $exitSub = $false
        $chosenSubKey = $null

        while (-not $exitSub) {
            $curW = Get-Width
            $curH = try { [Console]::WindowHeight } catch { 25 }
            if ($curW -ne $lastWidth -or $curH -ne $lastHeight) {
                $termWidth = $curW
                $termHeight = $curH
                $lastWidth = $curW
                $lastHeight = $curH
                try { Clear-Host } catch {}
            }

            Reset-Cursor
            Write-LineClean ("=" * $termWidth) Cyan
            $spaces = [math]::Max(0, [math]::Floor(($termWidth - $HubTitle.Length) / 2))
            $bannerText = if ($HubTitle.Length -gt $termWidth) { $HubTitle.Substring(0, $termWidth) } else { (" " * $spaces) + $HubTitle }
            Write-LineClean $bannerText Yellow
            Write-LineClean ("=" * $termWidth) Cyan
            Write-LineClean " Choose a sub-module to execute:" White
            Write-LineClean " (Use [Up / Down] Arrow Keys to navigate, [Enter] to select, or tap [0-9])" DarkGray
            Write-LineClean "" White

            for ($i = 0; $i -lt $Options.Count; $i++) {
                $opt = $Options[$i]
                $line = Format-MenuOptionLine -Option $opt -IsSelected ($i -eq $subIndex) -TermWidth $termWidth
                if ($i -eq $subIndex) {
                    Write-LineClean $line Green
                } else {
                    Write-LineClean $line Gray
                }
            }

            Write-LineClean "" White
            Write-LineClean ("-" * $termWidth) Cyan
            Write-LineClean " Controls: [Up / Down] Navigate  |  [Enter] Select  |  [0 / Esc] Return" DarkGray
            try { [Console]::Write("`e[J") } catch {}

            try {
                if ([Console]::IsInputRedirected) { return $null }
            } catch { return $null }

            # Live responsive polling (detects zoom in / zoom out while sitting on menu)
            while (-not [Console]::KeyAvailable) {
                $checkW = Get-Width
                $checkH = try { [Console]::WindowHeight } catch { 25 }
                if ($checkW -ne $lastWidth -or $checkH -ne $lastHeight) {
                    break
                }
                Start-Sleep -Milliseconds 50
            }

            if (-not [Console]::KeyAvailable) {
                continue
            }

            $kInfo = [Console]::ReadKey($true)
            switch ($kInfo.Key) {
                'UpArrow' {
                    $subIndex--
                    if ($subIndex -lt 0) { $subIndex = $Options.Count - 1 }
                }
                'DownArrow' {
                    $subIndex++
                    if ($subIndex -ge $Options.Count) { $subIndex = 0 }
                }
                'Enter' {
                    $chosenSubKey = $Options[$subIndex].Key
                    $exitSub = $true
                }
                'Spacebar' {
                    $chosenSubKey = $Options[$subIndex].Key
                    $exitSub = $true
                }
                'Escape' {
                    return "0"
                }
                Default {
                    $ch = $kInfo.KeyChar
                    if ($ch -eq '0' -or $ch -eq 'q' -or $ch -eq 'Q') {
                        return "0"
                    } elseif ($ch -match '^[1-9]$') {
                        $matched = $Options | Where-Object { $_.Key -eq $ch.ToString() }
                        if ($matched) {
                            return $matched.Key
                        }
                    }
                }
            }
        }

        Show-Cursor
        return $chosenSubKey
    }
}

function Invoke-AutoResizeCalibrator {
    Hide-Cursor
    $lastW = 0
    $lastH = 0
    $redrawCount = 0
    $statusNotice = "Calibrator Engine Initialized. Listening for live zoom/resize events..."

    while ($true) {
        $curW = Get-Width
        $curH = try { [Console]::WindowHeight } catch { 25 }

        if ($curW -ne $lastW -or $curH -ne $lastH) {
            $redrawCount++
            $zoomMode = if ($curW -lt 60) {
                "[HIGH ZOOM / MAGNIFIED] Compact Layout"
            } elseif ($curW -lt 85) {
                "[STANDARD ZOOM] Balanced Alignment"
            } elseif ($curW -lt 120) {
                "[EXPANDED / COMFORT] High Headroom"
            } else {
                "[ULTRA-WIDE CANVAS] Max Columns"
            }
            if ($lastW -gt 0) {
                $statusNotice = "[ZOOM / RESIZE DETECTED] Adapted from $lastW to $curW cols ($zoomMode)"
            }
            $lastW = $curW
            $lastH = $curH
            try { Clear-Host } catch {}
        }

        Reset-Cursor
        $termWidth = $lastW

        # Header Banner
        $titleStr = "DYNAMIC AUTO-RESIZE & LAYOUT CALIBRATOR (RACES)"
        $spaces = [math]::Max(0, [math]::Floor(($termWidth - $titleStr.Length) / 2))
        $bannerText = if ($titleStr.Length -gt $termWidth) { $titleStr.Substring(0, $termWidth) } else { (" " * $spaces) + $titleStr }

        Write-LineClean ("=" * $termWidth) Cyan
        Write-LineClean $bannerText Yellow
        Write-LineClean ("=" * $termWidth) Cyan

        $zoomModeDesc = if ($termWidth -lt 60) { "Magnified / Zoomed-In" } elseif ($termWidth -lt 85) { "Standard / Normal" } else { "Expanded / Zoomed-Out" }
        Write-LineClean " Console Metrics : Width: $termWidth cols | Height: $lastH rows | Mode: $zoomModeDesc" White
        Write-LineClean " Live Event Notice : $statusNotice" Gray
        Write-LineClean ("-" * $termWidth) DarkGray
        Write-LineClean " RESPONSIVE 10-ALERT SYSTEM STATUS & LAYOUT VERIFICATION:" Yellow
        Write-LineClean "" White

        # 10 Responsive Demo Elements (live layout preview - uses real hw info where available)
        $cpuTempC = if ($hw.CpuTempC -gt 0) { $hw.CpuTempC } else { 48 }
        $cpuTempPct = [math]::Min(100, [int]($cpuTempC))
        $ssdWearPct = if ($hw.DiskWearPct -ge 0) { $hw.DiskWearPct } else { 0 }
        $battHealthPct = if ($hw.HealthPct -gt 0) { [int]$hw.HealthPct } else { 96 }
        $cpuStr = if ($hw.CpuName) { $hw.CpuName.Substring(0, [math]::Min(22, $hw.CpuName.Length)) } else { "CPU" }
        $diskStr = if ($hw.DiskModel) { $hw.DiskModel.Substring(0, [math]::Min(22, $hw.DiskModel.Length)) } else { "NVMe SSD" }
        $gpuStr = if ($hw.DgpuName) { $hw.DgpuName.Substring(0, [math]::Min(15, $hw.DgpuName.Length)) } else { "GPU" }
        $ramStr = "$($hw.TotalRamGB) GB @ $($hw.RamSpeedMTs) MT/s"
        $alerts = @(
            @{ Id = "01"; Subsys = "ACPI THERMALS  "; Status = "NOMINAL"; Val = "$cpuTempC C (ACPI Zone)"; Pct = $cpuTempPct }
            @{ Id = "02"; Subsys = "CPU ENGINE     "; Status = "ACTIVE "; Val = "$cpuStr"; Pct = 80 }
            @{ Id = "03"; Subsys = "DEDICATED GPU  "; Status = "ACTIVE "; Val = "$gpuStr"; Pct = 100 }
            @{ Id = "04"; Subsys = "SYSTEM MEMORY  "; Status = "LOADED "; Val = $ramStr; Pct = 75 }
            @{ Id = "05"; Subsys = "NVMe SSD WEAR  "; Status = "HEALTHY"; Val = "$ssdWearPct% Wear ($diskStr)"; Pct = 100 - $ssdWearPct }
            @{ Id = "06"; Subsys = "BATTERY HEALTH "; Status = "OPTIMAL"; Val = "$battHealthPct% Capacity Remaining"; Pct = $battHealthPct }
            @{ Id = "07"; Subsys = "PCIe NATIVE ASPM";Status = "LOCKED "; Val = "DisableNativeAspm = 1"; Pct = 100 }
            @{ Id = "08"; Subsys = "DRIVER WudfRd  "; Status = "SYSTEM "; Val = "Start Type 1 (Verified)"; Pct = 100 }
            @{ Id = "09"; Subsys = "BUFFER AUTO-FIT"; Status = "SYNCED "; Val = "Edge No-Wrap Guard Active"; Pct = 100 }
            @{ Id = "10"; Subsys = "LIVE ZOOM TRACK"; Status = "LOCKED "; Val = "Auto-Layout Refresh Engine"; Pct = 100 }
        )

        foreach ($a in $alerts) {
            if ($termWidth -ge 95) {
                $barW = 12
                $filled = [int](($a.Pct / 100.0) * $barW)
                $bar = "[" + ("=" * $filled) + (" " * ($barW - $filled)) + "]"
                $line = "  [$($a.Id)] $($a.Subsys) : $bar [$($a.Status)] $($a.Val)"
            } elseif ($termWidth -ge 70) {
                $barW = 6
                $filled = [int](($a.Pct / 100.0) * $barW)
                $bar = "[" + ("=" * $filled) + (" " * ($barW - $filled)) + "]"
                $line = "  [$($a.Id)] $($a.Subsys.Trim()) $bar [$($a.Status)] $($a.Val)"
            } elseif ($termWidth -ge 50) {
                $line = "  [$($a.Id)] $($a.Subsys.Trim()): [$($a.Status)] $($a.Val)"
            } else {
                $line = "  [$($a.Id)] $($a.Status): $($a.Subsys.Trim())"
            }
            if ($line.Length -gt $termWidth) {
                $line = $line.Substring(0, $termWidth)
            }
            Write-LineClean $line $(if ($a.Status -in "NOMINAL","HEALTHY","SYNCED","LOCKED","OPTIMAL","PEAK") { 'Green' } else { 'Cyan' })
        }

        Write-LineClean "" White
        Write-LineClean ("-" * $termWidth) Cyan
        Write-LineClean " Live Zoom Test: Press [Ctrl + / Wheel Up] or [Ctrl - / Wheel Down] to test auto-resize!" Yellow
        Write-LineClean " Controls      : [R] Force Redraw  |  [0 / Esc / Q] Return to Main Menu" DarkGray
        try { [Console]::Write("`e[J") } catch {}

        try {
            if ([Console]::IsInputRedirected) { Show-Cursor; return }
        } catch { Show-Cursor; return }

        # Non-blocking poll loop detecting zoom events in real time (every 40ms)
        $keyAvail = $false
        try { $keyAvail = [Console]::KeyAvailable } catch { Show-Cursor; return }
        while (-not $keyAvail) {
            $testW = Get-Width
            $testH = try { [Console]::WindowHeight } catch { 25 }
            if ($testW -ne $lastW -or $testH -ne $lastH) {
                break
            }
            Start-Sleep -Milliseconds 40
            try { $keyAvail = [Console]::KeyAvailable } catch { Show-Cursor; return }
        }

        if (-not $keyAvail) {
            continue
        }

        $k = [Console]::ReadKey($true)
        switch ($k.Key) {
            'Escape' { Show-Cursor; return }
            Default {
                $ch = $k.KeyChar
                if ($ch -in '0','q','Q') { Show-Cursor; return }
                if ($ch -in 'r','R') {
                    $lastW = 0
                    $statusNotice = "[MANUAL RE-ALIGNMENT TRIGGERED] Redrawn to $curW cols"
                }
            }
        }
    }
}

$mainOptions = @(
    [PSCustomObject]@{ Key = "1"; Title = "Live System Monitor";          Desc = "All-in-One real-time terminal telemetry engine" }
    [PSCustomObject]@{ Key = "2"; Title = "Storage & SSD Hub";            Desc = "Partitions, file systems, SMART wear & SSD TRIM optimizer" }
    [PSCustomObject]@{ Key = "3"; Title = "Battery & Health Hub";         Desc = "Calibrated health %, wear level, cycle count & battery tuner" }
    [PSCustomObject]@{ Key = "4"; Title = "CPU & Memory Hub";             Desc = "Multi-thread core loads, RAM volume & frequency limits" }
    [PSCustomObject]@{ Key = "5"; Title = "Process Manager Hub";          Desc = "Fast resource monitor & interactive PID killer" }
    [PSCustomObject]@{ Key = "6"; Title = "Session Logs & Reports";       Desc = "In-terminal session logs, analysis reports & folder access" }
    [PSCustomObject]@{ Key = "7"; Title = "Benchmark & Stress Testing Hub";Desc = "NVMe read, CPU/GPU/RAM burn-in stress tests & bandwidth" }
    [PSCustomObject]@{ Key = "0"; Title = "Exit";                         Desc = "Exit OMNI toolkit" }
)

$selectedIndex = 0
$lastMenuWidth = 0
$lastMenuHeight = 0

while ($true) {
    Hide-Cursor
    $termWidth = Get-Width
    $termHeight = try { [Console]::WindowHeight } catch { 25 }
    $lastMenuWidth = $termWidth
    $lastMenuHeight = $termHeight
    try { Clear-Host } catch {}

    $exitMenu = $false

    while (-not $exitMenu) {
        $curW = Get-Width
        $curH = try { [Console]::WindowHeight } catch { 25 }
        if ($curW -ne $lastMenuWidth -or $curH -ne $lastMenuHeight) {
            $termWidth = $curW
            $termHeight = $curH
            $lastMenuWidth = $curW
            $lastMenuHeight = $curH
            try { Clear-Host } catch {}
        }

        Reset-Cursor
        $spaces = [math]::Max(0, [math]::Floor(($termWidth - $bannerTitle.Length) / 2))
        $centeredBanner = if ($bannerTitle.Length -gt $termWidth) { $bannerTitle.Substring(0, $termWidth) } else { (" " * $spaces) + $bannerTitle }

        Write-LineClean ("=" * $termWidth) Cyan
        Write-LineClean $centeredBanner Yellow
        Write-LineClean ("=" * $termWidth) Cyan
        Write-LineClean " Hardware: $($hw.Manufacturer) $($hw.Model)  |  CPU: $($hw.CpuName)" Gray
        Write-LineClean "" White
        Write-LineClean " Choose a hardware subsystem to inspect:" White
        Write-LineClean " (Use [Up / Down] Arrow Keys to navigate, [Enter] to select, or tap [0-7])" DarkGray
        Write-LineClean "" White

        for ($i = 0; $i -lt $mainOptions.Count; $i++) {
            $opt = $mainOptions[$i]
            $line = Format-MenuOptionLine -Option $opt -IsSelected ($i -eq $selectedIndex) -TermWidth $termWidth
            if ($i -eq $selectedIndex) {
                Write-LineClean $line Green
            } else {
                Write-LineClean $line Gray
            }
        }

        Write-LineClean "" White
        Write-LineClean ("-" * $termWidth) Cyan
        Write-LineClean " Controls: [Up / Down] Move Selection  |  [Enter / Space] Select  |  [0-7] Quick Jump  |  [Q] Exit" DarkGray
        try { [Console]::Write("`e[J") } catch {}

        try {
            if ([Console]::IsInputRedirected) {
                return
            }
        } catch { return }

        # Live responsive polling (detects zoom in / zoom out while sitting on menu)
        while (-not [Console]::KeyAvailable) {
            $checkW = Get-Width
            $checkH = try { [Console]::WindowHeight } catch { 25 }
            if ($checkW -ne $lastMenuWidth -or $checkH -ne $lastMenuHeight) {
                break
            }
            Start-Sleep -Milliseconds 50
        }

        if (-not [Console]::KeyAvailable) {
            continue
        }

        $keyInfo = [Console]::ReadKey($true)
        $chosenKey = $null

        switch ($keyInfo.Key) {
            'UpArrow' {
                $selectedIndex--
                if ($selectedIndex -lt 0) { $selectedIndex = $mainOptions.Count - 1 }
            }
            'DownArrow' {
                $selectedIndex++
                if ($selectedIndex -ge $mainOptions.Count) { $selectedIndex = 0 }
            }
            'Enter' {
                $chosenKey = $mainOptions[$selectedIndex].Key
                $exitMenu = $true
            }
            'Spacebar' {
                $chosenKey = $mainOptions[$selectedIndex].Key
                $exitMenu = $true
            }
            'Escape' {
                $chosenKey = "0"
                $exitMenu = $true
            }
            Default {
                $ch = $keyInfo.KeyChar
                if ($ch -eq 'q' -or $ch -eq 'Q') {
                    $chosenKey = "0"
                    $exitMenu = $true
                } elseif ($ch -match '^[0-7]$') {
                    $matchedOpt = $mainOptions | Where-Object { $_.Key -eq $ch.ToString() }
                    if ($matchedOpt) {
                        $chosenKey = $matchedOpt.Key
                        $exitMenu = $true
                    }
                }
            }
        }
    }

    Show-Cursor
    Clear-Host

    switch ($chosenKey) {
        "1" {
            # Live All-in-One Monitor
            $tuiPath = Join-Path $ScriptDir "tui\ubat_tui.py"
            if (Get-Command python -ErrorAction SilentlyContinue) {
                # Pre-flight check for rich & psutil dependencies
                python -c "import sys, rich, psutil; sys.exit(0)" 2>$null
                if ($LASTEXITCODE -ne 0) {
                    Write-Host " [INFO] Installing required Python libraries (rich, psutil)..." -ForegroundColor Yellow
                    $reqPath = Join-Path $ScriptDir "requirements.txt"
                    if (Test-Path $reqPath) {
                        python -m pip install -r $reqPath --quiet
                    } else {
                        python -m pip install rich psutil --quiet
                    }
                }
                python $tuiPath
            } else {
                & "$ScriptDir\monitor\LiveMonitor.ps1" -InitialView "menu"
            }
        }

        "2" {
            # Storage & SSD Hub (Consolidated options)
            $subOpts = @(
                [PSCustomObject]@{ Key = "1"; Title = "Storage & SSD Diagnostics";       Desc = "Complete physical drive, partitions, file systems & SMART wear %" }
                [PSCustomObject]@{ Key = "2"; Title = "NVMe Storage Read Benchmark";     Desc = "Benchmark sequential & 4K random read throughput in MB/s" }
                [PSCustomObject]@{ Key = "3"; Title = "Run SSD TRIM Optimizer";          Desc = "Execute volume ReTrim & write wear reduction (Press R or T)" }
                [PSCustomObject]@{ Key = "0"; Title = "Return to Main Menu";             Desc = "Back to subsystem launcher" }
            )
            $subPick = Show-SubMenu -HubTitle "STORAGE & NVME SSD HUB" -Options $subOpts
            try { Clear-Host } catch {}
            switch ($subPick) {
                "1" {
                    & "$ScriptDir\diagnostics\SsdDiagnostics.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    try { [Console]::ReadKey($true) | Out-Null } catch {}
                }
                "2" {
                    & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -StorageRead
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    try { [Console]::ReadKey($true) | Out-Null } catch {}
                }
                { $_ -in "3", "t", "T", "r", "R" } {
                    & "$ScriptDir\optimizer\SsdOptimizer.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    try { [Console]::ReadKey($true) | Out-Null } catch {}
                }
            }
        }

        "3" {
            # Battery & Health Hub (Option inside an option)
            $subOpts = @(
                [PSCustomObject]@{ Key = "1"; Title = "All-in-One Battery Diagnostics";  Desc = "Calibrated health %, wear %, cycle count & terminal voltage" }
                [PSCustomObject]@{ Key = "2"; Title = "Battery Optimization & Cleanup";  Desc = "Power audit, User temp cleanup & Admin system cleanup" }
                [PSCustomObject]@{ Key = "3"; Title = "Apply Universal Battery Profile"; Desc = "Cap CPU boost to 99% on battery & enable PCIe ASPM" }
                [PSCustomObject]@{ Key = "4"; Title = "Start Background Session Logger"; Desc = "Begin silent 30s telemetry recording to logs/" }
                [PSCustomObject]@{ Key = "5"; Title = "Stop Background Session Logger";  Desc = "Terminate active background recording daemon" }
                [PSCustomObject]@{ Key = "0"; Title = "Return to Main Menu";             Desc = "Back to subsystem launcher" }
            )
            $subPick = Show-SubMenu -HubTitle "BATTERY & HEALTH DIAGNOSTICS HUB" -Options $subOpts
            try { Clear-Host } catch {}
            switch ($subPick) {
                "1" {
                    & "$ScriptDir\core\BatteryHealthModel.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    try { [Console]::ReadKey($true) | Out-Null } catch {}
                }
                "2" {
                    & "$ScriptDir\optimizer\BatteryOptimizer.ps1"
                }
                "3" {
                    & "$ScriptDir\optimizer\PowerOptimizer.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    try { [Console]::ReadKey($true) | Out-Null } catch {}
                }
                "4" {
                    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptDir\logger\BackgroundLogger.ps1`""
                    Write-Host "================================================================================" -ForegroundColor Cyan
                    Write-Host " [OK] Background Logger started in background." -ForegroundColor Green
                    Write-Host " Telemetry is continuously recording to: logs/current-session.csv" -ForegroundColor White
                    Write-Host "================================================================================" -ForegroundColor Cyan
                    Start-Sleep -Seconds 2
                }
                "5" {
                    & "$ScriptDir\logger\StopLogger.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    try { [Console]::ReadKey($true) | Out-Null } catch {}
                }
            }
        }

        "4" {
            # CPU & Memory Hub (User-friendly consolidated structure)
            $subOpts = @(
                [PSCustomObject]@{ Key = "1"; Title = "Essential CPU & RAM Overview";    Desc = "Hardware architecture, clocks, thermals & DDR5 speed" }
                [PSCustomObject]@{ Key = "2"; Title = "Advanced Multi-Core Analysis";    Desc = "Per-thread core loads, ACPI zones & instantaneous spikes" }
                [PSCustomObject]@{ Key = "3"; Title = "CPU & Memory Benchmarks";         Desc = "Single/Multi-thread compute scoring & RAM bandwidth GB/s" }
                [PSCustomObject]@{ Key = "4"; Title = "CPU & RAM Stress Testing";        Desc = "10s Multi-core thermal stress & 96% physical RAM burn-in" }
                [PSCustomObject]@{ Key = "5"; Title = "Power & Frequency Limiter";       Desc = "Cap CPU Turbo Boost to 99% to eliminate thermal throttling" }
                [PSCustomObject]@{ Key = "0"; Title = "Return to Main Menu";             Desc = "Back to subsystem launcher" }
            )
            $subPick = Show-SubMenu -HubTitle "CPU & MEMORY HUB (ESSENTIAL OVERVIEW)" -Options $subOpts
            try { Clear-Host } catch {}
            switch ($subPick) {
                "1" {
                    & "$ScriptDir\core\HardwareProfile.ps1" -ShowUi
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    try { [Console]::ReadKey($true) | Out-Null } catch {}
                }
                "2" {
                    & "$ScriptDir\diagnostics\MeasureCpuDelta.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    try { [Console]::ReadKey($true) | Out-Null } catch {}
                }
                "3" {
                    Write-Host "================================================================================" -ForegroundColor Cyan
                    Write-Host "           CPU COMPUTATIONAL & RAM MEMORY BANDWIDTH BENCHMARK" -ForegroundColor Yellow
                    Write-Host "================================================================================" -ForegroundColor Cyan
                    & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -CpuBench
                    Write-Host ""
                    & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -RamBench
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    try { [Console]::ReadKey($true) | Out-Null } catch {}
                }
                "4" {
                    Write-Host "================================================================================" -ForegroundColor Cyan
                    Write-Host "              CPU MULTI-CORE & RAM 96% SATURATION BURN-IN" -ForegroundColor Yellow
                    Write-Host "================================================================================" -ForegroundColor Cyan
                    & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -CpuStress -StressDuration 10
                    Write-Host ""
                    & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -RamStress -StressDuration 10
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    try { [Console]::ReadKey($true) | Out-Null } catch {}
                }
                "5" {
                    & "$ScriptDir\optimizer\PowerOptimizer.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    try { [Console]::ReadKey($true) | Out-Null } catch {}
                }
            }
        }

        "5" {
            # Process Manager Hub (Option inside an option)
            $subOpts = @(
                [PSCustomObject]@{ Key = "1"; Title = "All-in-One Process Monitor";     Desc = "Fast process table sorted by resource usage" }
                [PSCustomObject]@{ Key = "2"; Title = "Interactive Process Killer";     Desc = "Launch manager in kill mode to terminate by PID" }
                [PSCustomObject]@{ Key = "0"; Title = "Return to Main Menu";             Desc = "Back to subsystem launcher" }
            )
            $subPick = Show-SubMenu -HubTitle "PROCESS MANAGER & RESOURCE KILLER HUB" -Options $subOpts
            Clear-Host
            if ($subPick -eq "1") {
                & "$ScriptDir\diagnostics\ProcessManager.ps1" -Monitor
            } elseif ($subPick -eq "2") {
                & "$ScriptDir\diagnostics\ProcessManager.ps1" -Kill
            }
        }

        "6" {
            # Session Logs & Reports Hub (Option inside an option)
            $subOpts = @(
                [PSCustomObject]@{ Key = "1"; Title = "All-in-One In-Terminal Log Viewer";Desc = "Show active session telemetry & recent rows" }
                [PSCustomObject]@{ Key = "2"; Title = "Generate Statistical Test Report"; Desc = "Calculate average drain Watts & battery runtime" }
                [PSCustomObject]@{ Key = "3"; Title = "Open Logs Folder in File Explorer";Desc = "Open ubat/logs/ folder in Windows Explorer" }
                [PSCustomObject]@{ Key = "0"; Title = "Return to Main Menu";              Desc = "Back to subsystem launcher" }
            )
            $subPick = Show-SubMenu -HubTitle "SESSION LOGS & REPORTING HUB" -Options $subOpts
            Clear-Host
            switch ($subPick) {
                "1" {
                    & "$ScriptDir\analyzer\ViewLogs.ps1"
                }
                "2" {
                    & "$ScriptDir\analyzer\LogAnalyzer.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "3" {
                    $logsPath = Join-Path $ScriptDir "logs"
                    if (-not (Test-Path $logsPath)) { New-Item -ItemType Directory -Path $logsPath -Force | Out-Null }
                    Start-Process explorer.exe -ArgumentList $logsPath
                    Write-Host "Opened logs folder in File Explorer." -ForegroundColor Green
                    Start-Sleep -Seconds 1
                }
                "0" {
                    # Return to main menu
                }
            }
        }

        "7" {
            # Hardware Benchmark & Stress Testing Hub (Option inside an option)
            $subOpts = @(
                [PSCustomObject]@{ Key = "1"; Title = "NVMe Storage Read Benchmark";     Desc = "Benchmark sequential & 4K random read throughput in MB/s" }
                [PSCustomObject]@{ Key = "2"; Title = "Multi-Core CPU Thermal Stress Test";Desc = "Stress all CPU threads with live temperature tracking" }
                [PSCustomObject]@{ Key = "3"; Title = "Dedicated GPU Hardware Stress Test";Desc = "Stress RTX 5050 with 524,288 CUDA threads at 100% load" }
                [PSCustomObject]@{ Key = "4"; Title = "Dedicated Physical RAM Stress";   Desc = "Saturate DDR5 RAM to 95% with active memory bus churn" }
                [PSCustomObject]@{ Key = "5"; Title = "Combined Full-System Burn-In";     Desc = "Saturate CPU, dedicated GPU & RAM (95%) simultaneously" }
                [PSCustomObject]@{ Key = "6"; Title = "Manual Start / Stop Continuous Stress";Desc = "Continuous CPU/GPU/RAM burn-in with live keypress start/stop" }
                [PSCustomObject]@{ Key = "7"; Title = "CPU Computational Benchmark";     Desc = "Measure single-thread & multi-thread compute score" }
                [PSCustomObject]@{ Key = "8"; Title = "RAM Memory Bandwidth Benchmark"; Desc = "Measure DDR5 read and copy throughput in GB/s" }
                [PSCustomObject]@{ Key = "9"; Title = "All-in-One Full System Benchmark";Desc = "Run full sequence of Storage, RAM, CPU and GPU stress" }
                [PSCustomObject]@{ Key = "0"; Title = "Return to Main Menu";             Desc = "Back to subsystem launcher" }
            )
            $subPick = Show-SubMenu -HubTitle "HARDWARE BENCHMARK & STRESS TESTING HUB" -Options $subOpts
            try { Clear-Host } catch { }
            switch ($subPick) {
                "1" {
                    & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -StorageRead
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "2" {
                    $dur = Read-Host " Select duration: [1] 10s Quick  [2] 30s Standard  [3] 60s Extended (default 10s)"
                    $dSec = switch ($dur.Trim()) { "2" { 30 } "3" { 60 } default { 10 } }
                    & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -CpuStress -StressDuration $dSec
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "3" {
                    $dur = Read-Host " Select duration: [1] 10s Quick  [2] 30s Standard  [3] 60s Extended (default 10s)"
                    $dSec = switch ($dur.Trim()) { "2" { 30 } "3" { 60 } default { 10 } }
                    & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -GpuStress -StressDuration $dSec
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "4" {
                    $dur = Read-Host " Select duration: [1] 10s Quick  [2] 30s Standard  [3] 60s Extended (default 10s)"
                    $dSec = switch ($dur.Trim()) { "2" { 30 } "3" { 60 } default { 10 } }
                    & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -RamStress -StressDuration $dSec
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "5" {
                    $dur = Read-Host " Select duration: [1] 10s Quick  [2] 30s Standard  [3] 60s Extended (default 10s)"
                    $dSec = switch ($dur.Trim()) { "2" { 30 } "3" { 60 } default { 10 } }
                    & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -SystemStress -StressDuration $dSec
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "6" {
                    try { Clear-Host } catch { }
                    Write-Host "================================================================================" -ForegroundColor Cyan
                    Write-Host "       MANUAL START / STOP HARDWARE STRESS TEST CONTROLLER" -ForegroundColor Yellow
                    Write-Host "================================================================================" -ForegroundColor Cyan
                    Write-Host " Select Target Component for Continuous Burn-In:" -ForegroundColor White
                    Write-Host " [1] Combined Full-System Burn-In (CPU + Dedicated GPU + RAM to 95%)" -ForegroundColor White
                    Write-Host " [2] Dedicated GPU Stress (RTX 5050 CUDA 100% @ 2.7+ GHz)" -ForegroundColor White
                    Write-Host " [3] Multi-Core CPU Thermal Stress (All 24 Logical Threads)" -ForegroundColor White
                    Write-Host " [4] Dedicated Physical RAM Saturation (Fill RAM to 95%+)" -ForegroundColor White
                    Write-Host " [0] Cancel" -ForegroundColor DarkGray
                    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Cyan
                    $mPick = Read-Host " Select target [0-4]"
                    $tgt = switch ($mPick) {
                        "1" { "system" }
                        "2" { "gpu" }
                        "3" { "cpu" }
                        "4" { "ram" }
                        default { $null }
                    }
                    if ($tgt) {
                        & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -ManualStress -Target $tgt
                    }
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "7" {
                    & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -CpuBench
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "8" {
                    & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -RamBench
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "9" {
                    & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -All
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
            }
        }

        "0" {
            Write-Host "Exiting OMNI. Goodbye!" -ForegroundColor Cyan
            Start-Sleep -Milliseconds 300
            exit 0
        }
    }
}
