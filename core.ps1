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
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$CoreVersion = 'v2.3.4'
$ConfigVersion = 3
$RepoSlug = 'GarnServo/mc-startup-script'

$ScriptRoot = Split-Path -Parent $PSCommandPath           # ...\config
$ServerRoot = Split-Path -Parent $ScriptRoot               # server root, one level up
$ConfigPath = Join-Path $ScriptRoot 'StartupScript.json'
$JavaRequirementsCachePath = Join-Path $ScriptRoot 'JavaRequirements.json'
Set-Location $ServerRoot
Remove-Variable ScriptRoot

#region Helpers

function Write-Good { param($Message) Write-Host $Message -ForegroundColor Green }
function Write-Warn2 { param($Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Bad { param($Message) Write-Host $Message -ForegroundColor Red }
function Write-Rule { Write-Host ('-' * 64) -ForegroundColor DarkGray }
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
function Read-Choice {
    param([string]$Prompt, [string[]]$Options, [int]$Default = 0)
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("    [{0}] {1}{2}" -f ($i + 1), $Options[$i], $(if ($i -eq $Default) { '  (default)' } else { '' })) -ForegroundColor White
    }
    $raw = Read-Host ("  {0} [1-{1}]" -f $Prompt, $Options.Count)
    if ($raw -eq '') { return $Default }
    if ($raw -match '^\d+$' -and [int]$raw -ge 1 -and [int]$raw -le $Options.Count) { return [int]$raw - 1 }
    Write-Warn2 "  Invalid selection - using the default."
    return $Default
}
function Wait-ForEnter {
    param([string]$Prompt = 'Press Enter to continue')
    [void](Read-Host ("  {0} [Enter]" -f $Prompt))
}

# Single source of truth for how an exit code is described, so the console
# output and the Discord webhook never disagree with each other.
function Get-ExitState {
    param([int]$ExitCode)
    if ($ExitCode -eq 0) { return [PSCustomObject]@{ Label = 'stopped normally'; Message = 'The server has stopped normally.'; Color = [ConsoleColor]::Green } }
    return [PSCustomObject]@{ Label = 'crashed'; Message = 'The server has crashed.'; Color = [ConsoleColor]::Red }
}

# Visible countdown for pauses long enough that silence would look frozen.
function Start-CountdownPause {
    param([int]$Seconds, [string]$Label = 'Resuming')
    for ($remaining = $Seconds; $remaining -gt 0; $remaining--) {
        Write-Host ("`r  {0} in {1,3}s..." -f $Label, $remaining) -ForegroundColor DarkGray -NoNewline
        Start-Sleep -Seconds 1
    }
    Write-Host ("`r  {0} now.{1}" -f $Label, (' ' * 12))
}
function Get-GcLabel {
    param([string]$JvmFlags)
    if (-not $JvmFlags) { return 'JVM default' }
    if ($JvmFlags -match 'UseZGC') { return 'ZGC' }
    if ($JvmFlags -match 'UseG1GC') { return 'G1GC' }
    if ($JvmFlags -match 'UseShenandoahGC') { return 'Shenandoah' }
    return 'Custom'
}
function Show-ServerDashboard {
    param($Config, [int]$RestartCount, [int]$JavaMajor)
    Write-Brand
    Write-Host "  SERVER STATUS" -ForegroundColor Cyan
    Write-Rule
    Write-StatusRow 'Server' $Config.serverJar
    Write-StatusRow 'Type' ("{0}{1}" -f $Config.serverType, $(if ($Config.mcVersion) { "  |  MC $($Config.mcVersion)" } else { '' }))
    Write-StatusRow 'Memory' "$($Config.iniRam) initial  |  $($Config.maxRam) max"
    Write-StatusRow 'Java' ("Java {0}" -f $JavaMajor)
    Write-StatusRow 'GC' (Get-GcLabel -JvmFlags $Config.jvmFlags)
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
# Used when Mojang metadata is unavailable. Keep this for older installs and
# unusual server versions that are not present in the official manifest.
function Get-FallbackJavaMajor {
    param([string]$McVersion)
    if (-not $McVersion) { return $null }
    $parts = ($McVersion -split '\.') | ForEach-Object { [int]($_ -replace '\D', '0') }
    while ($parts.Count -lt 3) { $parts += 0 }
    $maj, $min, $pat = $parts[0], $parts[1], $parts[2]

    # Year-based releases.
    if ($maj -ge 26) { return 25 }

    # Older 1.x releases.
    if ($maj -eq 1 -and $min -ge 21) { return 21 }
    if ($maj -eq 1 -and $min -eq 20 -and $pat -ge 5) { return 21 }
    if ($maj -eq 1 -and $min -eq 20) { return 17 }
    if ($maj -eq 1 -and $min -eq 19) { return 17 }
    if ($maj -eq 1 -and $min -eq 18) { return 17 }
    if ($maj -eq 1 -and $min -eq 17) { return 17 }
    if ($maj -eq 1 -and $min -eq 16 -and $pat -ge 5) { return 16 }
    if ($maj -eq 1 -and $min -ge 12 -and $min -le 16) { return 11 }
    return 8
}

function Get-RequiredJavaMajor {
    param([string]$McVersion)
    if (-not $McVersion) { return $null }

    try {
        $cache = @()
        if (Test-Path $JavaRequirementsCachePath) {
            $cache = @(Get-Content $JavaRequirementsCachePath -Raw | ConvertFrom-Json)
            $cached = $cache | Where-Object { $_.version -eq $McVersion } | Select-Object -First 1
            if ($cached -and [int]$cached.majorVersion -gt 0) { return [int]$cached.majorVersion }
        }

        $manifest = Invoke-RestMethod -Uri 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json' -TimeoutSec 8
        $entry = $manifest.versions | Where-Object { $_.id -eq $McVersion } | Select-Object -First 1
        if ($entry -and $entry.url) {
            $metadata = Invoke-RestMethod -Uri $entry.url -TimeoutSec 8
            if ($metadata.javaVersion.majorVersion) {
                $cache = @($cache | Where-Object { $_.version -ne $McVersion })
                $cache += [PSCustomObject]@{
                    version      = $McVersion
                    majorVersion = [int]$metadata.javaVersion.majorVersion
                    checkedAt    = (Get-Date).ToUniversalTime().ToString('o')
                }
                $cache | ConvertTo-Json -Depth 4 | Set-Content -Path $JavaRequirementsCachePath -Encoding UTF8
                return [int]$metadata.javaVersion.majorVersion
            }
        }
    }
    catch {
        # A network failure should never prevent a known version from starting.
    }

    return Get-FallbackJavaMajor -McVersion $McVersion
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
        }
        finally { $zip.Dispose() }
    }
    catch { return $null }
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
    return (Get-McVersionDetection -ServerType $ServerType -JarPath $JarPath).Version
}

function Get-McVersionDetection {
    param($ServerType, [string]$JarPath)
    switch ($ServerType.Type) {
        'plain' {
            $v = Get-McVersionFromJar -JarPath $JarPath
            if ($v) { return [PSCustomObject]@{ Version = $v; Source = 'metadata' } }
            # Fall back to the jar filename when version.json is unavailable.
            if ((Split-Path -Leaf $JarPath) -match '(\d+\.\d+(\.\d+)?)') {
                return [PSCustomObject]@{ Version = $Matches[1]; Source = 'filename' }
            }
            return [PSCustomObject]@{ Version = $null; Source = 'unknown' }
        }
        'fabric' {
            if ((Split-Path -Leaf $JarPath) -match 'mc\.(\d+\.\d+(\.\d+)?)') {
                return [PSCustomObject]@{ Version = $Matches[1]; Source = 'filename' }
            }
            return [PSCustomObject]@{ Version = $null; Source = 'unknown' }
        }
        'forge' {
            if ($ServerType.ArgFile -match '(\d+\.\d+(\.\d+)?)-[\d.]+') {
                return [PSCustomObject]@{ Version = $Matches[1]; Source = 'argfile' }
            }
            if ($ServerType.ArgFile -match '(\d+\.\d+(\.\d+)?)') {
                return [PSCustomObject]@{ Version = $Matches[1]; Source = 'argfile' }
            }
            return [PSCustomObject]@{ Version = $null; Source = 'unknown' }
        }
    }
    return [PSCustomObject]@{ Version = $null; Source = 'unknown' }
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
    }
    catch {}
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
    }
    catch { return $null }
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
    Write-Section '1 / 5  Server file' 'Choose the runnable server jar in this folder.'
    $jars = Find-CandidateJars
    $serverJar = $null
    if ($jars.Count -eq 1) {
        Write-StatusRow 'Detected' $jars[0].Name Cyan
        if (Read-YesNo -Prompt 'Use this file?' -Default $true) { $serverJar = $jars[0].Name }
    }
    elseif ($jars.Count -gt 1) {
        Write-Host "  Multiple jar files found:" -ForegroundColor White
        for ($i = 0; $i -lt $jars.Count; $i++) { Write-Host ("  [{0}] {1}" -f $i, $jars[$i].Name) -ForegroundColor White }
        $idx = Read-Host "  Select a server jar by number"
        if ($idx -match '^\d+$' -and [int]$idx -ge 0 -and [int]$idx -lt $jars.Count) {
            $serverJar = $jars[[int]$idx].Name
        }
        else {
            Write-Warn2 "  That selection was not valid."
        }
    }
    else {
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
    Write-Section '2 / 5  Runtime check' 'Detecting server type, Minecraft version, and Java.'
    $serverType = Get-ServerType -JarPath (Join-Path $ServerRoot $serverJar)
    $versionInfo = Get-McVersionDetection -ServerType $serverType -JarPath (Join-Path $ServerRoot $serverJar)
    $mcVersion = $versionInfo.Version
    $reqJava = Get-RequiredJavaMajor -McVersion $mcVersion

    Write-StatusRow 'Server type' $serverType.Type
    if ($mcVersion) {
        Write-StatusRow 'Minecraft' "$mcVersion  (Java $reqJava+)"
        if ($versionInfo.Source -eq 'filename') {
            Write-Warn2 '  Version was inferred from the filename; metadata was not available.'
        }
    }
    else { Write-Warn2 '  Minecraft version could not be detected from this jar.' }

    $javaPath = $null
    $javaMajor = $null
    if ($reqJava) {
        $installed = Find-InstalledJavaRuntimes
        $best = Select-BestJava -RequiredMajor $reqJava -Installed $installed
        if ($best) {
            Write-Good "  Java $($best.Major) ready"
            Write-Host "  $($best.Path)" -ForegroundColor DarkGray
            $javaPath = $best.Path
            $javaMajor = $best.Major
        }
        else {
            Write-Bad "  No installed Java runtime satisfies Java $reqJava+."
            if ($installed) {
                Write-Host "  Found on this system:" -ForegroundColor White
                $installed | ForEach-Object { Write-Host "    Java $($_.Major)  $($_.Path)" -ForegroundColor DarkGray }
            }
            else {
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
                    $javaMajor = $manualMajor
                }
                else {
                    Write-Bad "  Java $manualMajor does not meet the Java $reqJava+ requirement."
                    Wait-ForEnter -Prompt 'Press Enter to exit'
                    exit 1
                }
            }
            else {
                Write-Bad "  Install Java $reqJava (for example, https://adoptium.net) and re-run this script."
                Wait-ForEnter -Prompt 'Press Enter to exit'
                exit 1
            }
        }
    }
    else {
        Write-Warn2 "  Java version check skipped; using the java command on PATH."
        $onPath = Get-Command java -ErrorAction SilentlyContinue
        if ($onPath) {
            $javaPath = $onPath.Source
            $javaMajor = Get-JavaMajorVersion -JavaExe $javaPath
        }
    }

    # Set memory limits.
    Write-Section '3 / 5  Memory' 'Choose how much RAM the server may use.'
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

    # Choose JVM/GC tuning.
    Write-Section '4 / 5  JVM flags' 'Choose how the garbage collector is tuned.'
    Write-Host "  Calculated works out G1GC vs generational ZGC (and tunes it) from your" -ForegroundColor DarkGray
    Write-Host "  Java version, CPU cores, and allocated RAM." -ForegroundColor DarkGray
    $flagChoice = Read-Choice -Prompt 'Choose an option' -Options @(
        'Calculated - work out the optimal flags for this hardware'
        'Custom - paste your own JVM flags'
        'Skip - no extra flags, just the JVM defaults'
    ) -Default 0
    $jvmFlags = $null
    switch ($flagChoice) {
        0 {
            $plan = Get-OptimalJvmPlan -JavaExe $javaPath -JavaMajor $javaMajor -HeapMB $maxRamMB -TotalRamMB $totalRam -ServerType $serverType.Type
            Write-Good "  $($plan.GC)"
            Write-Host "  $($plan.Reason)" -ForegroundColor DarkGray
            if ($plan.Flags) { Write-Host "  $($plan.Flags)" -ForegroundColor DarkGray }
            $jvmFlags = if ($plan.Flags) { $plan.Flags } else { $null }
        }
        1 {
            $jvmFlags = Read-Host "  Paste your JVM flags (heap flags are added automatically - don't include -Xms/-Xmx)"
            if (-not $jvmFlags) { $jvmFlags = $null }
        }
        2 {
            Write-Host "  No extra JVM flags - the JVM will use its own defaults." -ForegroundColor DarkGray
        }
    }

    # Set optional behavior.
    Write-Section '5 / 5  Server behavior' 'Set restart, GUI, and notification preferences.'
    $autoRestart = Read-YesNo -Prompt 'Auto-restart after a stop or crash?' -Default $false
    $gui = Read-YesNo -Prompt 'Enable the server GUI window?' -Default $false

    $webhookUrl = $null
    $webhookStart = $null
    $webhookStop = $null
    if (Read-YesNo -Prompt 'Enable Discord start/stop notifications?' -Default $false) {
        $webhookUrl = Read-Host "  Discord webhook URL"
        Write-Good "  Default formatted start and stop messages enabled."
        Write-Warn2 "  Note: a webhook URL works like a password - anyone who has it can post to"
        Write-Warn2 "  that channel. It's saved in plain text in StartupScript.json; don't share"
        Write-Warn2 "  that file or commit it anywhere public."
    }

    # Review before saving.
    Write-Section 'Review' 'Confirm these settings before saving.'
    Write-StatusRow 'Server' $serverJar
    Write-StatusRow 'Type' $serverType.Type
    if ($mcVersion) { Write-StatusRow 'Minecraft' $mcVersion }
    Write-StatusRow 'Java' $(if ($javaPath) { $javaPath } else { 'java (PATH)' })
    Write-StatusRow 'Memory' "$(Format-RamMB $iniRamMB) initial  |  $(Format-RamMB $maxRamMB) max"
    Write-StatusRow 'JVM flags' $(if ($jvmFlags) { $jvmFlags } else { 'None (JVM defaults)' })
    Write-StatusRow 'Auto-restart' $(if ($autoRestart) { 'Enabled' } else { 'Disabled' })
    Write-StatusRow 'GUI' $(if ($gui) { 'Enabled' } else { 'Disabled' })
    Write-StatusRow 'Webhook' $(if ($webhookUrl) { 'Configured' } else { 'Not configured' })
    Write-Host ""
    if (-not (Read-YesNo -Prompt 'Save this configuration?' -Default $true)) {
        Write-Warn2 "  Starting over..."
        Start-Sleep -Seconds 1
        return Invoke-SetupWizard
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
        jvmFlags      = $jvmFlags   # null/empty = no extra flags; otherwise the chosen calculated or custom flag string
    }
    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigPath -Encoding UTF8
    Write-Section 'Setup complete' 'Your server is ready for launch.'
    Write-Good "  Configuration saved"
    Write-Host "  $ConfigPath" -ForegroundColor DarkGray
    Write-Host "  Tip: edit that file directly to fine-tune JVM flags or custom webhook text." -ForegroundColor DarkGray
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
    Write-Host ""
    if (-not (Read-YesNo -Prompt "Do you accept Mojang's EULA?" -Default $false)) {
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

# Sourced from current (2026) Minecraft-server JVM-tuning consensus across
# multiple independent guides, cross-checked against the relevant JEPs:
#   - G1GC tuned with "Aikar's flags" remains the well-tested default
#     under ~12GB heap, and is the only sane choice below Java 21 (ZGC
#     is non-generational there, which isn't suitable for MC's
#     allocation pattern).
#   - Generational ZGC (JEP 439, default since JEP 474/JDK 23) trades
#     ~15-30% more memory and some throughput for near-zero pause
#     times, and starts paying for that overhead around a 12GB+ heap.
#     It's a concurrent collector, so it also needs CPU headroom - a
#     2 vCPU box starves the main tick thread trying to run it.
#   - JEP 490 (JDK 24) removed non-generational ZGC entirely. The
#     -XX:+ZGenerational opt-in flag is only meaningful on Java 21-23;
#     omit it on 24+ rather than risk passing a possibly-removed flag.
#   - Modded servers (Forge/NeoForge/Fabric) allocate more per tick
#     (custom entities, tile-entity processing) and measure better
#     with a larger young generation / region size than vanilla.

function Get-G1Flags {
    param([string]$ServerType)
    if ($ServerType -in @('forge', 'fabric')) {
        return '-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=40 -XX:G1MaxNewSizePercent=50 -XX:G1HeapRegionSize=16M -XX:G1ReservePercent=15 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=20 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1'
    }
    return '-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1'
}

function Get-ZgcFlags {
    param([int]$JavaMajor)
    $base = '-XX:+UseZGC -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:+UnlockExperimentalVMOptions'
    if ($JavaMajor -ge 21 -and $JavaMajor -le 23) { return "$base -XX:+ZGenerational" }
    return $base   # Java 24+: generational is the only mode - no flag needed, and the flag may not exist
}

# Dry-runs a candidate flag set against the *actual* installed JVM before
# committing to it - catches a build that's missing a GC (some minimal or
# older JREs), or a flag removed in a newer Java release, rather than
# discovering it when the real server jar fails to start.
function Test-JvmFlagsSupported {
    param([string]$JavaExe, [string[]]$Flags)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $JavaExe
        $psi.Arguments = (($Flags + '-version') -join ' ')
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
        $exitCode = $process.ExitCode
        $process.Dispose()
        $combined = ($stdout + $stderr)
        $bad = $combined -match 'Unrecognized VM option|Error occurred during initialization|Could not create the Java Virtual Machine'
        if ($exitCode -ne 0 -or $bad) {
            $oneLine = ($combined.Trim() -replace '\r?\n', ' | ')
            Write-Warn2 "    validation: exit $exitCode - $oneLine"
        }
        return ($exitCode -eq 0) -and (-not $bad)
    }
    catch {
        Write-Warn2 "    validation threw: $($_.Exception.Message)"
        return $false
    }
}

function Get-OptimalJvmPlan {
    param([string]$JavaExe, [int]$JavaMajor, [int]$HeapMB, [int]$TotalRamMB, [string]$ServerType)

    $cores = [Environment]::ProcessorCount
    $heapGB = [Math]::Round($HeapMB / 1024, 1)

    # ZGC needs 15-30% more memory than the heap alone for the same
    # workload - make sure there's realistic headroom above the heap on
    # total system RAM before recommending it, not just enough to launch.
    $zgcMemoryHeadroomOk = (-not $TotalRamMB) -or ($TotalRamMB -ge ($HeapMB * 1.3 + 2048))
    $zgcEligible = ($JavaMajor -ge 21) -and ($heapGB -ge 12) -and ($cores -ge 4) -and $zgcMemoryHeadroomOk

    if ($zgcEligible) {
        $flags = Get-ZgcFlags -JavaMajor $JavaMajor
        $gcName = 'Generational ZGC'
        $reason = "Java $JavaMajor, ${heapGB}G heap, $cores logical cores - enough heap and CPU headroom for ZGC's concurrent collection to be worth its overhead."
    }
    else {
        $flags = Get-G1Flags -ServerType $ServerType
        $gcName = 'G1GC (Aikar-tuned)'
        $reason =
        if ($JavaMajor -lt 21) { "Java $JavaMajor - generational ZGC needs Java 21+, so G1 is the right call here." }
        elseif ($heapGB -lt 12) { "${heapGB}G heap is under the ~12G point where ZGC starts paying for its overhead - G1 wins below that." }
        elseif ($cores -lt 4) { "$cores logical cores isn't enough headroom for a concurrent collector without starving the main tick - G1 is the safer choice." }
        else { "Not enough memory headroom above the ${heapGB}G heap for ZGC's overhead - G1 is the safer choice." }
    }

    if (-not (Test-JvmFlagsSupported -JavaExe $JavaExe -Flags ($flags -split ' '))) {
        Write-Warn2 "  $gcName flags weren't accepted by this Java install - falling back to plain G1GC."
        $flags = '-XX:+UseG1GC'
        $gcName = 'G1GC (JVM default tuning)'
        $reason = "The calculated flags weren't recognized by this specific Java build, so this falls back to plain G1 with no extra tuning."
        if (-not (Test-JvmFlagsSupported -JavaExe $JavaExe -Flags @('-XX:+UseG1GC'))) {
            $flags = ''
            $gcName = 'JVM default'
            $reason = "Couldn't validate any GC flags against this Java install - using the JVM's own defaults."
        }
    }

    return [PSCustomObject]@{ Flags = $flags; GC = $gcName; Reason = $reason }
}
#endregion

#region Launch command

function Get-LaunchArgs {
    param($Config)

    # $null/empty means no extra flags at all (the "skip" wizard choice) -
    # jvmFlags is always an explicit, fully-formed decision made at setup
    # time now, not a silent built-in default.
    $jvmFlags = if ($Config.jvmFlags) { $Config.jvmFlags -split ' ' } else { @() }
    $heap = @("-Xms$($Config.iniRam)", "-Xmx$($Config.maxRam)")
    $guiFlag = if ($Config.gui) { @() } else { @('--nogui') }

    switch ($Config.serverType) {
        'forge' {
            $serverType = Get-ServerType -JarPath (Join-Path $ServerRoot $Config.serverJar)
            if (-not $serverType.ArgFile) { throw "Forge/NeoForge argfile not found - has the install layout changed?" }
            $argFileRel = Resolve-Path $serverType.ArgFile -Relative
            return $heap + $jvmFlags + @('@user_jvm_args.txt', "@$argFileRel") + $guiFlag
        }
        default {
            # Plain and Fabric servers run as executable jars.
            return $heap + $jvmFlags + @('-jar', $Config.serverJar) + $guiFlag
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
                    title       = $Title
                    description = $Message
                    color       = $Color
                    footer      = @{ text = "mc-startup-script $CoreVersion" }
                    timestamp   = (Get-Date).ToUniversalTime().ToString('o')
                })
        } | ConvertTo-Json -Depth 5
        $payloadBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        Invoke-RestMethod -Uri $Url -Method Post -ContentType 'application/json; charset=utf-8' `
            -Body $payloadBytes -TimeoutSec 10 | Out-Null
    }
    catch {
        Write-Warn2 "Webhook notification failed: $($_.Exception.Message)"
    }
}

function Get-WebhookStartMessage {
    param($Config)
    if ($Config.webhookStart -and $Config.webhookStart -notmatch '(?i)server (starting\.\.\.|has started)') {
        return $Config.webhookStart
    }
    return "The server is coming online.`n`n**Server**  ``$($Config.serverJar)```n**Minecraft**  ``$($Config.mcVersion)```n**Memory**  ``$($Config.maxRam)``"
}

function Get-WebhookStopMessage {
    param($Config, [int]$ExitCode)
    $exitState = Get-ExitState -ExitCode $ExitCode
    $state = $exitState.Label
    if ($Config.webhookStop -and $Config.webhookStop -notmatch '(?i)server has stopped\.') {
        return "$($Config.webhookStop)`n`n**Status**  ``$state```n**Exit code**  ``$ExitCode``"
    }
    return "$($exitState.Message)`n`n**Server**  ``$($Config.serverJar)```n**Exit code**  ``$ExitCode``"
}
#endregion

#region Self-update

function Invoke-SelfUpdateCheck {
    param([switch]$Interactive)
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$RepoSlug/releases/latest" -TimeoutSec 8
    }
    catch {
        if ($Interactive) { Write-Warn2 "Could not check for updates (offline or rate-limited). Continuing with $CoreVersion." }
        return
    }
    if (-not $release.tag_name) { return }

    if ($release.tag_name -notmatch '^v\d+\.\d+\.\d+$') {
        if ($Interactive) { Write-Warn2 "  Latest release tag '$($release.tag_name)' has an unexpected format - skipping update check for safety." }
        return
    }

    if ((Compare-ScriptVersion $release.tag_name $CoreVersion) -le 0) {
        if ($Interactive) { Write-Host "  mc-startup-script is up to date ($CoreVersion)." -ForegroundColor DarkGray }
        return
    }

    if (-not $Interactive) {
        # Auto-restart loops run unattended - never block them on a prompt.
        # Just flag it; the next interactive launch will offer to install.
        Write-Warn2 "  Update available ($CoreVersion -> $($release.tag_name)) - will offer to install next time this is run interactively."
        return
    }

    Write-Section 'Update available' "$CoreVersion  ->  $($release.tag_name)"
    if ($release.body) {
        # release.body is also free text - strip control/escape characters
        # before it hits the console, since a crafted release description
        # could otherwise use terminal escape sequences to spoof output.
        $cleanBody = $release.body -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
        ($cleanBody -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 4) | ForEach-Object {
            Write-Host "  $_" -ForegroundColor DarkGray
        }
        Write-Host ""
    }
    if (-not (Read-YesNo -Prompt 'Download and install it now?' -Default $true)) { return }

    $batAsset = $release.assets | Where-Object { $_.name -eq 'START.bat' }
    $coreAsset = $release.assets | Where-Object { $_.name -eq 'core.ps1' }
    if (-not $batAsset -or -not $coreAsset) {
        Write-Warn2 "  The release is missing START.bat or core.ps1. Update skipped."
        return
    }
    # GitHub computes and exposes a SHA256 digest for every release asset automatically (assets[].digest, "sha256:<hex>")
    if (-not $batAsset.digest -or -not $coreAsset.digest) {
        Write-Bad "  GitHub hasn't published a checksum for one of these assets yet - refusing to update without integrity verification."
        return
    }

    # Swap files from a separate process after this script exits. Updating a
    # running batch file in place can leave cmd.exe reading the wrong offset.
    $updaterBatPath = Join-Path $ServerRoot 'Updater.bat'
    $updaterPs1Path = Join-Path $ServerRoot 'Updater.ps1'

    $updaterScript = @'
param($BatUrl, $CoreUrl, $BatDigest, $CoreDigest)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Test-Checksum {
    param($FilePath, $ExpectedDigest)
    if (-not $ExpectedDigest) { return $false }   # strict mode: no digest = fail closed
    $expected = $ExpectedDigest -replace '^sha256:', ''
    $actual = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
    return ($actual -ieq $expected)
}
try {
    Invoke-WebRequest -Uri $BatUrl  -OutFile 'START.bat.new'        -UseBasicParsing
    Invoke-WebRequest -Uri $CoreUrl -OutFile 'config\core.ps1.new'  -UseBasicParsing
    if (-not (Test-Checksum 'START.bat.new' $BatDigest))        { throw 'START.bat checksum mismatch - refusing to install' }
    if (-not (Test-Checksum 'config\core.ps1.new' $CoreDigest)) { throw 'core.ps1 checksum mismatch - refusing to install' }
    Move-Item -Force 'START.bat.new' 'START.bat'
    Move-Item -Force 'config\core.ps1.new' 'config\core.ps1'
} catch {
    Write-Host "Update failed: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item 'START.bat.new','config\core.ps1.new' -Force -ErrorAction SilentlyContinue
    exit 1
}
'@
    $updaterScript | Set-Content -Path $updaterPs1Path -Encoding UTF8

    @"
@echo off
title Updating mc-startup-script to $($release.tag_name)...
powershell -NoProfile -ExecutionPolicy Bypass -File "Updater.ps1" -BatUrl "$($batAsset.browser_download_url)" -CoreUrl "$($coreAsset.browser_download_url)" -BatDigest "$($batAsset.digest)" -CoreDigest "$($coreAsset.digest)"
if errorlevel 1 (
    del "Updater.ps1" >nul 2>&1
    pause
    exit /b 1
)
del "Updater.ps1"
start "" "START.bat"
del "%~f0"
"@ | Set-Content -Path $updaterBatPath -Encoding ASCII

    Write-Good "  Downloading $($release.tag_name) and restarting..."
    Start-Sleep -Seconds 1
    Start-Process -FilePath $updaterBatPath -WorkingDirectory $ServerRoot
    exit 0
}
#endregion

#region Main loop

function Import-LegacyConfig {
    $legacyPath = Join-Path (Split-Path -Parent $ConfigPath) 'StartupScript.conf'
    if ((Test-Path $ConfigPath) -or -not (Test-Path $legacyPath)) { return $null }

    try {
        $values = @{}
        foreach ($line in (Get-Content $legacyPath)) {
            if ($line -match '^\s*([^#][^=]*)=(.*)$') { $values[$Matches[1].Trim()] = $Matches[2].Trim() }
        }
        if (-not $values.serverName -or -not (Test-Path (Join-Path $ServerRoot $values.serverName))) { return $null }

        $serverJar = $values.serverName
        $serverType = Get-ServerType -JarPath (Join-Path $ServerRoot $serverJar)
        $mcVersion = Get-DetectedMcVersion -ServerType $serverType -JarPath (Join-Path $ServerRoot $serverJar)
        $javaPath = $null
        $requiredJava = Get-RequiredJavaMajor -McVersion $mcVersion
        if ($requiredJava) {
            $bestJava = Select-BestJava -RequiredMajor $requiredJava -Installed (Find-InstalledJavaRuntimes)
            if ($bestJava) { $javaPath = $bestJava.Path }
        }
        else {
            $onPath = Get-Command java -ErrorAction SilentlyContinue
            if ($onPath) { $javaPath = $onPath.Source }
        }
        if (-not $javaPath) { return $null }

        $config = [PSCustomObject]@{
            configVersion = $ConfigVersion
            serverJar     = $serverJar
            serverType    = $serverType.Type
            mcVersion     = $mcVersion
            javaPath      = $javaPath
            maxRam        = $values.maxRam
            iniRam        = $values.iniRam
            autoRestart   = ($values.autoRestart -match '^(?i:true|yes|y|1)$')
            gui           = ($values.GUI -match '^(?i:true|yes|y|1)$')
            webhookUrl    = $values.webhookURL
            webhookStart  = $values.webhookMessageStart
            webhookStop   = $values.webhookMessageStop
            jvmFlags      = $null
        }
        $config | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigPath -Encoding UTF8
        Write-Good '  Existing v1 settings imported successfully.'
        return $config
    }
    catch {
        Write-Warn2 '  The old configuration could not be imported. Starting setup instead.'
        return $null
    }
}

function Get-Config {
    if (-not (Test-Path $ConfigPath)) {
        $legacy = Import-LegacyConfig
        if ($legacy) { return $legacy }
        return Invoke-SetupWizard
    }
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
Invoke-SelfUpdateCheck -Interactive
$config = Get-Config
Confirm-Eula

if (-not (Test-Path (Join-Path $ServerRoot $config.serverJar))) {
    Write-Bad "Configured server jar '$($config.serverJar)' no longer exists. Re-running setup."
    $config = Invoke-SetupWizard
}

$restartCount = 0
$restartTimestamps = New-Object System.Collections.Generic.List[datetime]
$javaMajor = Get-JavaMajorVersion -JavaExe $config.javaPath

while ($true) {
    $launchArgs = Get-LaunchArgs -Config $config
    $Host.UI.RawUI.WindowTitle = "$($config.serverJar) | Restarts: $restartCount"

    Show-ServerDashboard -Config $config -RestartCount $restartCount -JavaMajor $javaMajor

    Send-WebhookMessage -Url $config.webhookUrl -Message (Get-WebhookStartMessage -Config $config) `
        -Title "$([char]::ConvertFromUtf32(0x1F7E2)) Server starting" -Color 5763719

    $javaExe = if ($config.javaPath) { $config.javaPath } else { 'java' }
    & $javaExe @launchArgs
    $exitCode = $LASTEXITCODE
    $launchArgs = $null
    $javaExe = $null

    Send-WebhookMessage -Url $config.webhookUrl -Message (Get-WebhookStopMessage -Config $config -ExitCode $exitCode) `
        -Title "$([char]::ConvertFromUtf32(0x1F534)) Server stopped" -Color 15548997
    $exitState = Get-ExitState -ExitCode $exitCode
    Write-Section 'Server stopped' "Process exited with code $exitCode."
    Write-Host ("  {0}" -f $exitState.Message) -ForegroundColor $exitState.Color

    if (-not $config.autoRestart) {
        Write-Host "  Automatic restart is disabled." -ForegroundColor DarkGray
        if (-not (Read-YesNo -Prompt 'Restart the server?' -Default $false)) {
            Write-Host "  Exiting."
            break
        }
        Invoke-SelfUpdateCheck -Interactive
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
        Write-Bad "  Server has stopped $($restartTimestamps.Count) times in 5 minutes. Pausing to prevent a crash loop."
        Start-CountdownPause -Seconds 60 -Label 'Resuming'
    }
    else {
        Start-Sleep -Seconds 2
    }
    Write-Host "  Restarting (attempt #$restartCount)..." -ForegroundColor Yellow
    Invoke-SelfUpdateCheck
}
#endregion