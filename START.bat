@echo off
setlocal
title Checking dependencies...

REM ============================================================
REM  mc-startup-script launcher (v2.0.0)
REM  This file only bootstraps config\core.ps1, which holds all
REM  the actual logic. Distribute just this .bat - it fetches the
REM  core script itself on first run.
REM  Repo: https://github.com/GarnServo/mc-startup-script
REM ============================================================

set "repo=GarnServo/mc-startup-script"
set "coreScript=.\config\core.ps1"

if not exist ".\config" mkdir ".\config" >nul 2>&1

if not exist "%coreScript%" (
    echo Core script not found - fetching it now...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "try { (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/%repo%/main/config/core.ps1' -UseBasicParsing).Content | Set-Content -Path '%coreScript%' -Encoding UTF8 } catch { exit 1 }"
    if errorlevel 1 (
        echo.
        echo Failed to download config\core.ps1 - check your internet connection
        echo or download it manually from:
        echo https://github.com/%repo%
        echo.
        pause
        exit /b 1
    )
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%coreScript%"
exit /b %errorlevel%