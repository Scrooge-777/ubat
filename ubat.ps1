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

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

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

# Ensure UTF-8 console output encoding
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch {}

# Unicode Box Drawing & Clack Timeline Glyphs (String typed for multiplication and formatting)
$global:G_RAIL    = [string][char]0x2502  # │
$global:G_TOP     = [string][char]0x250C  # ┌
$global:G_BOT     = [string][char]0x2514  # └
$global:G_TEE     = [string][char]0x251C  # ├
$global:G_BAR     = [string][char]0x2500  # ─
$global:G_TR      = [string][char]0x256E  # ╮
$global:G_BR      = [string][char]0x256F  # ╯
$global:G_DIAMOND = [string][char]0x25C7  # ◇
$global:G_ACTIVE  = [string][char]0x25CF  # ●
$global:G_IDLE    = [string][char]0x25CB  # ○
$global:G_CHECK   = [string][char]0x2713  # ✓

# Console helper functions are provided by core\ConsoleHelpers.ps1 (dot-sourced above)

function Format-MenuOptionLine {
    param(
        [object]$Option,
        [bool]$IsSelected,
        [int]$TermWidth
    )
    $bullet = if ($IsSelected) { $global:G_ACTIVE } else { $global:G_IDLE }
    $prefix = "$($global:G_RAIL)  $bullet  "
    $avail = $TermWidth - $prefix.Length
    if ($avail -le 24) {
        return "$prefix$($Option.Title)"
    }
    if ($avail -lt 60) {
        $title = $Option.Title
        $rem = $avail - $title.Length - 4
        if ($rem -gt 8) {
            $desc = if ($Option.Desc.Length -gt $rem) { $Option.Desc.Substring(0, $rem - 3) + "..." } else { $Option.Desc }
            return "$prefix$title $($global:G_BAR) $desc"
        } else {
            return "$prefix$title"
        }
    } else {
        $pad = [math]::Min(34, [math]::Max(24, [int]($avail * 0.36)))
        $rem = $avail - $pad - 4
        $desc = if ($Option.Desc.Length -gt $rem) { $Option.Desc.Substring(0, [math]::Max(0, $rem - 3)) + "..." } else { $Option.Desc }
        return "$prefix$($Option.Title.PadRight($pad)) $($global:G_BAR) $desc"
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
            Write-LineClean "$($global:G_TOP)   $HubTitle" Cyan
            Write-LineClean "$($global:G_RAIL)" DarkGray
            Write-LineClean "$($global:G_DIAMOND)  Choose an operation to execute:" White
            Write-LineClean "$($global:G_RAIL)" DarkGray

            for ($i = 0; $i -lt $Options.Count; $i++) {
                $opt = $Options[$i]
                $line = Format-MenuOptionLine -Option $opt -IsSelected ($i -eq $subIndex) -TermWidth $termWidth
                if ($i -eq $subIndex) {
                    Write-LineClean $line Cyan
                } else {
                    Write-LineClean $line DarkGray
                }
            }

            Write-LineClean "$($global:G_RAIL)" DarkGray
            $cardWidth = [math]::Min(56, [math]::Max(42, $termWidth - 6))
            $padLen = [math]::Max(2, ($cardWidth - 14))
            Write-LineClean ("$($global:G_DIAMOND)  Controls " + ($global:G_BAR * $padLen) + $global:G_TR) DarkGray
            Write-LineClean ("$($global:G_RAIL)" + (" " * ($cardWidth + 1)) + "$($global:G_RAIL)") DarkGray
            $arrowNav = "$([char]0x2191)/$([char]0x2193)"
            $contentStr = "  [$arrowNav] Navigate   [Enter] Select   [Esc/Q] Back"
            $contentPad = [math]::Max(1, ($cardWidth - $contentStr.Length + 1))
            Write-LineClean ("$($global:G_RAIL)" + $contentStr + (" " * $contentPad) + "$($global:G_RAIL)") DarkGray
            Write-LineClean ("$($global:G_RAIL)" + (" " * ($cardWidth + 1)) + "$($global:G_RAIL)") DarkGray
            Write-LineClean ("$($global:G_TEE)" + ($global:G_BAR * ($cardWidth + 1)) + $global:G_BR) DarkGray
            Write-LineClean "$($global:G_RAIL)" DarkGray
            Write-LineClean "$($global:G_BOT)  Ready. Use arrow keys to navigate." DarkGray
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
                    }
                }
            }
        }

        Show-Cursor
        return $chosenSubKey
    }
}

function Get-StressDuration {
    param([string]$StressName)
    $durOpts = @(
        [PSCustomObject]@{ Key = "10"; Title = "Quick Stress (10 seconds)";     Desc = "Fast verification of thermal response & power spikes" }
        [PSCustomObject]@{ Key = "30"; Title = "Standard Stress (30 seconds)";  Desc = "Thorough thermal saturation & throttling check" }
        [PSCustomObject]@{ Key = "60"; Title = "Extended Burn-In (60 seconds)"; Desc = "Heavy sustained load & cooling dissipation test" }
        [PSCustomObject]@{ Key = "0";  Title = "Cancel";                        Desc = "Return to benchmark menu" }
    )
    $res = Show-SubMenu -HubTitle "$StressName - DURATION" -Options $durOpts
    try { Clear-Host } catch {}
    if ($res -in "10", "30", "60") { return [int]$res }
    return 0
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
        Write-LineClean "$($global:G_TOP)   $bannerTitle" Cyan
        Write-LineClean "$($global:G_RAIL)" DarkGray
        Write-LineClean "$($global:G_DIAMOND)  Platform: $($hw.Manufacturer) $($hw.Model)  |  CPU: $($hw.CpuName)" DarkGray
        Write-LineClean "$($global:G_RAIL)" DarkGray
        Write-LineClean "$($global:G_DIAMOND)  Choose a hardware subsystem or hub:" White
        Write-LineClean "$($global:G_RAIL)" DarkGray

        for ($i = 0; $i -lt $mainOptions.Count; $i++) {
            $opt = $mainOptions[$i]
            $line = Format-MenuOptionLine -Option $opt -IsSelected ($i -eq $selectedIndex) -TermWidth $termWidth
            if ($i -eq $selectedIndex) {
                Write-LineClean $line Cyan
            } else {
                Write-LineClean $line DarkGray
            }
        }

        Write-LineClean "$($global:G_RAIL)" DarkGray
        $cardWidth = [math]::Min(62, [math]::Max(46, $termWidth - 6))
        $padLen = [math]::Max(2, ($cardWidth - 14))
        Write-LineClean ("$($global:G_DIAMOND)  Controls " + ($global:G_BAR * $padLen) + $global:G_TR) DarkGray
        Write-LineClean ("$($global:G_RAIL)" + (" " * ($cardWidth + 1)) + "$($global:G_RAIL)") DarkGray
        $arrowNav = "$([char]0x2191)/$([char]0x2193)"
        $contentStr = "  [$arrowNav] Navigate   [Enter/Space] Select   [Q/Esc] Exit"
        $contentPad = [math]::Max(1, ($cardWidth - $contentStr.Length + 1))
        Write-LineClean ("$($global:G_RAIL)" + $contentStr + (" " * $contentPad) + "$($global:G_RAIL)") DarkGray
        Write-LineClean ("$($global:G_RAIL)" + (" " * ($cardWidth + 1)) + "$($global:G_RAIL)") DarkGray
        Write-LineClean ("$($global:G_TEE)" + ($global:G_BAR * ($cardWidth + 1)) + $global:G_BR) DarkGray
        Write-LineClean "$($global:G_RAIL)" DarkGray
        Write-LineClean "$($global:G_BOT)  Ready. Use arrow keys to navigate." DarkGray
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
                if ($ch -eq '0' -or $ch -eq 'q' -or $ch -eq 'Q') {
                    $chosenKey = "0"
                    $exitMenu = $true
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
                    $dSec = Get-StressDuration -StressName "MULTI-CORE CPU THERMAL STRESS"
                    if ($dSec -gt 0) {
                        & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -CpuStress -StressDuration $dSec
                        Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                        [Console]::ReadKey($true) | Out-Null
                    }
                }
                "3" {
                    $dSec = Get-StressDuration -StressName "DEDICATED GPU HARDWARE STRESS"
                    if ($dSec -gt 0) {
                        & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -GpuStress -StressDuration $dSec
                        Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                        [Console]::ReadKey($true) | Out-Null
                    }
                }
                "4" {
                    $dSec = Get-StressDuration -StressName "PHYSICAL RAM SATURATION STRESS"
                    if ($dSec -gt 0) {
                        & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -RamStress -StressDuration $dSec
                        Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                        [Console]::ReadKey($true) | Out-Null
                    }
                }
                "5" {
                    $dSec = Get-StressDuration -StressName "COMBINED FULL-SYSTEM BURN-IN"
                    if ($dSec -gt 0) {
                        & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -SystemStress -StressDuration $dSec
                        Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                        [Console]::ReadKey($true) | Out-Null
                    }
                }
                "6" {
                    $tgtOpts = @(
                        [PSCustomObject]@{ Key = "system"; Title = "Combined Full-System Burn-In";     Desc = "Saturate CPU, Dedicated GPU & RAM to 95% simultaneously" }
                        [PSCustomObject]@{ Key = "gpu";    Title = "Dedicated GPU Stress";             Desc = "CUDA 100% load & maximum core clock" }
                        [PSCustomObject]@{ Key = "cpu";    Title = "Multi-Core CPU Thermal Stress";    Desc = "All logical threads saturated with live thermal tracking" }
                        [PSCustomObject]@{ Key = "ram";    Title = "Dedicated Physical RAM Saturation"; Desc = "Fill RAM to 95%+ with active memory bus churn" }
                        [PSCustomObject]@{ Key = "0";      Title = "Cancel";                           Desc = "Return to benchmark menu" }
                    )
                    $tgt = Show-SubMenu -HubTitle "CONTINUOUS STRESS TEST TARGET" -Options $tgtOpts
                    try { Clear-Host } catch {}
                    if ($tgt -and $tgt -ne "0") {
                        & "$ScriptDir\diagnostics\BenchmarkEngine.ps1" -ManualStress -Target $tgt
                        Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                        [Console]::ReadKey($true) | Out-Null
                    }
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
