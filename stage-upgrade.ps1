<#
stage-upgrade.ps1
Purpose: Run under SYSTEM as part of the Windows 11 staged upgrade chain.
Checks for ISO, mounts/extracts contents to C:\Win11Upgrade\ISOFiles,
then schedules run-upgrade.ps1 (not itself).
#>

$ErrorActionPreference = "Stop"

# --- Config ---
$Root        = "C:\Win11Upgrade"
$IsoName     = "Win11_24H2.iso"
$IsoUrl      = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoPath     = Join-Path $Root $IsoName
$ExtractDir  = Join-Path $Root "ISOFiles"
$LogFile     = Join-Path $Root "stage-upgrade.log"
$RunScript   = "C:\Win11Upgrade\Project811-main\run-upgrade.ps1"   # ✅ Adjusted for correct file
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

# --- Ensure the Win11_RunUpgrade task isn't pointing to this same script ---
try {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        $args = ($existing.Actions | Select-Object -First 1).Arguments
        if ($args -match "stage-upgrade\.ps1") {
            Log "Detected self-reference in $TaskName. Removing old task..."
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
} catch { Log "Warning checking scheduled task: $($_.Exception.Message)" }

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

# --- Schedule run-upgrade.ps1 ---
try {
    if (!(Test-Path $RunScript)) { Abort "Missing run-upgrade.ps1 at $RunScript" }

    Log "Registering scheduled task for run-upgrade.ps1..."
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Log "Removed previous scheduled task $TaskName"
    }

    $args = "-ExecutionPolicy Bypass -File `"$RunScript`""
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $action  = New-ScheduledTaskAction -Execute $ps -Argument $args
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds(30))
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -RunLevel Highest -User "SYSTEM" -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    Log "Scheduled and started task '$TaskName' successfully (file: $RunScript)."
}
catch { Abort "Failed to register or start run-upgrade.ps1: $_" }

Log "stage-upgrade complete."
