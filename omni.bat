@echo off
setlocal
title OMNI - System Hardware Telemetry & Optimizer Engine

if "%1"=="--menu" goto RunMenu
if "%1"=="-m" goto RunMenu
if "%1"=="-Menu" goto RunMenu
if "%1"=="/menu" goto RunMenu

:: Launch flagship terminal UI directly
python "%~dp0tui\ubat_tui.py" %*
if %ERRORLEVEL% EQU 0 exit /b

:RunMenu
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ubat.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    pause
)
exit /b
