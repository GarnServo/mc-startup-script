@echo off
title Checking dependencies...
set scriptVersion=v1.2.1

REM Set restart counter variables
set "restartCount=0"
set "restartTime=No restarts yet..."

REM Check if the scripts utility folder exists, if not, create it.
if not exist "config" (
    mkdir config
    echo Created config folder
)

REM Check if script config file exists, if not, go to create it.
if not exist .\config\StartupScript.conf (
    goto initialSetup
) else (
    goto scriptUpdater
)

:scriptUpdater
title Checking for updates...

REM Check for updates to this script.
for /f "delims=" %%a in ('powershell -Command "(Invoke-WebRequest -Uri 'https://api.github.com/repos/GarnServo/mc-startup-script/releases/latest').Content | ConvertFrom-Json | Select -ExpandProperty tag_name"') do set latestVersion=%%a
echo Current script version: %scriptVersion%
echo Latest version from GitHub: %latestVersion%
REM Check if the script version is greater than the latest version
if %latestVersion% LEQ %scriptVersion% (
    echo You have the latest version of the script.
    goto initiateServer
) else (
    echo An update is available for the script ^(version "%latestVersion%"^).
    choice /C YN /M "Update script (Y/N): "
    if errorlevel 2 goto initiateServer
    if errorlevel 1 (
        echo @echo off > UpdateStartupScript.bat
        echo title Updating startup script... > UpdateStartupScript.bat
        echo powershell -Command "(Invoke-WebRequest -Uri 'https://github.com/GarnServo/mc-startup-script/releases/latest/download/START.bat' -OutFile 'START.bat')" >> UpdateStartupScript.bat
        echo start START.bat >> UpdateStartupScript.bat
        echo exit >> UpdateStartupScript.bat
        start UpdateStartupScript.bat
        exit
    )
)



:initiateServer
title Initiating server...
REM Cleanup updater
if exist UpdateStartupScript.bat del UpdateStartupScript.bat

REM Check EULA exists, if not, go to create it (and accept it)
if not exist "eula.txt" (
    goto eula
)

REM Reads the startup config file and fetches the variables from the config file and ignores "#" comments
for /f "tokens=*" %%i in ('type .\config\StartupScript.conf ^| findstr /V "^#"') do (
    for /f "tokens=1,2 delims==" %%a in ("%%i") do (
        set "%%a=%%b"
    )
)

REM Display config info on startup
echo [1;32m.............................................[0m
echo [1;4;33mServer[0m: [33m%serverName%[0m
echo [1;4;33mInitial RAM[0m: [33m%iniRam% [0;1m^| [1;4;33mMaximum RAM[0m: [33m%maxRam%[0m
echo [1;4;33mAuto-restart[0m: [33m%autoRestart%[0m
echo [1;4;33mServer GUI[0m: [33m%GUI%[0m
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
        echo -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions -XX:+AlwaysActAsServerClassMachine -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:NmethodSweepActivity=1 -XX:ReservedCodeCacheSize=400M -XX:NonNMethodCodeHeapSize=12M -XX:ProfiledCodeHeapSize=194M -XX:NonProfiledCodeHeapSize=194M -XX:-DontCompileHugeMethods -XX:MaxNodeLimit=240000 -XX:NodeLimitFudgeFactor=8000 -XX:+UseVectorCmov -XX:+PerfDisableSharedMem -XX:+UseFastUnorderedTimeStamps -XX:+UseCriticalJavaThreadPriority -XX:ThreadPriorityPolicy=1 -XX:AllocatePrefetchStyle=3 -XX:+UseG1GC -XX:MaxGCPauseMillis=130 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=28 -XX:G1HeapRegionSize=16M -XX:G1ReservePercent=20 -XX:G1MixedGCCountTarget=3 -XX:InitiatingHeapOccupancyPercent=10 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=0 -XX:SurvivorRatio=32 -XX:MaxTenuringThreshold=1 -XX:G1SATBBufferEnqueueingThresholdPercent=30 -XX:G1ConcMarkStepDurationMillis=5 -XX:G1ConcRefinementServiceIntervalMillis=150 -XX:G1ConcRSHotCardLimit=16
        set args=@.\config\jvm_args.txt
    ) > .\config\jvm_args.txt
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
java %RAM% %args% -jar %serverName% %GUI%
echo.
echo.
set /A restartCount+=1
set "restartTime=%TIME%, %DATE%"
echo Server has closed or crashed...restarting now...
echo Server has restarted %restartCount% times. Last restart: %restartTime%
goto scriptUpdater

:runNoRestart
title %Title%
java %RAM% %args% -jar %serverName% %GUI%
echo.
echo.
echo Server has closed or crashed.
CHOICE /N /C YN /M "Do you want to restart the server? (Y/N): "
if %errorlevel%==1 goto scriptUpdater
if %errorlevel%==2 (
    echo You chose not to restart the server.
    echo Press any key to exit.
    pause >nul
    exit /b
)




:initialSetup
title Running through initial config...
:serverName
cls
REM Let user define the title of their server jar file
echo [1mEnter the filename of your server .jar file [0m(Eg: purpur-1.20.4-2155.jar)
set /p "serverName=Server .jar name: "
if "%serverName:~-4%" neq ".jar" (
    echo Error: File must end with .jar extension.
    goto :serverName
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
REM Let user configure maximum RAM for the server.
echo [1mEnter Maximum Ram Allocation for Minecraft Server. [0m^(Eg:1G,1024M^)
echo ^(Must have M or G for Megabytes and Gigabytes respectively^)
set /p maxRam=Maximum RAM: 
if "%maxRam%" == "" set maxRam=1G
if defined maxRam (
    if not "%maxRam:~-1%"=="M" if not "%maxRam:~-1%"=="G" (
        echo Invalid input, input should be one or more numbers followed by "M" or "G".
        echo Press any key to retry...
        pause >nul
        goto maxRam
    )
)
goto iniRam
:iniRam
cls
REM Let user configure maximum initial RAM for the server. Should be same as max RAM, unless on low-RAM system.
echo [1mEnter Initial RAM Allocation for Minecraft Server. [0m^(Eg:1G,1024M^)
echo ^(Must have M or G for Megabytes and Gigabytes respectively.^)
set /p iniRam=Initial RAM: 
if "%iniRam%" == "" set iniRam=1G
if defined iniRam (
    if not "%iniRam:~-1%"=="M" if not "%iniRam:~-1%"=="G" (
        echo Invalid input, input should be one or more numbers followed by "M" or "G".
        echo Press any key to retry...
        pause >nul
        goto iniRam
    )
)
cls
REM Let user configure whether the server auto-restarts
echo [1mAuto-restart the Minecraft Server on crash or ^/restart[0m
CHOICE /N /C:YN /M "Auto-restart (Y/N): "
if %errorlevel%==1 set autoRestart=true
if %errorlevel%==2 set autoRestart=false
cls
REM Let user configure whether to use customised JVM arguments
echo [1mUse optimised JVM args?[0m
CHOICE /N /C:YN /M "Optimised JVM args (Y/N): "
if %errorlevel%==1 set optArgs=true
if %errorlevel%==2 set optArgs=false
cls
REM Let user configure whether to use default server GUI
echo [1mEnable server GUI?[0m
CHOICE /N /T 5 /D N /C:YN /M "GUI (Y/N): "
if %errorlevel%==1 set GUI=true
if %errorlevel%==2 set GUI=false
REM Confirm user choices
cls
echo [1;32m.............................................[0m
echo [1;4;33mServer[0m: [33m%serverName%[0m
echo [1;4;33mInitial RAM[0m: [33m%iniRam% [0;1m^| [1;4;33mMaximum RAM[0m: [33m%maxRam%[0m
echo [1;4;33mAuto-restart[0m: [33m%autoRestart%[0m
echo [1;4;33mServer GUI[0m: [33m%GUI%[0m
echo [1;32m.............................................[0m
CHOICE /N /C:YN /M "These are your desired settings? (Y/N): "
if %errorlevel%==1 goto saveSetup
if %errorlevel%==2 goto initialSetup

:saveSetup
title Saving setup...
echo #  > .\config\StartupScript.conf
echo # --------------------------------------------------------------------------------------------------------------------------- >> .\config\StartupScript.conf
echo #                                         Change the values in the section below >> .\config\StartupScript.conf
echo # --------------------------------------------------------------------------------------------------------------------------- >> .\config\StartupScript.conf
echo #  >> .\config\StartupScript.conf
echo # Define server file name here >> .\config\StartupScript.conf
echo serverName=%serverName%>> .\config\StartupScript.conf
echo. >> .\config\StartupScript.conf
echo # Define RAM allocation amount here you can use G for Gigabytes or M for Megabytes >> .\config\StartupScript.conf
echo # Maximum memory allocation pool >> .\config\StartupScript.conf
echo maxRam=%maxRam%>> .\config\StartupScript.conf
echo # Initial memory allocation pool >> .\config\StartupScript.conf
echo iniRam=%iniRam%>> .\config\StartupScript.conf
echo.  >> .\config\StartupScript.conf
echo # Restart mode on crash or /restart ^(true/false^) default = true >> .\config\StartupScript.conf
echo autoRestart=%autoRestart%>> .\config\StartupScript.conf
echo.  >> .\config\StartupScript.conf
echo # Vanilla server GUI ^(true/false^) >> .\config\StartupScript.conf
echo GUI=%GUI%>> .\config\StartupScript.conf
echo.  >> .\config\StartupScript.conf
echo # Set console title here >> .\config\StartupScript.conf
echo Title=Minecraft Server >> .\config\StartupScript.conf
echo.  >> .\config\StartupScript.conf
echo Config variables successfully saved to StartupScript.conf

REM Write Java Args to .\config\jvm_args.txt
if %optArgs%==true (
    echo -XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions -XX:+AlwaysActAsServerClassMachine -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:NmethodSweepActivity=1 -XX:ReservedCodeCacheSize=400M -XX:NonNMethodCodeHeapSize=12M -XX:ProfiledCodeHeapSize=194M -XX:NonProfiledCodeHeapSize=194M -XX:-DontCompileHugeMethods -XX:MaxNodeLimit=240000 -XX:NodeLimitFudgeFactor=8000 -XX:+UseVectorCmov -XX:+PerfDisableSharedMem -XX:+UseFastUnorderedTimeStamps -XX:+UseCriticalJavaThreadPriority -XX:ThreadPriorityPolicy=1 -XX:AllocatePrefetchStyle=3 -XX:+UseG1GC -XX:MaxGCPauseMillis=130 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=28 -XX:G1HeapRegionSize=16M -XX:G1ReservePercent=20 -XX:G1MixedGCCountTarget=3 -XX:InitiatingHeapOccupancyPercent=10 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=0 -XX:SurvivorRatio=32 -XX:MaxTenuringThreshold=1 -XX:G1SATBBufferEnqueueingThresholdPercent=30 -XX:G1ConcMarkStepDurationMillis=5 -XX:G1ConcRefinementServiceIntervalMillis=150 -XX:G1ConcRSHotCardLimit=16>> .\config\jvm_args.txt
) else (
    echo. >> .\config\jvm_args.txt
)
echo [32mJVM arguments file successfully created[0m
goto eula

:eula
REM Set EULA to true
cd %localhost%
if exist eula.txt (del eula.txt)
echo #By changing the setting below to TRUE you are indicating your agreement to our EULA ^(https://aka.ms/MinecraftEULA^)^.>> eula.txt
echo #Auto-accepted EULA with startup script made by Garn Servo. >> eula.txt
echo eula=true>> eula.txt
echo [32mEULA created and accepted.[0m
cls
goto scriptUpdater