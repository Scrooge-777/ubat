@echo off
title Stop Battery Drain Logger
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0logger\StopLogger.ps1"
pause
