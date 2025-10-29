<#
stage-upgrade.ps1
Purpose: Run under SYSTEM as part of staged upgrade chain.
Checks for ISO, mounts if needed, and runs run-upgrade.ps1 from repo.
#>

# --- Config ---
$Root       = "C:\Win11Upgrade"
$IsoName    = "Win11_24H2.iso"
$IsoUrl     = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoPath    = Join-Path $Root $IsoName
$LogFile    = Join-Path $Root "stage-upgrade.log"
$RunScript  = Join-Path $Root "Project811-main\run-upgrade.ps1"
$TaskName   = "Win11_RunUpgrade"

# --- Helpers ---
function Log {
    param([string]$Message)
    $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "[$t] $Message"
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
            Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoPath -UseBasicParsing
            if (!(Test-Path $IsoPath)) { Abort "ISO download failed." }
            Log "ISO downloaded successfully."
        }
    }
}
catch { Abort "Error locating or downloading ISO: $_" }

# --- Mount ISO (if not already) ---
try {
    $disk = Get-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
    if ($disk -and $disk.Attached) {
        Log "ISO already mounted."
    } else {
        Log "Mounting ISO..."
        Mount-DiskImage -ImagePath $IsoPath -ErrorAction Stop | Out-Null
        Start-Sleep -Seconds 3
    }

    $vol = Get-DiskImage -ImagePath $IsoPath | Get-Volume -ErrorAction SilentlyContinue
    if ($vol) {
        $DriveLetter = "$($vol.DriveLetter):"
        Log "Mounted ISO at drive $DriveLetter"
    } else {
        # fallback search
        $DriveLetter = (Get-Volume | Where-Object { Test-Path "$($_.DriveLetter):\setup.exe" } | Select-Object -First 1).DriveLetter + ":"
        if (-not $DriveLetter) { Abort "Unable to determine mounted drive letter." }
        Log "Detected ISO drive letter by fallback: $DriveLetter"
    }
}
catch { Abort "Error mounting ISO: $_" }

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
