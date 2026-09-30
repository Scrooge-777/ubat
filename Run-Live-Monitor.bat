@echo off
title ubat - Live Monitor
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0monitor\LiveMonitor.ps1" -InitialView "menu" -Interval 1
pause
