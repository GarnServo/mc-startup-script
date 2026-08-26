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

# ============================================================
#  Small helpers
# ============================================================

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

# Proper semantic-ish version compare so "v1.10.0" > "v1.9.0" (string
# comparison in the old batch script got this wrong). Returns -1/0/1.
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

# ============================================================
#  Minecraft version -> minimum Java major version
#  (Vanilla / Paper / Purpur / Pufferfish / Spigot all follow the
#  same Mojang-set requirement since they all bundle vanilla code.)
#
#  Mojang moved off the old "1.x.y" scheme in early 2026, starting
#  with version 26.1 - the last old-scheme release was 1.21.11.
#  Source-checked Aug 2026; revisit this table when new majors ship,
#  especially if a future year-scheme release bumps Java again.
# ============================================================
function Get-RequiredJavaMajor {
    param([string]$McVersion)
    if (-not $McVersion) { return $null }
    $parts = ($McVersion -split '\.') | ForEach-Object { [int]($_ -replace '\D', '0') }
    while ($parts.Count -lt 3) { $parts += 0 }
    $maj, $min, $pat = $parts[0], $parts[1], $parts[2]

    # New year-based scheme (26.1, 26.2, 27.x, ...)
    if ($maj -ge 26) { return 25 }

    # Old 1.x.y scheme
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

# ============================================================
#  Server jar / server-type autodetection
# ============================================================

function Find-CandidateJars {
    Get-ChildItem -Path $ServerRoot -Filter '*.jar' -File |
        Where-Object { $_.Name -notmatch '(?i)installer' } |
        Sort-Object LastWriteTime -Descending
}

# Reads version.json out of a runnable server jar (present in vanilla
# and every Paper-family jar) without extracting the whole archive.
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

    # Forge / NeoForge installer output: run.bat + user_jvm_args.txt + libraries\
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
            # Fallback: pull a version-looking token out of the filename
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

# ============================================================
#  Java runtime discovery
# ============================================================

function Get-JavaMajorVersion {
    param([string]$JavaExe)
    try {
        # Capture Java's version output directly; Java writes it to stderr,
        # which Windows PowerShell represents as ErrorRecord objects.
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

    # java on PATH
    $onPath = Get-Command java -ErrorAction SilentlyContinue
    if ($onPath) { $candidates.Add($onPath.Source) }

    # JAVA_HOME
    if ($env:JAVA_HOME) {
        $p = Join-Path $env:JAVA_HOME 'bin\java.exe'
        if (Test-Path $p) { $candidates.Add($p) }
    }

    # Generic scan of common install roots - one level deep is enough for
    # every vendor layout seen in practice (Adoptium/Temurin, Oracle,
    # Microsoft Build of OpenJDK, Zulu, Corretto, BellSoft, Semeru,
    # Liberica, GraalVM, SapMachine, ...). Scanning generically instead of
    # a fixed vendor allowlist means a vendor I didn't think of still gets
    # picked up.
    $roots = @(
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}",
        "$env:LocalAppData\Programs",
        "$env:LocalAppData\JetBrains"   # IDE-bundled JDKs, sometimes the only JDK on a dev machine
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $roots) {
        Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $vendorDir = $_.FullName
            # Some vendors (Adoptium, Zulu) nest an extra version folder: Vendor\jdk-25.x\bin\java.exe
            Get-ChildItem -Path $vendorDir -Filter 'bin' -Directory -Recurse -Depth 2 -ErrorAction SilentlyContinue | ForEach-Object {
                $p = Join-Path $_.FullName 'java.exe'
                if (Test-Path $p) { $candidates.Add($p) }
            }
        }
    }

    # The official Minecraft Launcher ships its own bundled Java runtimes,
    # and for a lot of end users that's the *only* Java on the machine.
    $mcLauncherRoot = Join-Path $env:LocalAppData 'Packages\Microsoft.4297127D64EC9AF_8wekyb3d8bbwe\LocalCache\Local\runtime'
    if (Test-Path $mcLauncherRoot) {
        Get-ChildItem -Path $mcLauncherRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Get-ChildItem -Path $_.FullName -Filter 'java.exe' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                $candidates.Add($_.FullName)
            }
        }
    }

    # Registry-registered JDKs - both 64-bit and 32-bit (WOW6432Node)
    # views, and both machine- and user-scoped installs.
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

# ============================================================
#  System RAM
# ============================================================

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

# ============================================================
#  Setup wizard
# ============================================================

function Invoke-SetupWizard {
    Write-Brand -Title 'MINECRAFT SERVER SETUP'
    Write-Host "  Let's get your server ready to launch." -ForegroundColor White

    # --- Server jar ---
    Write-Section '1 / 4  Server file' 'Choose the runnable server jar in this folder.'
    $jars = Find-CandidateJars
    $serverJar = $null
    if ($jars.Count -eq 1) {
        Write-StatusRow 'Detected' $jars[0].Name Cyan
        $confirm = Read-Host "  Use this file? (Y/n)"
        if ($confirm -eq '' -or $confirm -match '^[Yy]') { $serverJar = $jars[0].Name }
    } elseif ($jars.Count -gt 1) {
        Write-Host "  Multiple jar files found:" -ForegroundColor White
        for ($i = 0; $i -lt $jars.Count; $i++) { Write-Host ("  [{0}] {1}" -f $i, $jars[$i].Name) -ForegroundColor White }
        $idx = Read-Host "  Select a server jar by number"
        if ($idx -match '^\d+$' -and [int]$idx -lt $jars.Count) { $serverJar = $jars[[int]$idx].Name }
    }
    while (-not $serverJar -or -not (Test-Path (Join-Path $ServerRoot $serverJar))) {
        $serverJar = Read-Host "  Enter the filename of your server .jar file"
        if ($serverJar -and ($serverJar -notlike '*.jar')) { $serverJar += '.jar' }
        if (-not (Test-Path (Join-Path $ServerRoot $serverJar))) {
            Write-Bad "  File `"$serverJar`" was not found."
            $serverJar = $null
        }
    }

    # --- Server type + MC version + Java requirement ---
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
                    Read-Host "  Press Enter to exit"
                    exit 1
                }
            } else {
                Write-Bad "  Install Java $reqJava (for example, https://adoptium.net) and re-run this script."
                Read-Host "  Press Enter to exit"
                exit 1
            }
        }
    } else {
        Write-Warn2 "  Java version check skipped; using the java command on PATH."
        $onPath = Get-Command java -ErrorAction SilentlyContinue
        if ($onPath) { $javaPath = $onPath.Source }
    }

    # --- RAM ---
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
        if (-not $iniRamMB -or $iniRamMB -gt $maxRamMB) { $iniRamMB = $maxRamMB }
    }

    # --- Behaviour toggles ---
    Write-Section '4 / 4  Server behavior' 'Set restart, GUI, and notification preferences.'
    $autoRestart = (Read-Host "  Auto-restart after a stop or crash? (y/N)") -match '^[Yy]'
    $gui         = (Read-Host "  Enable the server GUI window? (y/N)") -match '^[Yy]'

    $webhookUrl = $null
    $webhookStart = $null
    $webhookStop = $null
    if ((Read-Host "  Enable Discord start/stop notifications? (y/N)") -match '^[Yy]') {
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

# ============================================================
#  EULA
# ============================================================

function Confirm-Eula {
    $eulaPath = Join-Path $ServerRoot 'eula.txt'
    if (Test-Path $eulaPath) {
        $content = Get-Content $eulaPath -Raw
        if ($content -match 'eula\s*=\s*true') { return }
    }
    Write-Brand -Title 'MINECRAFT EULA'
    Write-Host "  Running this server requires accepting Mojang's EULA." -ForegroundColor White
    Write-Host "  https://aka.ms/MinecraftEULA" -ForegroundColor Cyan
    $agree = Read-Host "`n  Do you accept? (yes/no)"
    if ($agree -notmatch '^(y|yes)$') {
        Write-Bad "  EULA not accepted. Exiting."
        exit 1
    }
    @(
        "#By changing the setting below to TRUE you are indicating your agreement to the EULA (https://aka.ms/MinecraftEULA)."
        "#Accepted via mc-startup-script setup."
        "eula=true"
    ) | Set-Content -Path $eulaPath -Encoding ASCII
}

# ============================================================
#  JVM flags (modern, minimal - see chat writeup for rationale)
# ============================================================

function Get-DefaultJvmFlags {
    '-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=130 -XX:+AlwaysPreTouch'
}

# ============================================================
#  Launch command construction
# ============================================================

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
            # 'plain' and 'fabric' both run as a normal executable jar
            return $heap + ($jvmFlags -split ' ') + @('-jar', $Config.serverJar) + $guiFlag
        }
    }
}

# ============================================================
#  Webhook
# ============================================================

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

# ============================================================
#  Self-update (updates START.bat + this core.ps1 in place)
# ============================================================

function Invoke-SelfUpdateCheck {
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$RepoSlug/releases/latest" -TimeoutSec 8
    } catch {
        Write-Warn2 "Could not check for updates (offline or rate-limited). Continuing with $CoreVersion."
        return
    }
    if (-not $release.tag_name) { return }
    if ((Compare-ScriptVersion $release.tag_name $CoreVersion) -le 0) {
        Write-Host "mc-startup-script is up to date ($CoreVersion)."
        return
    }

    Write-Info "Update available: $CoreVersion -> $($release.tag_name)"
    $doUpdate = Read-Host "Update now? (Y/n)"
    if ($doUpdate -ne '' -and $doUpdate -notmatch '^[Yy]') { return }

    $batAsset  = $release.assets | Where-Object { $_.name -eq 'START.bat' }
    $coreAsset = $release.assets | Where-Object { $_.name -eq 'core.ps1' }
    if (-not $batAsset -or -not $coreAsset) {
        Write-Warn2 "Release $($release.tag_name) is missing expected assets (START.bat / core.ps1) - skipping update."
        return
    }

    # IMPORTANT: we never overwrite START.bat/core.ps1 while they're the
    # files actively being executed - cmd.exe tracks a byte offset into a
    # running .bat, so modifying it mid-run can corrupt execution. Instead
    # we write a small, disposable "Updater.bat" that does the download +
    # swap in a *fresh* process after this one has exited, then relaunches
    # START.bat and deletes itself. This mirrors the original script's
    # daughter-script trick, just applied to two files instead of one.
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

    Write-Good "Downloading update to $($release.tag_name) and restarting..."
    Start-Sleep -Seconds 1
    Start-Process -FilePath $updaterPath -WorkingDirectory $ServerRoot
    exit 0
}

# ============================================================
#  Main
# ============================================================

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

    Send-WebhookMessage -Url $config.webhookUrl -Message (Get-WebhookStopMessage -Config $config -ExitCode $exitCode) `
        -Title "$([char]::ConvertFromUtf32(0x1F534)) Server stopped" -Color 15548997
    Write-Host ""
    Write-Warn2 "  Server process exited with code $exitCode."

    if (-not $config.autoRestart) {
        $again = Read-Host "  Restart the server? (y/N)"
        if ($again -notmatch '^[Yy]') {
            Write-Host "  Exiting."
            break
        }
        Invoke-SelfUpdateCheck
        continue
    }

    # Crash-loop protection: if we've restarted 5+ times inside 5 minutes, pause.
    $restartCount++
    $now = Get-Date
    $restartTimestamps.Add($now)
    $recent = $restartTimestamps | Where-Object { $_ -gt $now.AddMinutes(-5) }
    if ($recent.Count -ge 5) {
        Write-Bad "  Server has stopped $($recent.Count) times in 5 minutes. Pausing 60s to prevent a crash loop."
        Start-Sleep -Seconds 60
    } else {
        Start-Sleep -Seconds 2
    }
    Write-Host "  Restarting (attempt #$restartCount)..." -ForegroundColor Yellow
    Invoke-SelfUpdateCheck
}