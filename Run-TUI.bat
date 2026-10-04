@echo off
title OMNI - Live Hardware & System Monitor
cls

:: Check if Python is accessible
where python >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Python is not installed or not in PATH.
    echo Please install Python 3.9+ from https://python.org or the Microsoft Store.
    echo.
    pause
    exit /b 1
)

:: Verify dependencies
python -c "import sys, rich, psutil; sys.exit(0)" 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [INFO] Installing required dependencies (rich, psutil)...
    if exist "%~dp0requirements.txt" (
        python -m pip install -r "%~dp0requirements.txt" --quiet
    ) else (
        python -m pip install rich psutil --quiet
    )
)

python "%~dp0tui\ubat_tui.py" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Failed to start Rich Terminal UI. Ensure Python 3.9+ and required packages are installed.
    pause
)

