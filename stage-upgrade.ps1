<#
stage-upgrade.ps1
Purpose:
  Run under SYSTEM (called by bootstrap).
  Downloads ISO if missing, mounts & extracts it to C:\Win11Upgrade\ISOFiles,
  then directly executes run-upgrade.ps1 (which performs the upgrade).
#>

$ErrorActionPreference = "Stop"

# --- Config ---
$Root       = "C:\Win11Upgrade"
$IsoName    = "Win11_24H2.iso"
$IsoUrl     = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoPath    = Join-Path $Root $IsoName
$ExtractDir = Join-Path $Root "ISOFiles"
$LogFile    = Join-Path $Root "stage-upgrade.log"
$RunScript  = Join-Path $Root "Project811-main\run-upgrade.ps1"

# --- Logging helper ---
function Log($m){$t=(Get-Date).ToString("yyyy-MM-dd HH:mm:ss");Add-Content -Path $LogFile -Value "[$t] $m"}

Log "=== stage-upgrade started under $env:USERNAME ==="

# --- Download ISO if missing ---
if (!(Test-Path $IsoPath)) {
    Log "Downloading ISO from $IsoUrl..."
    Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoPath -UseBasicParsing -TimeoutSec 7200
    Log "Download complete."
} else {
    Log "Found existing ISO at $IsoPath."
}

# --- Mount and Extract ---
try {
    Log "Mounting ISO..."
    $mount = Mount-DiskImage -ImagePath $IsoPath -PassThru
    Start-Sleep -Seconds 3
    $vol = $mount | Get-Volume -ErrorAction SilentlyContinue
    if (-not $vol) { throw "Unable to determine mounted drive letter." }
    $DriveLetter = "$($vol.DriveLetter):"
    Log "Mounted at $DriveLetter."

    if (!(Test-Path $ExtractDir)) { New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null }
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

# --- Call Run-Upgrade ---
if (Test-Path $RunScript) {
    Log "Launching run-upgrade.ps1..."
    powershell -ExecutionPolicy Bypass -NoProfile -File $RunScript
    Log "run-upgrade.ps1 completed."
} else {
    Log "ERROR: run-upgrade.ps1 not found at $RunScript."
}

Log "stage-upgrade complete."
