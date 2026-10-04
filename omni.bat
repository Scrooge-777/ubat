@echo off
setlocal
title OMNI - System Hardware Telemetry & Optimizer Engine

if "%1"=="--menu" goto RunMenu
if "%1"=="-m" goto RunMenu
if "%1"=="-Menu" goto RunMenu
if "%1"=="/menu" goto RunMenu

:: Launch flagship terminal UI directly
where python >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    python -c "import rich, psutil" 2>nul
    if %ERRORLEVEL% NEQ 0 (
        if exist "%~dp0requirements.txt" (
            python -m pip install -r "%~dp0requirements.txt" --quiet
        ) else (
            python -m pip install rich psutil --quiet
        )
    )
    python "%~dp0tui\ubat_tui.py" %*
    if %ERRORLEVEL% EQU 0 exit /b
)

:RunMenu
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ubat.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    pause
)
exit /b
