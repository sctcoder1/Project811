<#
run-upgrade.ps1
Purpose:
  Execute Windows 11 setup.exe silently from extracted ISO folder.
  Assumes ISO contents are already in C:\Win11Upgrade\ISOFiles.
#>

$ErrorActionPreference = "Stop"
$Root    = "C:\Win11Upgrade"
$IsoDir  = Join-Path $Root "ISOFiles"
$Setup   = Join-Path $IsoDir "setup.exe"
$LogFile = Join-Path $Root "run-upgrade.log"

function Log($m){$t=(Get-Date).ToString("yyyy-MM-dd HH:mm:ss");Add-Content -Path $LogFile -Value "[$t] $m"}

Log "=== run-upgrade started under $env:USERNAME ==="

if (!(Test-Path $Setup)) {
    Log "FATAL: setup.exe not found in $IsoDir."
    exit 1
}

# Bypass hardware checks
try {
    $mo = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\MoSetup"
    if (!(Test-Path $mo)) { New-Item -Path $mo -Force | Out-Null }
    Set-ItemProperty -Path $mo -Name "AllowUpgradesWithUnsupportedTPMOrCPU" -Value 1 -Type DWord -Force
    Log "Set bypass key."
} catch { Log "Warning: failed to set bypass key. $_" }

# Detect active user session
$UserActive = $false
try {
    $users = (quser 2>$null)
    if ($users -match "Active") { $UserActive = $true; Log "Active user detected via quser." }
} catch { }

# Build arguments
if ($UserActive) {
    $Args = "/auto upgrade /quiet /NoReboot /Compat IgnoreWarning /DynamicUpdate Disable /Eula accept"
    Log "User logged in — upgrade will not auto-reboot."
} else {
    $Args = "/auto upgrade /quiet /Compat IgnoreWarning /DynamicUpdate Disable /Eula accept"
    Log "No user detected — reboot allowed."
}

# Launch setup
try {
    Log "Launching setup.exe..."
    Start-Process -FilePath $Setup -ArgumentList $Args -WindowStyle Hidden
    Log "Setup launched successfully."
} catch { Log "ERROR: Failed to start setup.exe. $_" }

Log "run-upgrade complete."
