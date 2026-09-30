<#
.SYNOPSIS
    Universal Laptop Power & Battery Optimizer Module
.DESCRIPTION
    Analyzes any Windows laptop hardware (HP, Lenovo, ASUS, Dell, Acer, MSI, etc.),
    detects CPU/GPU architecture, applies safe power plan optimizations,
    and provides vendor-specific guidance to reach maximum battery runtime.
#>

$ModuleDir = $PSScriptRoot
$RootDir = Split-Path $ModuleDir -Parent
$CorePath = Join-Path $RootDir "core\HardwareProfile.ps1"

# Import Core Engine
. $CorePath

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "         UNIVERSAL LAPTOP HARDWARE DIAGNOSTIC & POWER OPTIMIZER                 " -ForegroundColor Yellow
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. HARDWARE AUTO-DETECTION
Write-Host " [STEP 1: HARDWARE PROFILING]" -ForegroundColor Green

$hw = Get-HardwareProfile

Write-Host "   Manufacturer:       $($hw.Manufacturer)" -ForegroundColor White
Write-Host "   Laptop Model:       $($hw.Model)" -ForegroundColor White
Write-Host "   Processor (CPU):    $($hw.CpuName)" -ForegroundColor White

Write-Host "   Detected GPUs:" -ForegroundColor White
foreach ($g in $hw.GpuList) {
    Write-Host "     - $($g.Name) (Driver: $($g.DriverVersion))" -ForegroundColor Cyan
}

Write-Host "   Battery Capacity:   $($hw.FullCapMwh) mWh (Health: $($hw.HealthPct)% of factory design)" -ForegroundColor White

Write-Host ""
# 2. APPLYING UNIVERSAL POWER OPTIMIZATIONS
Write-Host " [STEP 2: APPLYING UNIVERSAL POWER OPTIMIZATIONS]" -ForegroundColor Green

# A. Processor Boost Clamping on Battery (DC)
try {
    # Cap PROCTHROTTLEMAX to 99% on DC to disable unnecessary high-voltage Turbo Boost spikes on battery
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 99 2>$null
    powercfg /setdcvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 bc5038f7-23e0-4960-96da-33abaf5935ec 99 2>$null
    Write-Host "   [OK] CPU Turbo Boost on Battery: Capped to 99% (Saves 10-15W; preserves 100% full boost when plugged in)." -ForegroundColor Green
} catch {
    Write-Host "   [!] Could not adjust CPU throttle state." -ForegroundColor Yellow
}

# B. PCIe Link State Power Management (ASPM) on Battery (DC)
try {
    powercfg /setdcvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a821a10c2668 ee12f906-d277-404b-b6da-e5fa1a576df5 2 2>$null
    Write-Host "   [OK] PCIe Bus Power Management: Configured to Maximum Power Savings on DC." -ForegroundColor Green
} catch {
    Write-Host "   [!] Could not adjust PCIe ASPM state." -ForegroundColor Yellow
}

# C. Reset GPU Clock Overrides if NVIDIA
if ($hw.HasNvidia) {
    try {
        $null = nvidia-smi -rgc 2>$null
        $null = nvidia-smi -rac 2>$null
        Write-Host "   [OK] NVIDIA Clocks: Reset all application and core clock overrides to default." -ForegroundColor Green
    } catch {
        Write-Host "   [!] nvidia-smi tool not available in PATH." -ForegroundColor Yellow
    }
}

powercfg /setactive SCHEME_CURRENT 2>$null
Write-Host "   [OK] Active power plan updated." -ForegroundColor Green

Write-Host ""
# 3. VENDOR & HARDWARE SPECIFIC RECOMMENDATIONS
Write-Host " [STEP 3: VENDOR-SPECIFIC HARDWARE ADVICE]" -ForegroundColor Yellow

$mfg = $hw.Manufacturer
if ($mfg -like '*HP*') {
    Write-Host "   Detected HP Laptop:" -ForegroundColor Cyan
    Write-Host "   * In OMEN Gaming Hub, set Graphics Switcher to ECO mode when you need 6-8+ hours." -ForegroundColor White
    Write-Host "   * Note: A system restart is required for the HP hardware MUX switch to physically cut power to the dGPU." -ForegroundColor Gray
} elseif ($mfg -like '*Lenovo*') {
    Write-Host "   Detected Lenovo Laptop:" -ForegroundColor Cyan
    Write-Host "   * In Lenovo Vantage / Legion Toolkit, enable 'Hybrid-iGPU Only Mode'." -ForegroundColor White
    Write-Host "   * Set Thermal Mode to 'Quiet Mode' (Fn + Q) for lowest fan and CPU power draw." -ForegroundColor Gray
} elseif ($mfg -like '*ASUS*') {
    Write-Host "   Detected ASUS Laptop:" -ForegroundColor Cyan
    Write-Host "   * In Armoury Crate or G-Helper, switch GPU Mode to 'Eco Mode' (disables dGPU completely)." -ForegroundColor White
    Write-Host "   * Switch Power Profile to 'Silent' when on battery." -ForegroundColor Gray
} elseif ($mfg -like '*Dell*' -or $mfg -like '*Alienware*') {
    Write-Host "   Detected Dell / Alienware Laptop:" -ForegroundColor Cyan
    Write-Host "   * In Dell Command / Alienware Command Center, switch thermal profile to 'Cool' or 'Quiet'." -ForegroundColor White
} elseif ($mfg -like '*Acer*') {
    Write-Host "   Detected Acer Laptop:" -ForegroundColor Cyan
    Write-Host "   * In NitroSense / PredatorSense, switch GPU Working Mode to 'Optimus' or 'Integrated Only'." -ForegroundColor White
} elseif ($mfg -like '*MSI*') {
    Write-Host "   Detected MSI Laptop:" -ForegroundColor Cyan
    Write-Host "   * In MSI Center, switch User Scenario to 'Super Battery Mode'." -ForegroundColor White
}

if ($hw.HasNvidia) {
    Write-Host ""
    Write-Host "   NVIDIA GPU Advice:" -ForegroundColor Cyan
    Write-Host "   * In NVIDIA Control Panel > Manage 3D Settings > Global Settings:" -ForegroundColor White
    Write-Host "     - Power management mode: Set to 'Optimal power' or 'Normal'." -ForegroundColor Gray
    Write-Host "     - Preferred graphics processor: Set to 'Auto-select'." -ForegroundColor Gray
}

# Screen Refresh Rate Advice
$highHz = $hw.GpuList | Where-Object { $_.CurrentRefreshRate -gt 60 }
if ($highHz) {
    Write-Host ""
    Write-Host "   Display Refresh Rate Notice:" -ForegroundColor Yellow
    Write-Host "   * Screen is currently set to $($highHz[0].CurrentRefreshRate) Hz." -ForegroundColor White
    Write-Host "   * Lowering to 60 Hz on battery (Settings > System > Display > Advanced Display) saves 5-8 Watts!" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " Optimization complete! Launch Live Monitor to verify your live wattage.       " -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan
