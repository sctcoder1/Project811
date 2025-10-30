<#
run-upgrade.ps1
Purpose:
  Execute Windows 11 setup.exe silently from extracted ISO folder.
  Wait for Modern Setup Host to complete before prompting user or scheduling reboot.
  Assumes ISO contents are already in C:\Win11Upgrade\ISOFiles.
#>

$ErrorActionPreference = "Stop"
$Root    = "C:\Win11Upgrade"
$IsoDir  = Join-Path $Root "ISOFiles"
$Setup   = Join-Path $IsoDir "setup.exe"
$LogFile = Join-Path $Root "run-upgrade.log"

function Log($m) {
    $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "[$t] $m"
}

Log "=== run-upgrade started under $env:USERNAME ==="

if (!(Test-Path $Setup)) {
    Log "FATAL: setup.exe not found in $IsoDir."
    exit 1
}

# --- Bypass hardware checks ---
try {
    $mo = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\MoSetup"
    if (!(Test-Path $mo)) { New-Item -Path $mo -Force | Out-Null }
    Set-ItemProperty -Path $mo -Name "AllowUpgradesWithUnsupportedTPMOrCPU" -Value 1 -Type DWord -Force
    Log "Set bypass key."
} catch { Log "Warning: failed to set bypass key. $_" }

# --- Detect active user session ---
$UserActive = $false
try {
    $users = (quser 2>$null)
    if ($users -match "Active") { $UserActive = $true; Log "Active user detected via quser." }
    else { Log "No active user detected." }
} catch { Log "Could not determine active user via quser. $_" }

# --- Build setup arguments ---
if ($UserActive) {
    $Args = "/auto upgrade /quiet /NoReboot /Compat IgnoreWarning /DynamicUpdate Disable /Eula accept"
    Log "User logged in — upgrade will not auto-reboot."
} else {
    $Args = "/auto upgrade /quiet /Compat IgnoreWarning /DynamicUpdate Disable /Eula accept"
    Log "No user detected — reboot allowed."
}

# --- Launch setup ---
try {
    Log "Launching setup.exe..."
    Start-Process -FilePath $Setup -ArgumentList $Args -WindowStyle Hidden
    Log "Setup launched successfully."
} catch {
    Log "ERROR: Failed to start setup.exe. $_"
    exit 1
}

# --- Wait for Modern Setup Host to appear ---
Log "Waiting for ModernSetupHost process..."
while (-not (Get-Process -Name "ModernSetupHost" -ErrorAction SilentlyContinue)) {
    Start-Sleep -Seconds 3
}
Log "ModernSetupHost detected."

# --- Wait for setup to finish ---
while (Get-Process -Name "ModernSetupHost" -ErrorAction SilentlyContinue) {
    Start-Sleep -Seconds 10
}
Log "ModernSetupHost exited — staging phase complete."

# --- Handle reboot scheduling ---
$now = Get-Date
$rebootAt = (Get-Date -Hour 18 -Minute 0 -Second 0)
if ($rebootAt -lt $now) { $rebootAt = $rebootAt.AddDays(1) } # if 6 PM already passed, use tomorrow

$session = (Get-CimInstance -ClassName Win32_ComputerSystem).UserName

if ($session) {
    Log "Active user session detected: $session"

    # Notify user to save work and reboot
    $msg = "Windows 11 upgrade is ready to install.`n`n" +
           "Please save all work and reboot now to continue.`n" +
           "If you do nothing, the system will reboot automatically at $($rebootAt.ToString('h:mm tt'))."
    try {
        msg * "$msg" /time:300
        Log "Displayed save-your-work message to active session."
    } catch {
        Log "Failed to send message: $_"
    }

    # Schedule reboot task
    Log "Scheduling reboot task for $($rebootAt.ToString('yyyy-MM-dd HH:mm:ss'))."

    $startBoundary = $rebootAt.ToString("yyyy-MM-ddTHH:mm:ss")
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <TimeTrigger>
      <StartBoundary>$startBoundary</StartBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>SYSTEM</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <StartWhenAvailable>true</StartWhenAvailable>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>shutdown.exe</Command>
      <Arguments>/r /t 60 /c "Windows 11 upgrade will now continue."</Arguments>
    </Exec>
  </Actions>
</Task>
"@

    $xmlPath = Join-Path $Root "RebootTask.xml"
    $xml | Out-File -Encoding Unicode -FilePath $xmlPath -Force

    schtasks /delete /tn "Win11_DeferredReboot" /f 2>$null | Out-Null
    schtasks /create /tn "Win11_DeferredReboot" /xml $xmlPath /ru SYSTEM /f | Out-Null
    Log "Reboot task created successfully for $($rebootAt.ToString('t'))."
}
else {
    Log "No logged-in user — rebooting automatically."
    shutdown /r /t 60 /c "Windows 11 upgrade will now continue." | Out-Null
}

Log "=== run-upgrade complete ==="
