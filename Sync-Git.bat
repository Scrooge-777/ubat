@echo off
setlocal
cd /d "%~dp0"
echo ========================================================
echo        UBAT GIT REPOSITORY SYNCHRONIZATION
echo ========================================================
echo.
echo 1. Pulling latest remote changes...
git pull origin main --rebase

echo.
echo 2. Staging all local changes...
git add -A

git diff-index --quiet HEAD --
if %ERRORLEVEL% EQU 0 (
    echo [INFO] No local changes to commit. Everything is up to date.
    echo.
    goto PushCheck
)

echo.
echo 3. Committing changes...
set /p commit_msg="Enter commit message (press Enter for auto-timestamp): "
if "%commit_msg%"=="" (
    for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set dt=%%I
    set commit_msg=sync: auto-update repository telemetry and configs
)
git commit -m "%commit_msg%"

:PushCheck
echo.
echo 4. Pushing to GitHub (origin/main)...
git push origin main

echo.
if %ERRORLEVEL% EQU 0 (
    echo ========================================================
    echo  [OK] Local and GitHub (Scrooge-777/ubat) are in sync!
    echo ========================================================
) else (
    echo ========================================================
    echo  [ERROR] Push failed. Please check your network/token.
    echo ========================================================
)
echo.
pause
