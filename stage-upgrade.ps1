<#
stage-upgrade.ps1
Purpose:
  Run under SYSTEM as part of the Windows 11 staged upgrade chain.
  Checks for ISO, mounts it if needed, extracts files to C:\Win11Upgrade\ISOFiles,
  and then schedules run-upgrade.ps1. Prevents recursion loops.
#>

# --- Configuration ---
$Root        = "C:\Win11Upgrade"
$IsoName     = "Win11_24H2.iso"
$IsoUrl      = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoPath     = Join-Path $Root $IsoName
$ExtractDir  = Join-Path $Root "ISOFiles"
$LogFile     = Join-Path $Root "stage-upgrade.log"
$RunScript   = Join-Path $Root "Project811-main\run-upgrade.ps1"   # Adjust if you move the file
$TaskName    = "Win11_RunUpgrade"

# --- Logging Helpers ---
function Log {
    param([string]$Message)
    $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "[$t] $Message"
}

function Abort {
    param([string]$Message)
    Log "FATAL: $Message"
    throw $Message
}

# --- Safety Guard ---
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    $TaskAction = (Get-ScheduledTask -TaskName $TaskName).Actions.Execute
    $TaskArgs   = (Get-ScheduledTask -TaskName $TaskName).Actions.Arguments
    if ($TaskArgs -match "stage-upgrade.ps1") {
        Log "Detected recursive self-launch via $TaskName — exiting to prevent loop."
        exit
    }
}

# --- Start ---
New-Item -ItemType Directory -Force -Path $Root | Out-Null
Log "=== stage-upgrade started under $env:USERNAME ==="

# --- Locate or Download ISO ---
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

# --- Mount and Extract ISO ---
try {
    Log "Mounting ISO for extraction..."
    $mount = Mount-DiskImage -ImagePath $IsoPath -PassThru
    Start-Sleep -Seconds 3

    $vol = $mount | Get-Volume -ErrorAction SilentlyContinue
    if (-not $vol) { Abort "Unable to determine mounted drive letter." }
    $DriveLetter = "$($vol.DriveLetter):"
    Log "Mounted ISO at drive $DriveLetter"

    Log "Extracting setup files from $DriveLetter to $ExtractDir ..."
    New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
    robocopy "$DriveLetter\" $ExtractDir /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    Log "Extraction complete."

    Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
    Log "ISO dismounted successfully."
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

    $action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$RunScript`""
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -RunLevel Highest -User "SYSTEM" -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    Log "Scheduled and started task '$TaskName' successfully."
}
catch { Abort "Failed to register or start run-upgrade.ps1: $_" }

Log "stage-upgrade complete."
