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
param(
    [switch]$ShowUi
)

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

    # Physical RAM Module details (DDR5 Clock, Manufacturer, Part Number)
    $ramModules = @()
    $ramSpeed = 0
    try {
        $physMem = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
        foreach ($pm in $physMem) {
            $ramModules += [PSCustomObject]@{
                Bank         = $pm.BankLabel
                Manufacturer = $pm.Manufacturer
                PartNumber   = if ($pm.PartNumber) { $pm.PartNumber.Trim() } else { "Generic" }
                SpeedMTs     = $pm.ConfiguredClockSpeed
                CapacityGB   = [math]::Round($pm.Capacity / 1GB, 1)
            }
            if ($pm.ConfiguredClockSpeed -gt $ramSpeed) { $ramSpeed = $pm.ConfiguredClockSpeed }
        }
    } catch {}

    # Motherboard & BIOS
    $bb = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    $boardMfg = if ($bb.Manufacturer) { $bb.Manufacturer.Trim() } else { $mfg }
    $boardProd = if ($bb.Product) { $bb.Product.Trim() } else { "Motherboard" }
    $biosVer = if ($bios.SMBIOSBIOSVersion) { $bios.SMBIOSBIOSVersion.Trim() } else { "N/A" }
    $biosDate = if ($bios.ReleaseDate) { (Get-Date $bios.ReleaseDate).ToString("yyyy-MM-dd") } else { "N/A" }

    # Native CPU Thermal & Clock Telemetry
    $tz = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
    $cpuTempC = if ($tz -and $tz.CurrentTemperature) { [math]::Round(($tz.CurrentTemperature - 2732) / 10, 1) } else { 0 }
    $cpuFreqMHz = 0
    try {
        $freqCounter = (Get-Counter '\Processor Information(*)\Processor Frequency' -ErrorAction SilentlyContinue).CounterSamples | Where-Object { $_.InstanceName -eq '_total' } | Select-Object -ExpandProperty CookedValue
        if ($freqCounter) { $cpuFreqMHz = [math]::Round($freqCounter) }
    } catch {}

    # NVIDIA Deep Telemetry
    $gpuDriver = "N/A"
    $gpuTemp = 0
    $gpuPowerW = 0.0
    $gpuVramTotalMB = 0
    $gpuVramUsedMB = 0
    $gpuMemClockMHz = 0
    $gpuCoreClockMHz = 0
    $gpuThrottle = "None"
    if ($hasNvidia) {
        try {
            $nvDeep = nvidia-smi --query-gpu=driver_version,temperature.gpu,memory.total,memory.used,clocks.current.graphics,clocks.current.memory,power.draw,pcie.link.gen.current,pcie.link.width.current,clocks_throttle_reasons.active --format=csv,noheader,nounits 2>$null
            if ($nvDeep) {
                $dp = $nvDeep.Trim() -split ','
                if ($dp.Count -ge 10) {
                    $gpuDriver = $dp[0].Trim()
                    $gpuTemp = [int]$dp[1].Trim()
                    $gpuVramTotalMB = [int]$dp[2].Trim()
                    $gpuVramUsedMB = [int]$dp[3].Trim()
                    $gpuCoreClockMHz = [int]$dp[4].Trim()
                    $gpuMemClockMHz = [int]$dp[5].Trim()
                    $gpuPowerW = [double]$dp[6].Trim()
                    $pcieLink = "Gen$($dp[7].Trim()) x$($dp[8].Trim())"
                    $gpuThrottle = $dp[9].Trim()
                }
            }
        } catch {}
    }

    # Physical Storage SMART
    $diskModel = "NVMe SSD"
    $diskHealth = "OK"
    $diskWear = 0
    $diskTemp = 0
    try {
        $pd = Get-PhysicalDisk | Select-Object -First 1
        $rc = Get-StorageReliabilityCounter -PhysicalDisk $pd -ErrorAction SilentlyContinue
        if ($pd) {
            $diskModel = $pd.FriendlyName
            $diskHealth = $pd.HealthStatus
        }
        if ($rc) {
            $diskWear = $rc.Wear
            $diskTemp = $rc.Temperature
        }
    } catch {}

    return [PSCustomObject]@{
        Manufacturer    = $mfg
        Model           = $model
        BoardMfg        = $boardMfg
        BoardProduct    = $boardProd
        BiosVersion     = $biosVer
        BiosDate        = $biosDate
        CpuName         = $cpuName
        CpuTempC        = $cpuTempC
        CpuFreqMHz      = $cpuFreqMHz
        HasNvidia       = $hasNvidia
        HasAmd          = $hasAmd
        DgpuName        = $dgpuName
        GpuDriver       = $gpuDriver
        GpuTemp         = $gpuTemp
        GpuPowerW       = $gpuPowerW
        GpuVramTotalMB  = $gpuVramTotalMB
        GpuVramUsedMB   = $gpuVramUsedMB
        GpuMemClockMHz  = $gpuMemClockMHz
        GpuCoreClockMHz = $gpuCoreClockMHz
        GpuThrottle     = $gpuThrottle
        GpuPcieLink     = $pcieLink
        FullCapMwh      = $fullCapMwh
        DesignCapMwh    = $designCapMwh
        HealthPct       = $healthPct
        TotalRamMB      = $totalRamMB
        TotalRamGB      = $totalRamGB
        RamSpeedMTs     = $ramSpeed
        RamModules      = $ramModules
        DiskModel       = $diskModel
        DiskHealth      = $diskHealth
        DiskWearPct     = $diskWear
        DiskTempC       = $diskTemp
        GpuList         = $gpus
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
    try { $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1 } catch {}

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

if ($ShowUi -or ($MyInvocation.InvocationName -and $MyInvocation.InvocationName -ne '.')) {
    $p = Get-HardwareProfile
    $m = Get-LiveMetrics -HardwareProfile $p
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "                  OMNI - NATIVE DEEP HARDWARE & SENSOR MATRIX" -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " System Model   : $($p.Manufacturer) $($p.Model)" -ForegroundColor White
    Write-Host " Motherboard    : $($p.BoardMfg) $($p.BoardProduct) | BIOS $($p.BiosVersion) ($($p.BiosDate))" -ForegroundColor White
    Write-Host " CPU Details    : $($p.CpuName)" -ForegroundColor White
    $tempStr = if ($p.CpuTempC -gt 0) { "$($p.CpuTempC) C" } else { "Active" }
    $freqStr = if ($p.CpuFreqMHz -gt 0) { "@ $($p.CpuFreqMHz) MHz" } else { "" }
    Write-Host " CPU Thermals   : Thermal Zone $tempStr $freqStr (Load: $($m.CpuLoad)%)" -ForegroundColor White
    Write-Host " Memory (RAM)   : $($p.TotalRamGB) GB Total | $($p.RamSpeedMTs) MT/s Clock Speed" -ForegroundColor White
    if ($p.RamModules) {
        foreach ($mod in $p.RamModules) {
            Write-Host "   Module       : $($mod.Bank) - $($mod.Manufacturer) $($mod.PartNumber) ($($mod.CapacityGB) GB @ $($mod.SpeedMTs) MT/s)" -ForegroundColor Gray
        }
    }
    if ($p.HasNvidia) {
        Write-Host " Primary GPU    : $($p.DgpuName) (Driver $($p.GpuDriver))" -ForegroundColor White
        Write-Host " GPU Telemetry  : $($p.GpuTemp) C | $($p.GpuPowerW) W | VRAM: $($p.GpuVramUsedMB) MB / $($p.GpuVramTotalMB) MB | Mem: $($p.GpuMemClockMHz) MHz" -ForegroundColor White
        Write-Host " GPU PCIe Link  : $($p.GpuPcieLink) | Throttle State: $($p.GpuThrottle)" -ForegroundColor White
    } else {
        Write-Host " Primary GPU    : Integrated Graphics" -ForegroundColor White
    }
    Write-Host " NVMe Storage   : $($p.DiskModel) | $($p.DiskHealth) (Wear: $($p.DiskWearPct)% | $($p.DiskTempC) C)" -ForegroundColor White
    Write-Host " Battery Health : $($p.HealthPct)% ($($p.FullCapMwh) mWh / $($p.DesignCapMwh) mWh)" -ForegroundColor White
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " Live RAM Used  : $($m.UsedRamGB) GB / $($m.TotalRamGB) GB ($($m.RamPercent)%)" -ForegroundColor White
    $pwrStr = if ($m.PowerOnline) { "AC Connected" } else { "Battery Power ($($m.DischargeWatts) W)" }
    Write-Host " Power Source   : $pwrStr" -ForegroundColor White
    Write-Host "================================================================================" -ForegroundColor Cyan
}

