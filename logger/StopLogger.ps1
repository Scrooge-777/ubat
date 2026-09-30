<#
.SYNOPSIS
    Stops the Background Logger Daemon
#>

$ModuleDir = $PSScriptRoot
$RootDir = Split-Path $ModuleDir -Parent
$LogsDir = Join-Path $RootDir "logs"
$PidFile = Join-Path $LogsDir "battery-logger.pid"

if (Test-Path $PidFile) {
    $procId = Get-Content $PidFile
    try {
        Stop-Process -Id $procId -Force -ErrorAction Stop
        Write-Host "Universal Battery Logger process (PID $procId) stopped successfully." -ForegroundColor Green
    } catch {
        Write-Host "Process $procId was not running or already closed." -ForegroundColor Yellow
    }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "No active battery logger PID file found in $LogsDir." -ForegroundColor Yellow
}
