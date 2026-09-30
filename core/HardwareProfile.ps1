<#
.SYNOPSIS
    Core Hardware Profiling & Metrics Extraction Engine
.DESCRIPTION
    Universal detection module for any Windows laptop:
    - Manufacturer (HP, Lenovo, ASUS, Dell, Acer, MSI, Surface, etc.)
    - CPU architecture (Intel Core, Core Ultra, AMD Ryzen)
    - GPU configuration (NVIDIA GeForce, AMD Radeon, Intel Arc, iGPU)
    - Battery design and full capacity metrics
#>
function Get-HardwareProfile {
    $cs = $null; $bios = $null; $cpu = $null; $gpus = @(); $batt = $null; $fullCap = $null; $staticBatt = $null
    try { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue } catch {}
    try { $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue } catch {}
    try { $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1 } catch {}
    try { $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue } catch {}
    try { $batt = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue } catch {}
    try { $fullCap = Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue } catch {}
    try { $staticBatt = Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue } catch {}

    $mfg = if ($cs.Manufacturer) { $cs.Manufacturer.Trim() } else { "Generic" }
    $model = if ($cs.Model) { $cs.Model.Trim() } else { "Laptop" }
    $cpuName = if ($cpu.Name) { $cpu.Name.Trim() } else { "Processor" }

    $nvidiaGpu = $gpus | Where-Object { $_.Name -like '*NVIDIA*' } | Select-Object -First 1
    $amdGpu = $gpus | Where-Object { $_.Name -like '*Radeon*' -or $_.Name -like '*AMD*' } | Select-Object -First 1
    $intelGpu = $gpus | Where-Object { $_.Name -like '*Intel*' } | Select-Object -First 1

    $dgpuName = $null
    $hasNvidia = $false
    $hasAmd = $false
    if ($nvidiaGpu) {
        $dgpuName = $nvidiaGpu.Name
        $hasNvidia = $true
    } elseif ($amdGpu -and $intelGpu) {
        $dgpuName = $amdGpu.Name
        $hasAmd = $true
    }

    $fullCapMwh = if ($fullCap) { $fullCap.FullChargedCapacity } else { 80000 }
    $designCapMwh = if ($staticBatt) { $staticBatt.DesignedCapacity } else { $fullCapMwh }
    $healthPct = 100
    if ($designCapMwh -gt 0 -and $fullCapMwh -gt 0) {
        $healthPct = [math]::Round(($fullCapMwh / $designCapMwh) * 100, 1)
    }

    $totalRamMB = 16384
    try {
        $totalRamMB = [math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1024, 0)
    } catch {}
    $totalRamGB = [math]::Round($totalRamMB / 1024, 2)

    return [PSCustomObject]@{
        Manufacturer = $mfg
        Model        = $model
        CpuName      = $cpuName
        HasNvidia    = $hasNvidia
        HasAmd       = $hasAmd
        DgpuName     = $dgpuName
        FullCapMwh   = $fullCapMwh
        DesignCapMwh = $designCapMwh
        HealthPct    = $healthPct
        TotalRamMB   = $totalRamMB
        TotalRamGB   = $totalRamGB
        GpuList      = $gpus
    }
}

function Get-LiveMetrics {
    param(
        [PSCustomObject]$HardwareProfile,
        [switch]$SkipProcessSort
    )

    if (-not $HardwareProfile) {
        $HardwareProfile = Get-HardwareProfile
    }

    $status = $null; $batt = $null; $os = $null; $cpu = $null
    try { $status = Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue } catch {}
    try { $batt = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue } catch {}
    try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue } catch {}
    try { $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1 } catch {}

    $powerOnline = if ($status) { $status.PowerOnline } else { $true }
    $remainingMwh = if ($status) { $status.RemainingCapacity } else { 0 }
    $fullCapMwh = $HardwareProfile.FullCapMwh
    
    $dischargeWatts = 0
    if ($status -and $status.DischargeRate) {
        $dischargeWatts = [math]::Round($status.DischargeRate / 1000, 2)
    }

    $voltageV = if ($status -and $status.Voltage) { [math]::Round($status.Voltage / 1000, 2) } else { 12.0 }

    $percent = if ($batt) { $batt.EstimatedChargeRemaining } else { 0 }
    if ($percent -eq 0 -and $remainingMwh -gt 0 -and $fullCapMwh -gt 0) {
        $percent = [math]::Round(($remainingMwh / $fullCapMwh) * 100)
    }

    # Dynamic 4-hour target budget
    $target4hWatts = [math]::Round($remainingMwh / 4000, 2)
    
    $estHours = 0
    $estMinutes = 0
    $canLast4Hours = $false

    if (-not $powerOnline -and $dischargeWatts -gt 0) {
        $rawHours = $remainingMwh / ($dischargeWatts * 1000)
        $estHours = [math]::Floor($rawHours)
        $estMinutes = [math]::Round(($rawHours - $estHours) * 60)
        if ($dischargeWatts -le $target4hWatts) {
            $canLast4Hours = $true
        }
    }

    # NVIDIA dGPU Power Query
    $gpuWatts = 0
    $gpuState = "Off / Asleep"
    if ($HardwareProfile.HasNvidia) {
        try {
            $nv = nvidia-smi --query-gpu=power.draw,pstate --format=csv,noheader,nounits 2>$null
            if ($nv) {
                $parts = $nv.Trim().Split(',')
                $gpuWatts = [math]::Round([double]$parts[0].Trim(), 2)
                $gpuState = $parts[1].Trim()
            }
        } catch {
            $gpuWatts = 0
            $gpuState = "D3Cold (Sleep)"
        }
    }

    $systemRestWatts = [math]::Round([math]::Max(0, $dischargeWatts - $gpuWatts), 2)
    $gpuSharePct = 0
    if ($dischargeWatts -gt 0 -and $gpuWatts -gt 0) {
        $gpuSharePct = [math]::Round(($gpuWatts / $dischargeWatts) * 100, 1)
    }

    $cpuLoad = if ($cpu) { $cpu.LoadPercentage } else { 0 }
    $totalRamGB = if ($HardwareProfile -and $HardwareProfile.TotalRamGB) {
        $HardwareProfile.TotalRamGB
    } elseif ($os) {
        [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    } else { 16.0 }

    $freeRamGB = if ($os) { [math]::Round($os.FreePhysicalMemory / 1MB, 2) } else { 0 }
    $usedRamGB = [math]::Round($totalRamGB - $freeRamGB, 2)
    $ramPercent = if ($totalRamGB -gt 0) { [math]::Round(($usedRamGB / $totalRamGB) * 100, 1) } else { 0 }

    # Top processes (optional fast path for live monitor)
    $topCpu = @()
    $topMem = @()
    if (-not $SkipProcessSort) {
        $topCpu = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 ProcessName, Id, @{N='CPU(s)'; E={[math]::Round($_.CPU, 1)}}, @{N='RAM(MB)'; E={[math]::Round($_.WorkingSet64 / 1MB, 1)}}
        $topMem = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 ProcessName, Id, @{N='RAM(MB)'; E={[math]::Round($_.WorkingSet64 / 1MB, 1)}}
    }

    return [PSCustomObject]@{
        Timestamp       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        PowerOnline     = $powerOnline
        Percent         = $percent
        DischargeWatts  = $dischargeWatts
        GpuWatts        = $gpuWatts
        GpuState        = $gpuState
        GpuSharePct     = $gpuSharePct
        SystemRestWatts = $systemRestWatts
        RemainingMwh    = $remainingMwh
        FullCapMwh      = $fullCapMwh
        VoltageV        = $voltageV
        EstHours        = $estHours
        EstMinutes      = $estMinutes
        Target4hWatts   = $target4hWatts
        CanLast4Hours   = $canLast4Hours
        CpuLoad         = $cpuLoad
        TotalRamGB      = $totalRamGB
        UsedRamGB       = $usedRamGB
        RamPercent      = $ramPercent
        TopCpu          = $topCpu
        TopMem          = $topMem
    }
}
