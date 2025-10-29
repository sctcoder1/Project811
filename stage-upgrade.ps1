<#
stage-upgrade.ps1
Purpose:
  Run under SYSTEM (called by bootstrap).
  Downloads ISO if missing, mounts & extracts it to C:\Win11Upgrade\ISOFiles,
  injects SetupConfig.ini from repo, then directly executes run-upgrade.ps1.
#>

$ErrorActionPreference = "Stop"

# --- Config ---
$Root         = "C:\Win11Upgrade"
$IsoName      = "Win11_24H2.iso"
$IsoUrl       = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoPath      = Join-Path $Root $IsoName
$ExtractDir   = Join-Path $Root "ISOFiles"
$RepoConfig   = Join-Path $Root "Project811-main\SetupConfig.ini"
$TargetConfig = Join-Path $ExtractDir "sources\SetupConfig.ini"
$RunScript    = Join-Path $Root "Project811-main\run-upgrade.ps1"
$LogFile      = Join-Path $Root "stage-upgrade.log"

# --- Logging helper ---
function Log {
    param([string]$m)
    $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "[$t] $m"
}

Log "=== stage-upgrade started under $env:USERNAME ==="

# --- Ensure folder exists ---
if (!(Test-Path $Root)) {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
}

# --- Verify or download ISO ---
try {
    if (Test-Path $IsoPath) {
        Log "Found existing ISO at $IsoPath"
    }
    else {
        Log "Downloading ISO from $IsoUrl ..."
        Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoPath -UseBasicParsing -TimeoutSec 7200
        if (!(Test-Path $IsoPath)) {
            throw "ISO download failed."
        }
        Log "ISO downloaded successfully."
    }
}
catch {
    Log "ERROR: Failed to locate or download ISO - $_"
    exit 1
}

# --- Mount & Extract ---
try {
    Log "Mounting ISO..."
    $mount = Mount-DiskImage -ImagePath $IsoPath -PassThru
    Start-Sleep -Seconds 3
    $vol = $mount | Get-Volume -ErrorAction SilentlyContinue
    if (-not $vol) {
        throw "Unable to determine mounted drive letter."
    }
    $DriveLetter = "$($vol.DriveLetter):"
    Log "Mounted at $DriveLetter"

    if (!(Test-Path $ExtractDir)) {
        New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
    }

    Log "Extracting contents to $ExtractDir..."
    robocopy "$DriveLetter\" $ExtractDir /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    Log "Extraction complete."

    Dismount-DiskImage -ImagePath $IsoPath
    Log "ISO dismounted successfully."
}
catch {
    Log "ERROR: Mount or extraction failed - $_"
    exit 1
}

# --- Inject SetupConfig.ini ---
try {
    if (Test-Path $RepoConfig) {
        $destDir = Split-Path $TargetConfig -Parent
        if (!(Test-Path $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }
        Copy-Item -Path $RepoConfig -Destination $TargetConfig -Force
        Log "Copied SetupConfig.ini into extracted ISO sources folder."
    }
    else {
        Log "WARNING: SetupConfig.ini not found in repo ? skipping copy."
    }
}
catch {
    Log "ERROR copying SetupConfig.ini: $_"
}

# --- Run next stage ---
if (Test-Path $RunScript) {
    Log "Launching run-upgrade.ps1..."
    powershell -ExecutionPolicy Bypass -NoProfile -File $RunScript
    Log "run-upgrade.ps1 completed."
}
else {
    Log "ERROR: run-upgrade.ps1 not found at $RunScript."
}

Log "stage-upgrade complete."
