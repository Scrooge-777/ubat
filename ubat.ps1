<#
.SYNOPSIS
    ubat Master Interactive Interactive Menu (Arrow-Key & Motionless Edition)
.DESCRIPTION
    Master TUI launcher for the entire ubat toolkit. Supports seamless arrow-key navigation (Up/Down),
    Enter/Space confirmation, direct number shortcuts, and zero-flicker rendering.
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
$bannerTitle = "UBAT - UNIVERSAL BATTERY OPTIMIZER ($laptopTitle)"

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

$mainOptions = @(
    [PSCustomObject]@{ Key = "1"; Title = "Live Monitor";           Desc = "Real-time battery, CPU, GPU & Task Manager heatmaps" }
    [PSCustomObject]@{ Key = "2"; Title = "Battery Health";         Desc = "Calibrated health %, wear level, cycle count & pack grade" }
    [PSCustomObject]@{ Key = "3"; Title = "Battery Optimizer";      Desc = "Tune power schemes, PCIe ASPM & safe CPU boost limits" }
    [PSCustomObject]@{ Key = "4"; Title = "Process Manager";        Desc = "Task Manager process table & interactive PID killer" }
    [PSCustomObject]@{ Key = "5"; Title = "Storage Diagnostics";    Desc = "NVMe SSD read/write speeds, drive health & APST draw" }
    [PSCustomObject]@{ Key = "6"; Title = "Start Session Logger";   Desc = "Record battery and power usage every 30s in background" }
    [PSCustomObject]@{ Key = "7"; Title = "Stop Session Logger";    Desc = "Terminate active background battery recording daemon" }
    [PSCustomObject]@{ Key = "8"; Title = "Generate Test Report";   Desc = "Statistical analysis, average drain Watts & runtime" }
    [PSCustomObject]@{ Key = "9"; Title = "View Session Logs";      Desc = "Show logs in terminal (with option to open folder)" }
    [PSCustomObject]@{ Key = "0"; Title = "Exit";                   Desc = "Exit ubat toolkit" }
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
        Write-LineClean " Choose a toolkit module to execute:" White
        Write-LineClean " (Use [Up / Down] Arrow Keys to navigate, [Enter] to select, or tap [0-9])" DarkGray
        Write-LineClean "" White

        for ($i = 0; $i -lt $mainOptions.Count; $i++) {
            $opt = $mainOptions[$i]
            if ($i -eq $selectedIndex) {
                # Highlight active selection
                $line = "  > [$($opt.Key)] $($opt.Title.PadRight(28)) - $($opt.Desc)"
                Write-LineClean $line Green
            } else {
                $line = "    [$($opt.Key)] $($opt.Title.PadRight(28)) - $($opt.Desc)"
                Write-LineClean $line Gray
            }
        }

        Write-LineClean "" White
        Write-LineClean ("-" * $termWidth) Cyan
        Write-LineClean " Controls: [Up / Down] Move Selection  |  [Enter / Space] Select  |  [0-9] Quick Jump  |  [Q] Exit" DarkGray
        try { [Console]::Write("`e[J") } catch {}

        # Non-interactive check
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
                } elseif ($ch -match '^[0-9a-zA-Z]$') {
                    $matchedOpt = $mainOptions | Where-Object { $_.Key -eq $ch.ToString().ToUpper() }
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
            # Live Monitor (Python Rich engine with auto-fallback)
            $tuiPath = Join-Path $ScriptDir "tui\ubat_tui.py"
            if (Get-Command python -ErrorAction SilentlyContinue) {
                python $tuiPath
            } else {
                & "$ScriptDir\monitor\LiveMonitor.ps1" -InitialView "menu"
            }
        }
        "2" {
            & "$ScriptDir\core\BatteryHealthModel.ps1"
            Write-Host "`nPress any key to return to menu..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "3" {
            & "$ScriptDir\optimizer\PowerOptimizer.ps1"
            Write-Host "`nPress any key to return to menu..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "4" {
            & "$ScriptDir\diagnostics\ProcessManager.ps1"
        }
        "5" {
            & "$ScriptDir\diagnostics\SsdDiagnostics.ps1"
            Write-Host "`nPress any key to return to menu..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "6" {
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptDir\logger\BackgroundLogger.ps1`""
            Write-Host "================================================================================" -ForegroundColor Cyan
            Write-Host " [OK] Background Logger started in background." -ForegroundColor Green
            Write-Host " Telemetry is continuously recording to: logs/current-session.csv" -ForegroundColor White
            Write-Host "================================================================================" -ForegroundColor Cyan
            Start-Sleep -Seconds 2
        }
        "7" {
            & "$ScriptDir\logger\StopLogger.ps1"
            Write-Host "`nPress any key to return to menu..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "8" {
            & "$ScriptDir\analyzer\LogAnalyzer.ps1"
            Write-Host "`nPress any key to return to menu..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "9" {
            & "$ScriptDir\analyzer\ViewLogs.ps1"
        }
        "L" {
            & "$ScriptDir\analyzer\ViewLogs.ps1"
        }
        "0" {
            Write-Host "Exiting ubat. Goodbye!" -ForegroundColor Cyan
            Start-Sleep -Milliseconds 400
            exit 0
        }
    }
}
