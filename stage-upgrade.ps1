# stage-upgrade.ps1
$ErrorActionPreference = "Stop"
$Root = "C:\Win11Upgrade"
$IsoName = "Win11_24H2.iso"
$IsoUrl  = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoPath = Join-Path $Root $IsoName
$ExtractDir = Join-Path $Root "ISOFiles"
$RunScript = "C:\Win11Upgrade\Project811-main\run-upgrade.ps1"
$LogFile = Join-Path $Root "stage-upgrade.log"

function Log($m){$t=(Get-Date).ToString("yyyy-MM-dd HH:mm:ss");Add-Content -Path $LogFile -Value "[$t] $m"}

Log "=== stage-upgrade started under $env:USERNAME ==="

# --- Download or verify ISO ---
if (!(Test-Path $IsoPath)) {
    Log "Downloading ISO..."
    Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoPath -UseBasicParsing
} else { Log "ISO already present." }

# --- Mount + extract ---
try {
    Log "Mounting ISO..."
    $mount = Mount-DiskImage -ImagePath $IsoPath -PassThru
    Start-Sleep -Seconds 3
    $drive = ($mount | Get-Volume).DriveLetter + ":"
    Log "Mounted at $drive"
    if (!(Test-Path $ExtractDir)) { New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null }
    Log "Extracting to $ExtractDir..."
    robocopy "$drive\" $ExtractDir /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    Dismount-DiskImage -ImagePath $IsoPath
    Log "Extraction complete."
}
catch { Log "Extraction failed: $_"; exit 1 }

# --- Run next stage ---
if (Test-Path $RunScript) {
    Log "Starting run-upgrade.ps1..."
    powershell -ExecutionPolicy Bypass -NoProfile -File $RunScript
} else {
    Log "ERROR: run-upgrade.ps1 not found."
}

Log "stage-upgrade complete."
