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

. $HwPath
$hw = Get-HardwareProfile

# Dynamic laptop banner
$rawModel = $hw.Model
$rawMfg = $hw.Manufacturer
$laptopTitle = if ($rawModel -match [regex]::Escape($rawMfg)) {
    $rawModel.ToUpper()
} else {
    "$rawMfg $rawModel".ToUpper()
}
$bannerTitle = "OMNI - SYSTEM HARDWARE TELEMETRY & OPTIMIZER ($laptopTitle)"

function Hide-Cursor {
    try { [Console]::CursorVisible = $false } catch {}
    try { [Console]::Write("`e[?25l") } catch {}
}

function Show-Cursor {
    try { [Console]::CursorVisible = $true } catch {}
    try { [Console]::Write("`e[?25h") } catch {}
}

function Reset-Cursor {
    try {
        [Console]::SetCursorPosition(0, 0)
    } catch {
        try { [Console]::Write("`e[H") } catch {}
    }
}

function Get-Width {
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
    $termWidth = Get-Width
    $cleanText = if ($Text.Length -lt $termWidth) {
        $Text.PadRight($termWidth)
    } else {
        $Text.Substring(0, $termWidth)
    }
    Write-Host "$cleanText`e[K" -ForegroundColor $ForegroundColor
}

function Show-SubMenu {
    param(
        [string]$HubTitle,
        [array]$Options
    )

    $subIndex = 0
    while ($true) {
        Hide-Cursor
        Clear-Host
        $termWidth = Get-Width

        $exitSub = $false
        $chosenSubKey = $null

        while (-not $exitSub) {
            Reset-Cursor
            Write-LineClean ("=" * $termWidth) Cyan
            Write-LineClean (" " * [math]::Max(0, [math]::Floor(($termWidth - $HubTitle.Length) / 2)) + $HubTitle) Yellow
            Write-LineClean ("=" * $termWidth) Cyan
            Write-LineClean " Choose a sub-module to execute:" White
            Write-LineClean " (Use [Up / Down] Arrow Keys to navigate, [Enter] to select, or tap [0-9])" DarkGray
            Write-LineClean "" White

            for ($i = 0; $i -lt $Options.Count; $i++) {
                $opt = $Options[$i]
                if ($i -eq $subIndex) {
                    $line = "  > [$($opt.Key)] $($opt.Title.PadRight(32)) - $($opt.Desc)"
                    Write-LineClean $line Green
                } else {
                    $line = "    [$($opt.Key)] $($opt.Title.PadRight(32)) - $($opt.Desc)"
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

$mainOptions = @(
    [PSCustomObject]@{ Key = "1"; Title = "Live System Monitor";       Desc = "All-in-One real-time terminal telemetry engine" }
    [PSCustomObject]@{ Key = "2"; Title = "Storage & SSD Hub";         Desc = "Partitions, file systems, SMART wear & SSD TRIM optimizer" }
    [PSCustomObject]@{ Key = "3"; Title = "Battery & Health Hub";      Desc = "Calibrated health %, wear level, cycle count & battery tuner" }
    [PSCustomObject]@{ Key = "4"; Title = "CPU & Memory Hub";          Desc = "Multi-thread core loads, RAM volume & frequency limits" }
    [PSCustomObject]@{ Key = "5"; Title = "Process Manager Hub";       Desc = "Fast resource monitor & interactive PID killer" }
    [PSCustomObject]@{ Key = "6"; Title = "Session Logs & Reports";    Desc = "In-terminal session logs, analysis reports & folder access" }
    [PSCustomObject]@{ Key = "0"; Title = "Exit";                      Desc = "Exit OMNI toolkit" }
)

$selectedIndex = 0

while ($true) {
    Hide-Cursor
    Clear-Host
    $termWidth = Get-Width
    $spaces = [math]::Max(0, [math]::Floor(($termWidth - $bannerTitle.Length) / 2))
    $centeredBanner = (" " * $spaces) + $bannerTitle

    $exitMenu = $false

    while (-not $exitMenu) {
        Reset-Cursor

        Write-LineClean ("=" * $termWidth) Cyan
        Write-LineClean $centeredBanner Yellow
        Write-LineClean ("=" * $termWidth) Cyan
        Write-LineClean " Hardware: $($hw.Manufacturer) $($hw.Model)  |  CPU: $($hw.CpuName)" Gray
        Write-LineClean "" White
        Write-LineClean " Choose a hardware subsystem to inspect:" White
        Write-LineClean " (Use [Up / Down] Arrow Keys to navigate, [Enter] to select, or tap [0-6])" DarkGray
        Write-LineClean "" White

        for ($i = 0; $i -lt $mainOptions.Count; $i++) {
            $opt = $mainOptions[$i]
            if ($i -eq $selectedIndex) {
                $line = "  > [$($opt.Key)] $($opt.Title.PadRight(28)) - $($opt.Desc)"
                Write-LineClean $line Green
            } else {
                $line = "    [$($opt.Key)] $($opt.Title.PadRight(28)) - $($opt.Desc)"
                Write-LineClean $line Gray
            }
        }

        Write-LineClean "" White
        Write-LineClean ("-" * $termWidth) Cyan
        Write-LineClean " Controls: [Up / Down] Move Selection  |  [Enter / Space] Select  |  [0-6] Quick Jump  |  [Q] Exit" DarkGray
        try { [Console]::Write("`e[J") } catch {}

        try {
            if ([Console]::IsInputRedirected) {
                return
            }
        } catch { return }

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
                } elseif ($ch -match '^[0-6]$') {
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
                python $tuiPath
            } else {
                & "$ScriptDir\monitor\LiveMonitor.ps1" -InitialView "menu"
            }
        }

        "2" {
            # Storage & SSD Hub (Option inside an option)
            $subOpts = @(
                [PSCustomObject]@{ Key = "1"; Title = "All-in-One Storage Diagnostics"; Desc = "Complete physical drive, partitions & wear overview" }
                [PSCustomObject]@{ Key = "2"; Title = "Partitions & File Systems Table";  Desc = "Detailed breakdown of C:, G:, S: labels & space" }
                [PSCustomObject]@{ Key = "3"; Title = "Physical SSD SMART Health & Wear";Desc = "Drive model, temperature & degradation level %" }
                [PSCustomObject]@{ Key = "4"; Title = "Run SSD TRIM Optimizer";          Desc = "Execute volume ReTrim & write wear reduction" }
                [PSCustomObject]@{ Key = "0"; Title = "Return to Main Menu";             Desc = "Back to subsystem launcher" }
            )
            $subPick = Show-SubMenu -HubTitle "STORAGE & NVME SSD HUB" -Options $subOpts
            Clear-Host
            switch ($subPick) {
                "1" {
                    & "$ScriptDir\diagnostics\SsdDiagnostics.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "2" {
                    & "$ScriptDir\diagnostics\SsdDiagnostics.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "3" {
                    & "$ScriptDir\diagnostics\SsdDiagnostics.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "4" {
                    & "$ScriptDir\optimizer\SsdOptimizer.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
            }
        }

        "3" {
            # Battery & Health Hub (Option inside an option)
            $subOpts = @(
                [PSCustomObject]@{ Key = "1"; Title = "All-in-One Battery Diagnostics"; Desc = "Calibrated health %, wear %, cycles & pack voltage" }
                [PSCustomObject]@{ Key = "2"; Title = "Battery Life Optimizer";         Desc = "Safe CPU boost capping (99%) & PCIe ASPM tuning" }
                [PSCustomObject]@{ Key = "3"; Title = "Start Background Session Logger";Desc = "Begin silent 30s telemetry recording to logs/" }
                [PSCustomObject]@{ Key = "4"; Title = "Stop Background Session Logger"; Desc = "Terminate active background recording daemon" }
                [PSCustomObject]@{ Key = "0"; Title = "Return to Main Menu";             Desc = "Back to subsystem launcher" }
            )
            $subPick = Show-SubMenu -HubTitle "BATTERY & HEALTH DIAGNOSTICS HUB" -Options $subOpts
            Clear-Host
            switch ($subPick) {
                "1" {
                    & "$ScriptDir\core\BatteryHealthModel.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "2" {
                    & "$ScriptDir\optimizer\PowerOptimizer.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "3" {
                    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptDir\logger\BackgroundLogger.ps1`""
                    Write-Host "================================================================================" -ForegroundColor Cyan
                    Write-Host " [OK] Background Logger started in background." -ForegroundColor Green
                    Write-Host " Telemetry is continuously recording to: logs/current-session.csv" -ForegroundColor White
                    Write-Host "================================================================================" -ForegroundColor Cyan
                    Start-Sleep -Seconds 2
                }
                "4" {
                    & "$ScriptDir\logger\StopLogger.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
            }
        }

        "4" {
            # CPU & Memory Hub (Option inside an option)
            $subOpts = @(
                [PSCustomObject]@{ Key = "1"; Title = "All-in-One CPU & RAM Status";    Desc = "Overall load %, clocks, cores and memory volume" }
                [PSCustomObject]@{ Key = "2"; Title = "Measure Instantaneous CPU Spikes";Desc = "Detect per-process CPU spikes in real-time" }
                [PSCustomObject]@{ Key = "3"; Title = "Cap CPU Boost Frequency (99%)";  Desc = "Disable thermal throttling spikes safely" }
                [PSCustomObject]@{ Key = "0"; Title = "Return to Main Menu";             Desc = "Back to subsystem launcher" }
            )
            $subPick = Show-SubMenu -HubTitle "CPU & MEMORY HUB" -Options $subOpts
            Clear-Host
            switch ($subPick) {
                "1" {
                    & "$ScriptDir\core\HardwareProfile.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "2" {
                    & "$ScriptDir\diagnostics\MeasureCpuDelta.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
                "3" {
                    & "$ScriptDir\optimizer\PowerOptimizer.ps1"
                    Write-Host "`nPress any key to return..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
            }
        }

        "5" {
            # Process Manager Hub (Option inside an option)
            $subOpts = @(
                [PSCustomObject]@{ Key = "1"; Title = "All-in-One Process Monitor";     Desc = "Fast process table sorted by resource usage" }
                [PSCustomObject]@{ Key = "2"; Title = "Interactive Process Killer";     Desc = "Launch manager and enter PID to terminate" }
                [PSCustomObject]@{ Key = "0"; Title = "Return to Main Menu";             Desc = "Back to subsystem launcher" }
            )
            $subPick = Show-SubMenu -HubTitle "PROCESS MANAGER & RESORUCE KILLER HUB" -Options $subOpts
            Clear-Host
            if ($subPick -eq "1" -or $subPick -eq "2") {
                & "$ScriptDir\diagnostics\ProcessManager.ps1"
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
            }
        }

        "0" {
            Write-Host "Exiting OMNI. Goodbye!" -ForegroundColor Cyan
            Start-Sleep -Milliseconds 300
            exit 0
        }
    }
}
