@echo off
title Checking dependencies...
set scriptVersion=v1.3.3
set currentConfigVersion=v1.3.0
set "configFile=.\config\StartupScript.conf"

REM Set restart counter variables
set "restartCount=0"
set "restartTime=No restarts yet..."

REM Check if the scripts utility folder exists, if not, create it.
mkdir "config" >nul 2>&1

REM Check if the config file exists, if not, go to initial setup
if not exist "%configFile%" (
    goto initialSetup
)
REM Check configuration version
for /f "tokens=1,* delims==" %%a in ('more +1 "%configFile%"') do (
    if "%%a"=="configVersion" (
        set "configVersion=%%b"
        goto versionCheck
    )
)
:versionCheck
REM Compare with expected version
if "%configVersion%" NEQ "%currentConfigVersion%" (
    echo [1;31mFollowing an update, your configuration file is outdated.[0m
    echo [1mPress any key to update your configuration...
    pause >nul
    goto initialSetup
) else (
    goto scriptUpdater
)

:scriptUpdater
title Checking for updates...
REM Fetch the latest version using PowerShell and GitHub API
for /f "usebackq tokens=*" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "(Invoke-RestMethod 'https://api.github.com/repos/GarnServo/mc-startup-script/releases/latest').tag_name"`) do (
    set "latestVersion=%%a"
)
REM Validate if the latest version was fetched
if not defined latestVersion (
    echo Failed to fetch the latest version. Proceeding with current script.
    goto initiateServer
)
echo Current script version: %scriptVersion%
echo Latest version: %latestVersion%
REM Compare script versions and check if update is needed
if "%latestVersion%" LEQ "%scriptVersion%" (
    echo You have the latest version of the script.
    goto initiateServer
)
REM Prompt the user for an update if needed
echo An update to version "%latestVersion%" is available.
choice /C YN /M "Update the script to version %latestVersion%? (Y/N): "
if %errorlevel%==2 goto initiateServer
REM If the user chooses to update, perform the update in a daughter script
echo Updating to version %latestVersion%...
(
    echo @echo off
    echo title Updating startup script...
    echo powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "(Invoke-WebRequest -Uri 'https://github.com/GarnServo/mc-startup-script/releases/latest/download/START.bat' -OutFile 'START.bat')"
    echo start START.bat
    echo exit
) > UpdateStartupScript.bat
start /b UpdateStartupScript.bat
exit


:initiateServer
title Initiating server...
REM Cleanup updater
del /q UpdateStartupScript.bat >nul 2>&1
REM Check for EULA
if not exist "eula.txt" goto eula

REM Reads the startup config file and fetches the variables from the config file and ignores "#" comments
for /f "usebackq tokens=1,2 delims==" %%a in (`findstr /v "^#" "%configFile%"`) do (
    set "%%a=%%b"
)

REM Display config info on startup
echo [1;32m.............................................[0m
echo [1;4;33mServer[0m: [33m%serverName%[0m
echo [1;4;33mInitial RAM[0m: [33m%iniRam% [0;1m^| [1;4;33mMaximum RAM[0m: [33m%maxRam%[0m
echo [1;4;33mAuto-restart[0m: [33m%autoRestart%[0m
echo [1;4;33mServer GUI[0m: [33m%GUI%[0m
if not "%webhookURL%"=="" (
    echo [1;4;33mDiscord Webhook[0m: [33mconfigured[0m
) else (
    echo [1;4;33mDiscord Webhook[0m: [33mnot configured[0m
)
echo [1;32m.............................................[0m
echo Server initialising...

REM Set RAM values
set RAM=-Xmx%maxRam% -Xms%iniRam%
REM Set GUI value
if "%GUI%"=="true" set GUI=
if "%GUI%"=="false" set GUI=--nogui
REM Check for JVM args file
if exist ".\config\jvm_args.txt" (
    echo [32mJVM args file found.[0m
    set args=@.\config\jvm_args.txt
) else (
    echo [31mJVM args file not found![0m
    (
        echo -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions -XX:+AlwaysActAsServerClassMachine -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:NmethodSweepActivity=1 -XX:ReservedCodeCacheSize=400M -XX:NonNMethodCodeHeapSize=12M -XX:ProfiledCodeHeapSize=194M -XX:NonProfiledCodeHeapSize=194M -XX:-DontCompileHugeMethods -XX:MaxNodeLimit=240000 -XX:NodeLimitFudgeFactor=8000 -XX:+UseVectorCmov -XX:+PerfDisableSharedMem -XX:+UseFastUnorderedTimeStamps -XX:+UseCriticalJavaThreadPriority -XX:ThreadPriorityPolicy=1 -XX:AllocatePrefetchStyle=3 -XX:+UseG1GC -XX:MaxGCPauseMillis=130 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=28 -XX:G1HeapRegionSize=16M -XX:G1ReservePercent=20 -XX:G1MixedGCCountTarget=3 -XX:InitiatingHeapOccupancyPercent=10 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=0 -XX:SurvivorRatio=32 -XX:MaxTenuringThreshold=1 -XX:G1SATBBufferEnqueueingThresholdPercent=30 -XX:G1ConcMarkStepDurationMillis=5 -XX:G1ConcRefinementServiceIntervalMillis=150 -XX:G1ConcRSHotCardLimit=16> .\config\jvm_args.txt
        set args=@.\config\jvm_args.txt
    )
    echo [32mJVM args file created successfully.[0m
)
REM Check auto-restart value
if "%autoRestart%"=="true" (
    GOTO runRestart
) ELSE (
    GOTO runNoRestart
)

:runRestart
title %Title% ^| Restarted: %restartCount% times
REM Send start message if webhook URL is set
if defined webhookURL (
    curl -H "Content-Type: application/json" -X POST -d "{\"content\":\"%webhookMessageStart%\"}" %webhookURL%
)
REM Start the server
java %RAM% %args% -jar %serverName% %GUI%
echo.
echo.
set /A restartCount+=1
set "restartTime=%TIME%, %DATE%"
echo Server has closed or crashed...restarting now...
echo Server has restarted %restartCount% times. Last restart: %restartTime%
REM Send stop message if webhook URL is set
if defined webhookURL (
    curl -H "Content-Type: application/json" -X POST -d "{\"content\":\"%webhookMessageStop%\"}" %webhookURL%
)
goto scriptUpdater

:runNoRestart
title %Title%
REM Send start message if webhook URL is set
if defined webhookURL (
    curl -H "Content-Type: application/json" -X POST -d "{\"content\":\"%webhookMessageStart%\"}" %webhookURL%
)
REM Start the server
java %RAM% %args% -jar %serverName% %GUI%
echo.
echo.
REM Send stop message if webhook URL is set
if defined webhookURL (
    curl -H "Content-Type: application/json" -X POST -d "{\"content\":\"%webhookMessageStop%\"}" %webhookURL%
)
echo Server has closed or crashed.
REM Prompt for restart decision
CHOICE /N /C YN /M "Do you want to restart the server? (Y/N): "
if errorlevel 2 (
    echo You chose not to restart the server.
    echo Press any key to exit.
    pause >nul
    exit /b
)
REM Proceed to scriptUpdater if restart is chosen
goto scriptUpdater



:initialSetup
title Running through initial config...
:serverName
cls
REM Prompt user for server .jar file
echo [1mEnter the filename of your server .jar file [0m (e.g., purpur-1.20.4-2155.jar)
set /p "serverName=Server .jar name: "
REM Append .jar if it's missing
if /i "%serverName:~-4%" neq ".jar" (
    set "serverName=%serverName%.jar"
)
REM Check if the file exists
if not exist "%serverName%" (
    echo Error: File "%serverName%" not found.
    echo Press any key to retry...
    pause >nul
    goto :serverName
)
goto :maxRam
:maxRam
cls
REM Prompt user for maximum RAM allocation
echo [1mEnter Maximum RAM Allocation for Minecraft Server:[0m (e.g., 1G, 1024M)
echo ^(Must end with "M" for Megabytes or "G" for Gigabytes^)
set /p "maxRam=Maximum RAM: "
if "%maxRam%"=="" set "maxRam=1G"
REM Validate RAM input
if not "%maxRam:~-1%"=="M" if not "%maxRam:~-1%"=="G" (
    echo Invalid input. Input should be one or more numbers followed by "M" or "G".
    echo Press any key to retry...
    pause >nul
    goto :maxRam
)
goto :iniRam
:iniRam
cls
REM Prompt user for initial RAM allocation
echo [1mEnter Initial RAM Allocation for Minecraft Server:[0m (e.g., 1G, 1024M)
echo ^(Must end with "M" for Megabytes or "G" for Gigabytes^)
set /p "iniRam=Initial RAM: "
if "%iniRam%"=="" set "iniRam=1G"
REM Validate RAM input
if not "%iniRam:~-1%"=="M" if not "%iniRam:~-1%"=="G" (
    echo Invalid input. Input should be one or more numbers followed by "M" or "G".
    echo Press any key to retry...
    pause >nul
    goto :iniRam
)
cls
REM Let user configure auto-restart
echo [1mAuto-restart the Minecraft Server on crash or ^/restart[0m
CHOICE /N /C YN /M "Auto-restart (Y/N): "
set "autoRestart=false"
if %errorlevel%==1 set "autoRestart=true"
cls
REM Let user configure JVM arguments
echo [1mUse optimised JVM args?[0m
CHOICE /N /C YN /M "Optimised JVM args (Y/N): "
set "optArgs=false"
if %errorlevel%==1 set "optArgs=true"
cls
REM Let user configure server GUI
echo [1mEnable server GUI?[0m
CHOICE /N /T 5 /D N /C YN /M "GUI (Y/N): "
set "GUI=false"
if %errorlevel%==1 set "GUI=true"
cls
REM Let user configure Discord webhooks
echo [1mEnable Discord webhooks?[0m
echo This will post stop/start notifications.
CHOICE /N /C YN /M "Proceed with Discord webhook setup? (Y/N)"
if %errorlevel%==1 (
    set /p "webhookURL=Enter the Discord webhook URL: "
) else (
    set "webhookURL="
)
REM Confirm user choices
cls
echo [1;32m.............................................[0m
echo [1;4;33mServer[0m: [33m%serverName%[0m
echo [1;4;33mInitial RAM[0m: [33m%iniRam% [0;1m^| [1;4;33mMaximum RAM[0m: [33m%maxRam%[0m
echo [1;4;33mAuto-restart[0m: [33m%autoRestart%[0m
echo [1;4;33mServer GUI[0m: [33m%GUI%[0m
if not "%webhookURL%"=="" (
    echo [1;4;33mDiscord Webhook[0m: [33mconfigured[0m
) else (
    echo [1;4;33mDiscord Webhook[0m: [33mnot configured[0m
)
echo [1;32m.............................................[0m
CHOICE /N /C:YN /M "These are your desired settings? (Y/N): "
if %errorlevel%==1 goto saveSetup
if %errorlevel%==2 goto initialSetup

:saveSetup
setlocal enabledelayedexpansion
title Saving setup...
(
    echo # Configuration File Version
    echo configVersion=%currentConfigVersion%
    echo #
    echo # ---------------------------------------------------------------------------------------------------------------------------
    echo #                                         General Server Options
    echo # ---------------------------------------------------------------------------------------------------------------------------
    echo #
    echo # Define server file name here
    echo serverName=%serverName%
    echo #
    echo # Define RAM allocation amount here you can use G for Gigabytes or M for Megabytes
    echo # Maximum memory allocation pool
    echo maxRam=%maxRam%
    echo # Initial memory allocation pool
    echo iniRam=%iniRam%
    echo #
    echo # Restart mode on crash or /restart ^(true/false^) default = true
    echo autoRestart=%autoRestart%
    echo #
    echo # Vanilla server GUI ^(true/false^)
    echo GUI=%GUI%
    echo #
    echo # Set console title here
    echo Title=Minecraft Server
    echo #
    echo # ---------------------------------------------------------------------------------------------------------------------------
    echo #                                         Discord Webhook Options
    echo # ---------------------------------------------------------------------------------------------------------------------------
    echo #
    echo # Follow the "Making a Webhook" section here: https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks
    echo #
    echo # Set the Discord webhook URL here
    echo webhookURL=%webhookURL%
    echo #
    echo # Set the message which is sent via webhook when the server stops
    echo webhookMessageStop=```\uD83C\uDFC1 The server has stopped.```
    echo #
    echo # Set the message which is sent via webhook when the server starts
    echo webhookMessageStart=```\uD83D\uDE80 The server has started.```
) > "%configFile%"
REM Check for success and print appropriate message
if %ERRORLEVEL% == 0 (
    echo Config variables successfully saved to %configFile%
) else (
    echo Failed to save configuration.
)
endlocal

REM Write Java Args to .\config\jvm_args.txt
if %optArgs%==true (
    (
        echo -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions -XX:+AlwaysActAsServerClassMachine -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:NmethodSweepActivity=1 -XX:ReservedCodeCacheSize=400M -XX:NonNMethodCodeHeapSize=12M -XX:ProfiledCodeHeapSize=194M -XX:NonProfiledCodeHeapSize=194M -XX:-DontCompileHugeMethods -XX:MaxNodeLimit=240000 -XX:NodeLimitFudgeFactor=8000 -XX:+UseVectorCmov -XX:+PerfDisableSharedMem -XX:+UseFastUnorderedTimeStamps -XX:+UseCriticalJavaThreadPriority -XX:ThreadPriorityPolicy=1 -XX:AllocatePrefetchStyle=3 -XX:+UseG1GC -XX:MaxGCPauseMillis=130 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=28 -XX:G1HeapRegionSize=16M -XX:G1ReservePercent=20 -XX:G1MixedGCCountTarget=3 -XX:InitiatingHeapOccupancyPercent=10 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=0 -XX:SurvivorRatio=32 -XX:MaxTenuringThreshold=1 -XX:G1SATBBufferEnqueueingThresholdPercent=30 -XX:G1ConcMarkStepDurationMillis=5 -XX:G1ConcRefinementServiceIntervalMillis=150 -XX:G1ConcRSHotCardLimit=16
    ) > .\config\jvm_args.txt
) else (
    echo. > .\config\jvm_args.txt
)
echo [32mJVM arguments file successfully created[0m

:eula
REM Set EULA to true
cd /d %localhost% 2>nul
(
    echo #By changing the setting below to TRUE you are indicating your agreement to our EULA ^(https://aka.ms/MinecraftEULA^)^.
    echo #Auto-accepted EULA with startup script made by Garn Servo.
    echo eula=true
) > eula.txt
cls
goto scriptUpdater