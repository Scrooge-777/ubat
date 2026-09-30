@echo off
title Universal Laptop Battery & Power Optimizer
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0optimizer\PowerOptimizer.ps1"
echo.
pause
