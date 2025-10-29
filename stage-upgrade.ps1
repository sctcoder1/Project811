<#
stage-upgrade.ps1
Run under SYSTEM. Ensures ISO present, extracts to C:\Win11Upgrade\ISOFiles (idempotent),
then registers + starts the Win11_RunUpgrade task to run run-upgrade.ps1.
#>

$ErrorActionPreference = 'Stop'

# --- Config ---
$Root        = "C:\Win11Upgrade"
$IsoName     = "Win11_24H2.iso"
$IsoUrl      = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoPath     = Join-Path $Root $IsoName
$ExtractDir  = Join-Path $Root "ISOFiles"
$LogFile     = Join-Path $Root "stage-upgrade.log"
# adjust if you relocated run-upgrade.ps1:
$RunScript   = Join-Path $Root "Project811-main\run-upgrade.ps1"
$TaskName    = "Win11_RunUpgrade"

# --- Ensure workspace exists BEFORE any logging ---
if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Force -Path $Root | Out-Null }

# --- Safe logger (never throws) ---
function Log {
  param([string]$Message)
  try {
    if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Force -Path $Root | Out-Null }
    $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "[$t] $Message"
  } catch {
    # fallback to console (Task Scheduler captures some stdout)
    Write-Host $Message
  }
}

function Abort {
  param([string]$msg)
  Log "FATAL: $msg"
  throw $msg
}

Log "=== stage-upgrade started under $env:USERNAME ==="

# --- Fix any accidental self-loop task BEFORE continuing ---
try {
  $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($existing) {
    $args = ($existing.Actions | Select-Object -First 1).Arguments
    if ($args -match "stage-upgrade\.ps1") {
      Log "Detected self-loop in $TaskName (points to stage-upgrade). Removing it."
      Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
  }
} catch { Log "Warning checking existing task: $($_.Exception.Message)" }

# --- ISO present or download ---
try {
  if (Test-Path $IsoPath) {
    Log "ISO present: $IsoPath"
  } else {
    $alt = Get-ChildItem -Path $Root -Filter *.iso -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($alt) {
      $IsoPath = $alt.FullName
      Log "Found alternate ISO: $IsoPath"
    } else {
      Log "Downloading ISO from $IsoUrl ..."
      Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoPath -UseBasicParsing -TimeoutSec 7200
      if (!(Test-Path $IsoPath)) { Abort "ISO download failed." }
      Log "ISO downloaded."
    }
  }
} catch { Abort "Error obtaining ISO: $($_.Exception.Message)" }

# --- Extract ISO (idempotent) ---
try {
  # If already extracted and setup.exe exists, skip extraction
  $SetupFromExtract = Join-Path $ExtractDir "setup.exe"
  if (Test-Path $SetupFromExtract) {
    Log "Extraction already present at $ExtractDir (setup.exe found) – skipping extract."
  } else {
    Log "Mounting ISO for extraction..."
    $mount = Mount-DiskImage -ImagePath $IsoPath -PassThru
    Start-Sleep -Seconds 3
    $vol = $mount | Get-Volume -ErrorAction SilentlyContinue
    if (-not $vol) { Abort "Unable to determine mounted drive letter." }
    $Drive = "$($vol.DriveLetter):"
    Log "Mounted ISO at $Drive"

    Log "Extracting to $ExtractDir ..."
    New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
    # Quiet robocopy copy of all files
    robocopy "$Drive\" $ExtractDir /E /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
    Log "Extraction complete."

    Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
    Log "ISO dismounted."
  }
} catch { Abort "Error during mount/extract: $($_.Exception.Message)" }

# --- Verify run-upgrade.ps1 exists ---
if (-not (Test-Path $RunScript)) {
  # If you prefer to keep scripts at root, you can fall back:
  $rootRun = Join-Path $Root "run-upgrade.ps1"
  if (Test-Path $rootRun) {
    Log "run-upgrade.ps1 not found at repo path; using root copy: $rootRun"
    $RunScript = $rootRun
  } else {
    Abort "Missing run-upgrade.ps1 at $RunScript"
  }
}

# --- Register and start Win11_RunUpgrade (points to run-upgrade.ps1) ---
try {
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Log "Removed previous task $TaskName"
  }

  $args = "-ExecutionPolicy Bypass -File `"$RunScript`""
  $action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $args
  $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds(20))   # short delay; avoids race with TS
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -RunLevel Highest -User "SYSTEM" -Force | Out-Null
  Start-ScheduledTask -TaskName $TaskName
  Log "Scheduled and started task '$TaskName' with args: $args"
} catch { Abort "Failed to register/start $TaskName: $($_.Exception.Message)" }

Log "stage-upgrade complete."
