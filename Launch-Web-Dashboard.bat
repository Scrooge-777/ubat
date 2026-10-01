@echo off
title UBAT Pro - Web Dashboard Launcher
echo Starting UBAT Web Telemetry Server...
start "" /b python "%~dp0web\server.py"
timeout /t 1 /nobreak >nul
echo Opening Dashboard in your browser...
start http://localhost:5050
echo.
echo ==============================================================
echo  UBAT Web Telemetry Dashboard is running at:
echo  http://localhost:5050
echo ==============================================================
echo Keep this window open or minimize it.
echo Press any key to stop the web server and exit.
pause >nul
taskkill /f /im python.exe /fi "WINDOWTITLE eq UBAT*" >nul 2>&1
exit /b
