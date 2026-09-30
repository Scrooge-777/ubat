@echo off
title Battery Drain Analysis Report
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0analyzer\LogAnalyzer.ps1"
echo.
pause
