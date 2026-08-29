@echo off
setlocal
title Checking dependencies...

REM ============================================================
REM  mc-startup-script launcher (v2.3.4)
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
        "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/%repo%/releases/latest' -UseBasicParsing; $asset = $release.assets | Where-Object { $_.name -eq 'core.ps1' }; if (-not $asset) { throw 'core.ps1 not found in the latest release' }; if (-not $asset.digest) { throw 'No checksum published for core.ps1 - refusing to install' }; $tmp = '%coreScript%.new'; Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -UseBasicParsing; $expected = $asset.digest -replace '^sha256:', ''; $actual = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash; if ($actual -ine $expected) { throw 'core.ps1 checksum mismatch - refusing to install' }; Move-Item -Force $tmp '%coreScript%' } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Remove-Item '%coreScript%.new' -Force -ErrorAction SilentlyContinue; exit 1 }"
    if errorlevel 1 (
        echo.
        echo Failed to fetch config\core.ps1 - check your internet connection
        echo or download it manually from the latest release:
        echo https://github.com/%repo%/releases/latest
        echo.
        pause
        exit /b 1
    )
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%coreScript%"
exit /b %errorlevel%