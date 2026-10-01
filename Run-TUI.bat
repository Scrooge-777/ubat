@echo off
title OMNI - Live Hardware & System Monitor
cls
python "%~dp0tui\ubat_tui.py"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Failed to start Rich Terminal UI. Ensure Python and 'rich' are installed.
    pause
)
