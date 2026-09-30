<#
.SYNOPSIS
    Process CPU Delta Measurement Tool
.DESCRIPTION
    Measures instantaneous CPU usage across all active processes over 2 seconds
    to pinpoint exactly which application is spiking battery drain.
#>

Write-Host "Sampling process CPU activity over 2 seconds..." -ForegroundColor Cyan
$p1 = Get-Process | Select-Object Id, ProcessName, CPU, WorkingSet64
Start-Sleep -Seconds 2
$p2 = Get-Process | Select-Object Id, ProcessName, CPU, WorkingSet64

$diff = foreach ($b in $p2) {
    $a = $p1 | Where-Object { $_.Id -eq $b.Id }
    if ($a -and $b.CPU -gt $a.CPU) {
        [PSCustomObject]@{
            Name          = $b.ProcessName
            PID           = $b.Id
            DeltaCPU_Secs = [math]::Round($b.CPU - $a.CPU, 2)
            Memory_MB     = [math]::Round($b.WorkingSet64 / 1MB, 1)
        }
    }
}

Write-Host ""
Write-Host "Top Active Processes Over Last 2 Seconds:" -ForegroundColor Yellow
$diff | Sort-Object DeltaCPU_Secs -Descending | Select-Object -First 10 | Format-Table -AutoSize
