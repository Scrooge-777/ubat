@echo off
setlocal
title OMNI - HWiNFO64 Sensor Launcher

set "HWI_DIR=C:\Users\SREEHARAN\wallpaper\hwi_852"
set "HWI_EXE=%HWI_DIR%\HWiNFO64.exe"

if not exist "%HWI_EXE%" (
    echo [ERROR] HWiNFO64.exe not found at: %HWI_EXE%
    pause
    exit /b 1
)

tasklist /FI "IMAGENAME eq HWiNFO64.exe" 2>NUL | find /I /N "HWiNFO64.exe">NUL
if "%ERRORLEVEL%"=="0" (
    echo [INFO] HWiNFO64 is already active and streaming shared memory.
    timeout /t 2 >nul
    exit /b 0
)

echo ========================================================
echo        OMNI - LAUNCHING HWiNFO64 SENSOR ENGINE
echo ========================================================
echo.
echo Launching HWiNFO64 in background sensors mode...
echo Shared Memory is enabled for real-time OMNI bridge.
echo.

start "" "%HWI_EXE%" -sensorsonly
echo [OK] HWiNFO64 started in background.
timeout /t 2 >nul
exit /b 0
