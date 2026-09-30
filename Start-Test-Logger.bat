@echo off
title Start Battery Drain Logger
echo Starting background battery logger...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""%~dp0logger\BackgroundLogger.ps1""'"
echo.
echo [OK] Background logger is running silently!
echo Every 30 seconds of test data is continuously saved into the 'logs/' folder.
echo.
timeout /t 3
