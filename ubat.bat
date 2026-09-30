@echo off
setlocal
title ubat - Universal Battery Tool
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ubat.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    pause
)
exit /b
