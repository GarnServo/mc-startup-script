#requires -Version 5.1
<#
    mc-startup-script core
    ---------------------------------------------------------------
    This file is bootstrapped and invoked by START.bat. It should
    not normally be run standalone, though it will work if you set
    $ScriptRoot manually below.

    Repo: https://github.com/GarnServo/mc-startup-script
#>

$ErrorActionPreference = 'Stop'
$CoreVersion   = 'v2.0.0'
$ConfigVersion = 2
$RepoSlug      = 'GarnServo/mc-startup-script'

$ScriptRoot = Split-Path -Parent $PSCommandPath           # ...\config
$ServerRoot = Split-Path -Parent $ScriptRoot               # server root, one level up
$ConfigPath = Join-Path $ScriptRoot 'StartupScript.json'
Set-Location $ServerRoot
Remove-Variable ScriptRoot

#region Helpers

function Write-Info    { param($Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Good    { param($Message) Write-Host $Message -ForegroundColor Green }
function Write-Warn2   { param($Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Bad     { param($Message) Write-Host $Message -ForegroundColor Red }
function Write-Rule    { Write-Host ('-' * 64) -ForegroundColor DarkGray }
function Write-Section {
    param([string]$Title, [string]$Subtitle)
    Write-Host ""
    Write-Host ("  {0}" -f $Title.ToUpper()) -ForegroundColor Cyan
    if ($Subtitle) { Write-Host ("  {0}" -f $Subtitle) -ForegroundColor DarkGray }
    Write-Rule
}
function Write-Brand {
    param([string]$Title = 'MINECRAFT SERVER CONTROL')
    Clear-Host
    Write-Host ""
    Write-Host ("  {0}" -f $Title) -ForegroundColor Cyan
    Write-Host ("  mc-startup-script {0}" -f $CoreVersion) -ForegroundColor DarkGray
    Write-Rule
}
function Write-StatusRow {
    param([string]$Label, [string]$Value, [ConsoleColor]$Color = [ConsoleColor]::White)
    Write-Host ("  {0,-16}" -f $Label) -ForegroundColor DarkGray -NoNewline
    Write-Host $Value -ForegroundColor $Color
}
function Read-YesNo {
    param([string]$Prompt, [bool]$Default = $false)
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host ("  {0} {1}" -f $Prompt, $hint)
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim() -match '^(?i:y|yes)$'
}
function Wait-ForEnter {
    param([string]$Prompt = 'Press Enter to continue')
    [void](Read-Host ("  {0} [Enter]" -f $Prompt))
}
function Show-ServerDashboard {
    param($Config, [int]$RestartCount)
    Write-Brand
    Write-Host "  SERVER STATUS" -ForegroundColor Cyan
    Write-Rule
    Write-StatusRow 'Server' $Config.serverJar
    Write-StatusRow 'Type' ("{0}{1}" -f $Config.serverType, $(if ($Config.mcVersion) { "  |  MC $($Config.mcVersion)" } else { '' }))
    Write-StatusRow 'Memory' "$($Config.iniRam) initial  |  $($Config.maxRam) max"
    Write-StatusRow 'Java' ("Java {0}" -f (Get-JavaMajorVersion -JavaExe $Config.javaPath))
    Write-StatusRow 'Auto-restart' $(if ($Config.autoRestart) { 'Enabled' } else { 'Ask on exit' }) $(if ($Config.autoRestart) { 'Green' } else { 'Yellow' })
    Write-StatusRow 'Restarts' $RestartCount
    Write-Host ""
    Write-Host "  Launching server..." -ForegroundColor Green
    Write-Host "  Server output will appear below." -ForegroundColor DarkGray
    Write-Host ""
}

# Compare version numbers numerically so v1.10.0 sorts after v1.9.0.
function Compare-ScriptVersion {
    param([string]$A, [string]$B)
    $an = ($A.TrimStart('v') -split '\.') | ForEach-Object { [int]($_ -replace '\D', '0') }
    $bn = ($B.TrimStart('v') -split '\.') | ForEach-Object { [int]($_ -replace '\D', '0') }
    $len = [Math]::Max($an.Count, $bn.Count)
    for ($i = 0; $i -lt $len; $i++) {
        $x = if ($i -lt $an.Count) { $an[$i] } else { 0 }
        $y = if ($i -lt $bn.Count) { $bn[$i] } else { 0 }
        if ($x -gt $y) { return 1 }
        if ($x -lt $y) { return -1 }
    }
    return 0
}
#endregion

#region Minecraft and Java requirements
# Minecraft 26.1+ uses the year-based version scheme and requires Java 25.
function Get-RequiredJavaMajor {
    param([string]$McVersion)
    if (-not $McVersion) { return $null }
    $parts = ($McVersion -split '\.') | ForEach-Object { [int]($_ -replace '\D', '0') }
    while ($parts.Count -lt 3) { $parts += 0 }
    $maj, $min, $pat = $parts[0], $parts[1], $parts[2]

    # Year-based releases.
    if ($maj -ge 26) { return 25 }

    # Older 1.x releases.
    if ($maj -eq 1 -and $min -ge 21)                          { return 21 }
    if ($maj -eq 1 -and $min -eq 20 -and $pat -ge 5)          { return 21 }
    if ($maj -eq 1 -and $min -eq 20)                          { return 17 }
    if ($maj -eq 1 -and $min -eq 19)                          { return 17 }
    if ($maj -eq 1 -and $min -eq 18)                          { return 17 }
    if ($maj -eq 1 -and $min -eq 17)                          { return 17 }
    if ($maj -eq 1 -and $min -eq 16 -and $pat -ge 5)          { return 16 }
    if ($maj -eq 1 -and $min -ge 12 -and $min -le 16)         { return 11 }
    return 8
}
#endregion

#region Server detection

function Find-CandidateJars {
    Get-ChildItem -Path $ServerRoot -Filter '*.jar' -File |
        Where-Object { $_.Name -notmatch '(?i)installer' } |
        Sort-Object LastWriteTime -Descending
}

# Read version.json without extracting the whole jar.
function Get-McVersionFromJar {
    param([string]$JarPath)
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [System.IO.Compression.ZipFile]::OpenRead($JarPath)
        try {
            $entry = $zip.Entries | Where-Object { $_.FullName -eq 'version.json' }
            if (-not $entry) { return $null }
            $reader = New-Object System.IO.StreamReader($entry.Open())
            $json = $reader.ReadToEnd() | ConvertFrom-Json
            $reader.Close()
            return $json.id
        } finally { $zip.Dispose() }
    } catch { return $null }
}

function Get-ServerType {
    param([string]$JarPath)
    $name = Split-Path -Leaf $JarPath

    # Forge and NeoForge expose their launch arguments in libraries.
    $argFile = Get-ChildItem -Path (Join-Path $ServerRoot 'libraries') -Filter '*win_args.txt' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($argFile -and (Test-Path (Join-Path $ServerRoot 'user_jvm_args.txt'))) {
        return @{ Type = 'forge'; ArgFile = $argFile.FullName }
    }

    if ($name -match '(?i)fabric-server-launch') {
        return @{ Type = 'fabric'; ArgFile = $null }
    }

    return @{ Type = 'plain'; ArgFile = $null }
}

function Get-DetectedMcVersion {
    param($ServerType, [string]$JarPath)
    switch ($ServerType.Type) {
        'plain' {
            $v = Get-McVersionFromJar -JarPath $JarPath
            if ($v) { return $v }
            # Fall back to the jar filename when version.json is unavailable.
            if ((Split-Path -Leaf $JarPath) -match '(\d+\.\d+(\.\d+)?)') { return $Matches[1] }
            return $null
        }
        'fabric' {
            if ((Split-Path -Leaf $JarPath) -match 'mc\.(\d+\.\d+(\.\d+)?)') { return $Matches[1] }
            return $null
        }
        'forge' {
            if ($ServerType.ArgFile -match '(\d+\.\d+(\.\d+)?)-[\d.]+') { return $Matches[1] }
            if ($ServerType.ArgFile -match '(\d+\.\d+(\.\d+)?)') { return $Matches[1] }
            return $null
        }
    }
    return $null
}
#endregion

#region Java runtime discovery

function Get-JavaMajorVersion {
    param([string]$JavaExe)
    try {
        # Java writes its version to stderr; capture it without PowerShell's
        # native-command error conversion.
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $JavaExe
        $psi.Arguments = '-version'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $process.Dispose()
        $out = "$stdout`n$stderr"
        if ($out -match 'version "(\d+)(\.(\d+))?') {
            $first = [int]$Matches[1]
            if ($first -eq 1 -and $Matches[3]) { return [int]$Matches[3] }  # old "1.8.0_xxx" style
            return $first
        }
    } catch {}
    return $null
}

function Find-InstalledJavaRuntimes {
    $candidates = New-Object System.Collections.Generic.List[string]

    # Check PATH and JAVA_HOME first.
    $onPath = Get-Command java -ErrorAction SilentlyContinue
    if ($onPath) { $candidates.Add($onPath.Source) }

    if ($env:JAVA_HOME) {
        $p = Join-Path $env:JAVA_HOME 'bin\java.exe'
        if (Test-Path $p) { $candidates.Add($p) }
    }

    # Scan common install roots without relying on vendor names.
    $roots = @(
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}",
        "$env:LocalAppData\Programs",
        "$env:LocalAppData\JetBrains"   # IDE-bundled JDKs, sometimes the only JDK on a dev machine
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $roots) {
        Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $vendorDir = $_.FullName
            # Some vendors add a version folder below the vendor directory.
            Get-ChildItem -Path $vendorDir -Filter 'bin' -Directory -Recurse -Depth 2 -ErrorAction SilentlyContinue | ForEach-Object {
                $p = Join-Path $_.FullName 'java.exe'
                if (Test-Path $p) { $candidates.Add($p) }
            }
        }
    }

    # Include runtimes bundled with the official Minecraft Launcher.
    $mcLauncherRoot = Join-Path $env:LocalAppData 'Packages\Microsoft.4297127D64EC9AF_8wekyb3d8bbwe\LocalCache\Local\runtime'
    if (Test-Path $mcLauncherRoot) {
        Get-ChildItem -Path $mcLauncherRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Get-ChildItem -Path $_.FullName -Filter 'java.exe' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                $candidates.Add($_.FullName)
            }
        }
    }

    # Check common machine and user registry locations.
    $regRoots = @(
        'HKLM:\SOFTWARE\JavaSoft\JDK',
        'HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment',
        'HKLM:\SOFTWARE\WOW6432Node\JavaSoft\JDK',
        'HKLM:\SOFTWARE\Eclipse Adoptium\JDK',
        'HKLM:\SOFTWARE\Microsoft\JDK',
        'HKCU:\SOFTWARE\JavaSoft\JDK'
    )
    foreach ($regRoot in $regRoots) {
        if (Test-Path $regRoot) {
            Get-ChildItem $regRoot -ErrorAction SilentlyContinue | ForEach-Object {
                $javaHome = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).JavaHome
                if ($javaHome) {
                    $p = Join-Path $javaHome 'bin\java.exe'
                    if (Test-Path $p) { $candidates.Add($p) }
                }
            }
        }
    }

    $candidates | Select-Object -Unique | ForEach-Object {
        $major = Get-JavaMajorVersion -JavaExe $_
        if ($major) { [PSCustomObject]@{ Path = $_; Major = $major } }
    } | Sort-Object Major -Unique
}

function Select-BestJava {
    param([int]$RequiredMajor, $Installed)
    $ok = $Installed | Where-Object { $_.Major -ge $RequiredMajor } | Sort-Object Major
    if ($ok) { return $ok[0] }   # closest version that still satisfies the minimum
    return $null
}
#endregion

#region Memory

function Get-TotalSystemRamMB {
    try {
        $bytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
        return [Math]::Round($bytes / 1MB)
    } catch { return $null }
}

function Format-RamMB {
    param([int]$MB)
    if ($MB -ge 1024 -and ($MB % 1024) -eq 0) { return "$($MB / 1024)G" }
    return "${MB}M"
}

function Convert-RamToMB {
    param([string]$Text)
    if ($Text -match '^(\d+)\s*([MmGg])$') {
        $n = [int]$Matches[1]
        if ($Matches[2] -match '[Gg]') { return $n * 1024 }
        return $n
    }
    return $null
}
#endregion

#region Setup wizard

function Invoke-SetupWizard {
    Write-Brand -Title 'MINECRAFT SERVER SETUP'
    Write-Host "  Let's get your server ready to launch." -ForegroundColor White

    # Pick the server jar.
    Write-Section '1 / 4  Server file' 'Choose the runnable server jar in this folder.'
    $jars = Find-CandidateJars
    $serverJar = $null
    if ($jars.Count -eq 1) {
        Write-StatusRow 'Detected' $jars[0].Name Cyan
        if (Read-YesNo -Prompt 'Use this file?' -Default $true) { $serverJar = $jars[0].Name }
    } elseif ($jars.Count -gt 1) {
        Write-Host "  Multiple jar files found:" -ForegroundColor White
        for ($i = 0; $i -lt $jars.Count; $i++) { Write-Host ("  [{0}] {1}" -f $i, $jars[$i].Name) -ForegroundColor White }
        $idx = Read-Host "  Select a server jar by number"
        if ($idx -match '^\d+$' -and [int]$idx -ge 0 -and [int]$idx -lt $jars.Count) {
            $serverJar = $jars[[int]$idx].Name
        } else {
            Write-Warn2 "  That selection was not valid."
        }
    } else {
        Write-Warn2 "  No server jars were found in this folder."
    }
    while (-not $serverJar -or -not (Test-Path (Join-Path $ServerRoot $serverJar))) {
        $serverJar = Read-Host "  Enter the filename of your server .jar file"
        if ($serverJar -and ($serverJar -notlike '*.jar')) { $serverJar += '.jar' }
        if (-not (Test-Path (Join-Path $ServerRoot $serverJar))) {
            Write-Bad "  File `"$serverJar`" was not found."
            $serverJar = $null
        }
    }

    # Work out the server type and runtime requirements.
    Write-Section '2 / 4  Runtime check' 'Detecting server type, Minecraft version, and Java.'
    $serverType = Get-ServerType -JarPath (Join-Path $ServerRoot $serverJar)
    $mcVersion  = Get-DetectedMcVersion -ServerType $serverType -JarPath (Join-Path $ServerRoot $serverJar)
    $reqJava    = Get-RequiredJavaMajor -McVersion $mcVersion

    Write-StatusRow 'Server type' $serverType.Type
    if ($mcVersion) { Write-StatusRow 'Minecraft' "$mcVersion  (Java $reqJava+)" }
    else            { Write-Warn2 '  Minecraft version could not be detected from this jar.' }

    $javaPath = $null
    if ($reqJava) {
        $installed = Find-InstalledJavaRuntimes
        $best = Select-BestJava -RequiredMajor $reqJava -Installed $installed
        if ($best) {
            Write-Good "  Java $($best.Major) ready"
            Write-Host "  $($best.Path)" -ForegroundColor DarkGray
            $javaPath = $best.Path
        } else {
            Write-Bad "  No installed Java runtime satisfies Java $reqJava+."
            if ($installed) {
                Write-Host "  Found on this system:" -ForegroundColor White
                $installed | ForEach-Object { Write-Host "    Java $($_.Major)  $($_.Path)" -ForegroundColor DarkGray }
            } else {
                Write-Host "  No Java installation found in the usual locations." -ForegroundColor White
            }
            Write-Host ""
            $manualPath = Read-Host "  Paste a java.exe path if it is installed elsewhere (or leave blank to exit)"
            if ($manualPath -and (Test-Path $manualPath)) {
                $manualMajor = Get-JavaMajorVersion -JavaExe $manualPath
                if ($manualMajor -ge $reqJava) {
                    Write-Good "  Java $manualMajor ready"
                    Write-Host "  $manualPath" -ForegroundColor DarkGray
                    $javaPath = $manualPath
                } else {
                    Write-Bad "  Java $manualMajor does not meet the Java $reqJava+ requirement."
                    Wait-ForEnter -Prompt 'Press Enter to exit'
                    exit 1
                }
            } else {
                Write-Bad "  Install Java $reqJava (for example, https://adoptium.net) and re-run this script."
                Wait-ForEnter -Prompt 'Press Enter to exit'
                exit 1
            }
        }
    } else {
        Write-Warn2 "  Java version check skipped; using the java command on PATH."
        $onPath = Get-Command java -ErrorAction SilentlyContinue
        if ($onPath) { $javaPath = $onPath.Source }
    }

    # Set memory limits.
    Write-Section '3 / 4  Memory' 'Choose how much RAM the server may use.'
    $totalRam = Get-TotalSystemRamMB
    $suggestedMax = $null
    if ($totalRam) {
        $suggestedMax = [Math]::Round(($totalRam * 0.7) / 512) * 512
        Write-StatusRow 'System memory' "$([Math]::Round($totalRam/1024,1))G  |  suggested max $(Format-RamMB $suggestedMax)"
    }
    do {
        $prompt = if ($suggestedMax) { "  Maximum RAM [$(Format-RamMB $suggestedMax)]" } else { "  Maximum RAM (e.g. 4G)" }
        $in = Read-Host $prompt
        if ($in -eq '' -and $suggestedMax) { $maxRamMB = $suggestedMax }
        else { $maxRamMB = Convert-RamToMB $in }
        if (-not $maxRamMB) { Write-Bad "  Enter a value like 4G or 4096M." }
        elseif ($totalRam -and $maxRamMB -gt ($totalRam * 0.8)) {
            Write-Bad "  That exceeds 80% of system RAM. Choose a lower value."
            $maxRamMB = $null
        }
    } while (-not $maxRamMB)

    $in = Read-Host "  Initial RAM [$(Format-RamMB $maxRamMB)]"
    if ($in -eq '') { $iniRamMB = $maxRamMB }
    else {
        $iniRamMB = Convert-RamToMB $in
        if (-not $iniRamMB -or $iniRamMB -gt $maxRamMB) {
            Write-Warn2 "  Initial RAM must be a valid value no larger than the maximum. Using $maxRamMB."
            $iniRamMB = $maxRamMB
        }
    }

    # Set optional behavior.
    Write-Section '4 / 4  Server behavior' 'Set restart, GUI, and notification preferences.'
    $autoRestart = Read-YesNo -Prompt 'Auto-restart after a stop or crash?' -Default $false
    $gui         = Read-YesNo -Prompt 'Enable the server GUI window?' -Default $false

    $webhookUrl = $null
    $webhookStart = $null
    $webhookStop = $null
    if (Read-YesNo -Prompt 'Enable Discord start/stop notifications?' -Default $false) {
        $webhookUrl = Read-Host "  Discord webhook URL"
        Write-Good "  Default formatted start and stop messages enabled."
    }

    $config = [PSCustomObject]@{
        configVersion = $ConfigVersion
        serverJar     = $serverJar
        serverType    = $serverType.Type
        mcVersion     = $mcVersion
        javaPath      = $javaPath
        maxRam        = Format-RamMB $maxRamMB
        iniRam        = Format-RamMB $iniRamMB
        autoRestart   = $autoRestart
        gui           = $gui
        webhookUrl    = $webhookUrl
        webhookStart  = $webhookStart
        webhookStop   = $webhookStop
        jvmFlags      = $null   # null = use built-in modern defaults; set a string here to override
    }
    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigPath -Encoding UTF8
    Write-Section 'Setup complete' 'Your server is ready for launch.'
    Write-Good "  Configuration saved"
    Write-Host "  $ConfigPath" -ForegroundColor DarkGray
    Start-Sleep -Seconds 1
    return $config
}

#endregion

#region EULA

function Confirm-Eula {
    $eulaPath = Join-Path $ServerRoot 'eula.txt'
    if (Test-Path $eulaPath) {
        $content = Get-Content $eulaPath -Raw
        if ($content -match 'eula\s*=\s*true') { return }
    }
    Write-Brand -Title 'MINECRAFT EULA'
    Write-Host "  Running this server requires accepting Mojang's EULA." -ForegroundColor White
    Write-Host "  https://aka.ms/MinecraftEULA" -ForegroundColor Cyan
    if (-not (Read-YesNo -Prompt "`nDo you accept Mojang's EULA?" -Default $false)) {
        Write-Bad "  EULA not accepted. Exiting."
        exit 1
    }
    @(
        "#By changing the setting below to TRUE you are indicating your agreement to the EULA (https://aka.ms/MinecraftEULA)."
        "#Accepted via mc-startup-script setup."
        "eula=true"
    ) | Set-Content -Path $eulaPath -Encoding ASCII
}
#endregion

#region JVM flags

function Get-DefaultJvmFlags {
    '-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=130 -XX:+AlwaysPreTouch'
}
#endregion

#region Launch command

function Get-LaunchArgs {
    param($Config)

    $jvmFlags = if ($Config.jvmFlags) { $Config.jvmFlags } else { Get-DefaultJvmFlags }
    $heap = @("-Xms$($Config.iniRam)", "-Xmx$($Config.maxRam)")
    $guiFlag = if ($Config.gui) { @() } else { @('--nogui') }

    switch ($Config.serverType) {
        'forge' {
            $serverType = Get-ServerType -JarPath (Join-Path $ServerRoot $Config.serverJar)
            if (-not $serverType.ArgFile) { throw "Forge/NeoForge argfile not found - has the install layout changed?" }
            $argFileRel = Resolve-Path $serverType.ArgFile -Relative
            return $heap + ($jvmFlags -split ' ') + @('@user_jvm_args.txt', "@$argFileRel") + $guiFlag
        }
        default {
            # Plain and Fabric servers run as executable jars.
            return $heap + ($jvmFlags -split ' ') + @('-jar', $Config.serverJar) + $guiFlag
        }
    }
}
#endregion

#region Discord webhook

function Send-WebhookMessage {
    param([string]$Url, [string]$Message, [string]$Title, [int]$Color)
    if (-not $Url -or -not $Message) { return }
    try {
        $payload = @{
            username = 'Minecraft Server'
            embeds   = @(@{
                title     = $Title
                description = $Message
                color     = $Color
                footer    = @{ text = "mc-startup-script $CoreVersion" }
                timestamp = (Get-Date).ToUniversalTime().ToString('o')
            })
        } | ConvertTo-Json -Depth 5
        $payloadBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        Invoke-RestMethod -Uri $Url -Method Post -ContentType 'application/json; charset=utf-8' `
            -Body $payloadBytes -TimeoutSec 10 | Out-Null
    } catch {
        Write-Warn2 "Webhook notification failed: $($_.Exception.Message)"
    }
}

function Get-WebhookStartMessage {
    param($Config)
    if ($Config.webhookStart -and $Config.webhookStart -ne 'Server starting...') { return $Config.webhookStart }
    return "The server is coming online.`n`n**Server**  ``$($Config.serverJar)```n**Minecraft**  ``$($Config.mcVersion)```n**Memory**  ``$($Config.maxRam)``"
}

function Get-WebhookStopMessage {
    param($Config, [int]$ExitCode)
    if ($Config.webhookStop -and $Config.webhookStop -ne 'Server has stopped.') {
        return "$($Config.webhookStop)`n`n**Exit code**  ``$ExitCode``"
    }
    $state = if ($ExitCode -eq 0) { 'stopped normally' } else { 'stopped unexpectedly' }
    return "The server has **$state**.`n`n**Server**  ``$($Config.serverJar)```n**Exit code**  ``$ExitCode``"
}
#endregion

#region Self-update

function Invoke-SelfUpdateCheck {
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$RepoSlug/releases/latest" -TimeoutSec 8
    } catch {
        Write-Warn2 "Could not check for updates (offline or rate-limited). Continuing with $CoreVersion."
        return
    }
    if (-not $release.tag_name) { return }
    if ((Compare-ScriptVersion $release.tag_name $CoreVersion) -le 0) {
        Write-Host "  mc-startup-script is up to date ($CoreVersion)." -ForegroundColor DarkGray
        return
    }

    Write-Section 'Update available' "$CoreVersion  ->  $($release.tag_name)"
    if (-not (Read-YesNo -Prompt 'Download and install it now?' -Default $true)) { return }

    $batAsset  = $release.assets | Where-Object { $_.name -eq 'START.bat' }
    $coreAsset = $release.assets | Where-Object { $_.name -eq 'core.ps1' }
    if (-not $batAsset -or -not $coreAsset) {
        Write-Warn2 "  The release is missing START.bat or core.ps1. Update skipped."
        return
    }

    # Swap files from a separate process after this script exits. Updating a
    # running batch file in place can leave cmd.exe reading the wrong offset.
    $updaterPath = Join-Path $ServerRoot 'Updater.bat'
    $batUrl  = $batAsset.browser_download_url
    $coreUrl = $coreAsset.browser_download_url
    @"
@echo off
title Updating mc-startup-script to $($release.tag_name)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -Uri '$batUrl' -OutFile 'START.bat.new' -UseBasicParsing; Invoke-WebRequest -Uri '$coreUrl' -OutFile 'config\core.ps1.new' -UseBasicParsing; Move-Item -Force 'START.bat.new' 'START.bat'; Move-Item -Force 'config\core.ps1.new' 'config\core.ps1' } catch { exit 1 }"
if errorlevel 1 (
    echo Update download failed - keeping the current version.
    pause
    exit /b 1
)
start "" "START.bat"
del "%~f0"
"@ | Set-Content -Path $updaterPath -Encoding ASCII

    Write-Good "  Downloading $($release.tag_name) and restarting..."
    Start-Sleep -Seconds 1
    Start-Process -FilePath $updaterPath -WorkingDirectory $ServerRoot
    exit 0
}
#endregion

#region Main loop

function Get-Config {
    if (-not (Test-Path $ConfigPath)) { return Invoke-SetupWizard }
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if ($cfg.configVersion -ne $ConfigVersion) {
        Write-Warn2 "Config schema is outdated - running setup again."
        Start-Sleep -Seconds 1
        return Invoke-SetupWizard
    }
    if (-not $cfg.javaPath -or -not (Test-Path $cfg.javaPath)) {
        Write-Warn2 "Configured Java path is missing - re-running setup."
        return Invoke-SetupWizard
    }
    return $cfg
}

$Host.UI.RawUI.WindowTitle = 'Checking dependencies...'
Invoke-SelfUpdateCheck
$config = Get-Config
Confirm-Eula

if (-not (Test-Path (Join-Path $ServerRoot $config.serverJar))) {
    Write-Bad "Configured server jar '$($config.serverJar)' no longer exists. Re-running setup."
    $config = Invoke-SetupWizard
}

$restartCount = 0
$restartTimestamps = New-Object System.Collections.Generic.List[datetime]

while ($true) {
    $launchArgs = Get-LaunchArgs -Config $config
    $Host.UI.RawUI.WindowTitle = "$($config.serverJar) | Restarts: $restartCount"

    Show-ServerDashboard -Config $config -RestartCount $restartCount

    Send-WebhookMessage -Url $config.webhookUrl -Message (Get-WebhookStartMessage -Config $config) `
        -Title "$([char]::ConvertFromUtf32(0x1F7E2)) Server starting" -Color 5763719

    $javaExe = if ($config.javaPath) { $config.javaPath } else { 'java' }
    & $javaExe @launchArgs
    $exitCode = $LASTEXITCODE
    $launchArgs = $null
    $javaExe = $null

    Send-WebhookMessage -Url $config.webhookUrl -Message (Get-WebhookStopMessage -Config $config -ExitCode $exitCode) `
        -Title "$([char]::ConvertFromUtf32(0x1F534)) Server stopped" -Color 15548997
    Write-Section 'Server stopped' "Process exited with code $exitCode."

    if (-not $config.autoRestart) {
        Write-Host "  Automatic restart is disabled." -ForegroundColor DarkGray
        if (-not (Read-YesNo -Prompt 'Restart the server?' -Default $false)) {
            Write-Host "  Exiting."
            break
        }
        Invoke-SelfUpdateCheck
        continue
    }

    # Pause after repeated failures so a broken server does not restart forever.
    $restartCount++
    $now = Get-Date
    $restartTimestamps.Add($now)
    while ($restartTimestamps.Count -gt 0 -and $restartTimestamps[0] -le $now.AddMinutes(-5)) {
        $restartTimestamps.RemoveAt(0)
    }
    while ($restartTimestamps.Count -gt 5) {
        $restartTimestamps.RemoveAt(0)
    }
    if ($restartTimestamps.Count -ge 5) {
        Write-Bad "  Server has stopped $($restartTimestamps.Count) times in 5 minutes. Pausing 60s to prevent a crash loop."
        Start-Sleep -Seconds 60
    } else {
        Start-Sleep -Seconds 2
    }
    Write-Host "  Restarting (attempt #$restartCount)..." -ForegroundColor Yellow
    Invoke-SelfUpdateCheck
}
#endregion