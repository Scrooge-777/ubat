<#
.SYNOPSIS
    ubat Master Interactive Interactive Menu (Arrow-Key & Motionless Edition)
.DESCRIPTION
    Master TUI launcher for the entire ubat toolkit. Supports seamless arrow-key navigation (↑/↓),
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
    [PSCustomObject]@{ Key = "1"; Title = "Launch Live Monitor";         Desc = "Flicker-free live wattage, power breakdown & process table" }
    [PSCustomObject]@{ Key = "2"; Title = "Battery Health Model";        Desc = "Calibrated health %, cycle life, degradation grade & pack balance" }
    [PSCustomObject]@{ Key = "3"; Title = "Optimize Laptop Battery";     Desc = "Safe CPU boost capping (99%), PCIe ASPM & OEM guidance" }
    [PSCustomObject]@{ Key = "4"; Title = "Start Background Logger";     Desc = "30s silent crash-proof session recording into logs/" }
    [PSCustomObject]@{ Key = "5"; Title = "Stop Background Logger";      Desc = "Terminate active background recording daemon" }
    [PSCustomObject]@{ Key = "6"; Title = "Generate Test Report";        Desc = "Statistical analysis, average Watts, battery drop & Markdown export" }
    [PSCustomObject]@{ Key = "7"; Title = "Process Manager & Killer";    Desc = "Task Manager parallel table & interactive PID killer" }
    [PSCustomObject]@{ Key = "8"; Title = "NVMe SSD Health & Speed";    Desc = "Storage throughput (MB/s), active disk %, drive health & APST draw" }
    [PSCustomObject]@{ Key = "9"; Title = "Open Logs Folder";            Desc = "Open ubat/logs/ folder in Windows File Explorer" }
    [PSCustomObject]@{ Key = "0"; Title = "Exit";                        Desc = "Exit ubat toolkit" }
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
        Write-LineClean " (Use [↑ / ↓] Arrow Keys to navigate, [Enter] to select, or tap [0-9])" DarkGray
        Write-LineClean "" White

        for ($i = 0; $i -lt $mainOptions.Count; $i++) {
            $opt = $mainOptions[$i]
            if ($i -eq $selectedIndex) {
                # Highlight active selection
                $line = "  ► [$($opt.Key)] $($opt.Title.PadRight(28)) - $($opt.Desc)"
                Write-LineClean $line Green
            } else {
                $line = "    [$($opt.Key)] $($opt.Title.PadRight(28)) - $($opt.Desc)"
                Write-LineClean $line Gray
            }
        }

        Write-LineClean "" White
        Write-LineClean ("-" * $termWidth) Cyan
        Write-LineClean " Controls: [↑ / ↓] Move Selection  |  [Enter / Space] Select  |  [0-9] Quick Jump  |  [Q] Exit" DarkGray
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
                } elseif ($ch -match '^[0-9]$') {
                    $chosenKey = $ch.ToString()
                    $exitMenu = $true
                }
            }
        }
    }

    Show-Cursor
    Clear-Host

    switch ($chosenKey) {
        "1" {
            # Live Monitor with arrow-key partition menu
            & "$ScriptDir\monitor\LiveMonitor.ps1" -InitialView "menu"
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
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptDir\logger\BackgroundLogger.ps1`""
            Write-Host "================================================================================" -ForegroundColor Cyan
            Write-Host " [OK] Background Logger started silently in background." -ForegroundColor Green
            Write-Host " Logs are continuously appending to: logs/current-session.csv" -ForegroundColor White
            Write-Host "================================================================================" -ForegroundColor Cyan
            Start-Sleep -Seconds 2
        }
        "5" {
            & "$ScriptDir\logger\StopLogger.ps1"
            Write-Host "`nPress any key to return to menu..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "6" {
            & "$ScriptDir\analyzer\LogAnalyzer.ps1"
            Write-Host "`nPress any key to return to menu..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "7" {
            & "$ScriptDir\diagnostics\ProcessManager.ps1"
        }
        "8" {
            & "$ScriptDir\diagnostics\SsdDiagnostics.ps1"
            Write-Host "`nPress any key to return to menu..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        "9" {
            $logsPath = Join-Path $ScriptDir "logs"
            if (-not (Test-Path $logsPath)) { New-Item -ItemType Directory -Path $logsPath -Force | Out-Null }
            Start-Process explorer.exe -ArgumentList $logsPath
            Write-Host "Opened logs folder in File Explorer." -ForegroundColor Green
            Start-Sleep -Seconds 1
        }
        "0" {
            Write-Host "Exiting ubat. Goodbye!" -ForegroundColor Cyan
            Start-Sleep -Milliseconds 400
            exit 0
        }
    }
}
