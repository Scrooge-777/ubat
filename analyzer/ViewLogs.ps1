<#
.SYNOPSIS
    Universal In-Terminal Session Log Viewer
.DESCRIPTION
    Displays active battery recording logs, statistics, recent entries, and archives
    directly inside the terminal. Includes option to open the logs folder in Windows File Explorer.
#>

$ScriptDir = Split-Path $PSScriptRoot -Parent
$LogsDir = Join-Path $ScriptDir "logs"
$ArchiveDir = Join-Path $LogsDir "archive"
$CurrentLog = Join-Path $LogsDir "current-session.csv"
$PidFile = Join-Path $LogsDir "battery-logger.pid"

function Show-LogViewer {
    Clear-Host
    $w = 88
    try {
        if ([Console]::WindowWidth -gt 1) {
            $w = [Console]::WindowWidth - 1
            if ($w -lt 35) { $w = 35 }
        }
    } catch { $w = 88 }

    Write-Host ("=" * $w) -ForegroundColor Cyan
    $title = "OMNI SESSION LOG VIEWER"
    $spaces = [math]::Max(0, [math]::Floor(($w - $title.Length) / 2))
    $titleText = if ($title.Length -gt $w) { $title.Substring(0, $w) } else { (" " * $spaces) + $title }
    Write-Host $titleText -ForegroundColor Yellow
    Write-Host ("=" * $w) -ForegroundColor Cyan

    # 1. Daemon Status
    $isLogging = $false
    $loggerPid = $null
    if (Test-Path $PidFile) {
        try {
            $pText = (Get-Content -Path $PidFile -ErrorAction SilentlyContinue).Trim()
            if ($pText -match '^\d+$') {
                $loggerPid = [int]$pText
                $proc = Get-Process -Id $loggerPid -ErrorAction SilentlyContinue
                if ($proc) { $isLogging = $true }
            }
        } catch {}
    }

    if ($isLogging) {
        Write-Host " Logger Status: [ACTIVE] Recording every 30s (PID: $loggerPid)" -ForegroundColor Green
    } else {
        Write-Host " Logger Status: [STOPPED] Background logger is currently inactive" -ForegroundColor DarkGray
    }
    Write-Host " Log Location:  $CurrentLog" -ForegroundColor Gray
    Write-Host ""

    # 2. Parse Current Session
    if (-not (Test-Path $CurrentLog)) {
        Write-Host " [NOTICE] No active session log found at: $CurrentLog" -ForegroundColor Yellow
        Write-Host " Start the Background Logger (Option 6) to begin recording telemetry." -ForegroundColor DarkGray
    } else {
        $rawLines = Get-Content -Path $CurrentLog -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch "^#" -and $_ -match "," }
        $dataLines = $rawLines | Select-Object -Skip 1
        $recordCount = if ($dataLines) { $dataLines.Count } else { 0 }

        Write-Host " Session Records: $recordCount entries recorded" -ForegroundColor White

        if ($recordCount -ge 2) {
            try {
                $firstRow = ($dataLines | Select-Object -First 1) -split ","
                $lastRow = ($dataLines | Select-Object -Last 1) -split ","
                
                $startTime = [datetime]::Parse($firstRow[0])
                $endTime = [datetime]::Parse($lastRow[0])
                $duration = $endTime - $startTime
                $durStr = "$([math]::Floor($duration.TotalMinutes))m $($duration.Seconds)s"
                
                $startPct = $firstRow[2]
                $endPct = $lastRow[2]
                $dropPct = [math]::Round([double]$startPct - [double]$endPct, 1)

                $startMwh = [double]$firstRow[3]
                $endMwh = [double]$lastRow[3]
                $usedMwh = [math]::Round($startMwh - $endMwh, 0)

                Write-Host " Session Duration: $durStr  |  Battery: $startPct% -> $endPct% ($dropPct% drop, $usedMwh mWh used)" -ForegroundColor Cyan
            } catch {}
        }

        Write-Host ""
        Write-Host " --- RECENT TELEMETRY ENTRIES (Last 12) ---" -ForegroundColor Cyan
        
        # Display header
        $hdrLine = " {0,-19} | {1,-4} | {2,6} | {3,9} | {4,8} | {5,5} | {6,8} | {7,-14}" -f "TIMESTAMP", "PWR", "BATT %", "REM(mWh)", "DRAIN(W)", "CPU %", "RAM(GB)", "TOP APP"
        Write-Host $hdrLine -ForegroundColor Yellow
        Write-Host ("-" * [math]::Min($w, $hdrLine.Length + 2)) -ForegroundColor DarkGray

        # Display rows
        $recentRows = $dataLines | Select-Object -Last 12
        if ($recentRows) {
            foreach ($line in $recentRows) {
                $cols = $line -split ","
                if ($cols.Count -ge 11) {
                    $ts = $cols[0]
                    $pwr = if ($cols[1] -match "true|1") { "AC" } else { "BAT" }
                    $pct = "$($cols[2])%"
                    $rem = "$($cols[3])"
                    $rate = "$($cols[4]) W"
                    $cpu = "$($cols[6])%"
                    $ram = "$($cols[7])"
                    $app = if ($cols[10].Length -gt 14) { $cols[10].Substring(0, 14) } else { $cols[10] }

                    $formatted = " {0,-19} | {1,-4} | {2,6} | {3,9} | {4,8} | {5,5} | {6,8} | {7,-14}" -f $ts, $pwr, $pct, $rem, $rate, $cpu, $ram, $app
                    Write-Host $formatted -ForegroundColor $(if ($pwr -eq "AC") { "Green" } else { "Yellow" })
                }
            }
        } else {
            Write-Host " [INFO] No telemetry rows recorded yet in this session." -ForegroundColor DarkGray
        }
    }

    # 3. Archives
    Write-Host ""
    if (Test-Path $ArchiveDir) {
        $archives = Get-ChildItem -Path $ArchiveDir -Filter "*.csv" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 4
        if ($archives) {
            Write-Host " Archived Sessions: " -NoNewline -ForegroundColor Cyan
            $archStrs = foreach ($a in $archives) {
                $kb = [math]::Round($a.Length / 1KB, 1)
                "$($a.Name) ($kb KB)"
            }
            Write-Host ($archStrs -join " | ") -ForegroundColor Gray
        }
    }

    # 4. Controls Footer
    Write-Host ""
    Write-Host ("-" * $w) -ForegroundColor Cyan
    Write-Host " Actions: [O] Open Logs Folder in Explorer | [A] Full Report | [R] Refresh | [Enter / Q] Return" -ForegroundColor Yellow
    Write-Host ("=" * $w) -ForegroundColor Cyan
}

while ($true) {
    Show-LogViewer
    
    # Non-interactive fallback
    try {
        if ([Console]::IsInputRedirected) { return }
    } catch { return }

    $key = [Console]::ReadKey($true)
    switch ($key.Key) {
        'O' {
            if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null }
            Start-Process explorer.exe -ArgumentList $LogsDir
            Write-Host "`n [OK] Opened logs folder in Windows File Explorer." -ForegroundColor Green
            Start-Sleep -Milliseconds 800
        }
        'A' {
            Clear-Host
            & "$ScriptDir\analyzer\LogAnalyzer.ps1"
            Write-Host "`nPress any key to return to log viewer..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
        }
        'R' {
            # Loop re-renders
        }
        'Enter' {
            return
        }
        'Escape' {
            return
        }
        Default {
            $ch = $key.KeyChar
            if ($ch -eq 'o' -or $ch -eq 'O') {
                if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null }
                Start-Process explorer.exe -ArgumentList $LogsDir
                Write-Host "`n [OK] Opened logs folder in Windows File Explorer." -ForegroundColor Green
                Start-Sleep -Milliseconds 800
            } elseif ($ch -eq 'a' -or $ch -eq 'A') {
                Clear-Host
                & "$ScriptDir\analyzer\LogAnalyzer.ps1"
                Write-Host "`nPress any key to return to log viewer..." -ForegroundColor DarkGray
                [Console]::ReadKey($true) | Out-Null
            } elseif ($ch -eq 'q' -or $ch -eq 'Q' -or $ch -eq 'b' -or $ch -eq 'B') {
                return
            }
        }
    }
}
