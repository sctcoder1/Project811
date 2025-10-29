<#
stage-upgrade.ps1
Purpose: Run under SYSTEM as part of the Windows 11 staged upgrade chain.
Checks for ISO, mounts/extracts contents to C:\Win11Upgrade\ISOFiles,
then schedules run-upgrade.ps1 (not itself) using the prebuilt XML.
#>

$ErrorActionPreference = "Stop"

# --- Config ---
$Root        = "C:\Win11Upgrade"
$IsoName     = "Win11_24H2.iso"
$IsoUrl      = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoPath     = Join-Path $Root $IsoName
$ExtractDir  = Join-Path $Root "ISOFiles"
$LogFile     = Join-Path $Root "stage-upgrade.log"
$XmlTemplate = "C:\Win11Upgrade\Project811-main\Task_RunUpgrade.xml"
$TaskName    = "Win11_RunUpgrade"

# --- Logging helpers ---
function Log {
    param([string]$Message)
    try {
        if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Force -Path $Root | Out-Null }
        $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Add-Content -Path $LogFile -Value "[$t] $Message"
    } catch { Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $Message" }
}

function Abort {
    param([string]$msg)
    Log "FATAL: $msg"
    throw $msg
}

# --- Start ---
New-Item -ItemType Directory -Force -Path $Root | Out-Null
Log "=== stage-upgrade started under $env:USERNAME ==="

# --- Locate or download ISO ---
try {
    if (Test-Path $IsoPath) {
        Log "ISO already present at $IsoPath"
    } else {
        $existing = Get-ChildItem -Path $Root -Filter *.iso -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($existing) {
            $IsoPath = $existing.FullName
            Log "Found alternate ISO: $IsoPath"
        } else {
            Log "Downloading ISO from $IsoUrl ..."
            Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoPath -UseBasicParsing -TimeoutSec 7200
            if (!(Test-Path $IsoPath)) { Abort "ISO download failed." }
            Log "ISO downloaded successfully."
        }
    }
}
catch { Abort "Error locating or downloading ISO: $_" }

# --- Extract ISO contents if not already extracted ---
try {
    $SetupFile = Join-Path $ExtractDir "setup.exe"
    if (Test-Path $SetupFile) {
        Log "Setup files already extracted to $ExtractDir — skipping extraction."
    } else {
        Log "Mounting ISO for extraction..."
        $mount = Mount-DiskImage -ImagePath $IsoPath -PassThru
        Start-Sleep -Seconds 3
        $vol = $mount | Get-Volume -ErrorAction SilentlyContinue
        if (-not $vol) { Abort "Unable to determine mounted drive letter." }
        $DriveLetter = "$($vol.DriveLetter):"
        Log "Mounted ISO at drive $DriveLetter"

        Log "Extracting files to $ExtractDir ..."
        New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
        robocopy "$DriveLetter\" $ExtractDir /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
        Log "Extraction complete."

        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
        Log "ISO dismounted successfully."
    }
}
catch { Abort "Error mounting or extracting ISO: $_" }

# --- Start pre-created RunUpgrade task ---
try {
    if (Get-ScheduledTask -TaskName "Win11_RunUpgrade" -ErrorAction SilentlyContinue) {
        schtasks /run /tn "Win11_RunUpgrade" | Out-Null
        Log "Started existing RunUpgrade task."
    } else {
        Log "ERROR: RunUpgrade task not found."
    }
}
catch {
    Log "FATAL: could not start RunUpgrade task. $_"
}
