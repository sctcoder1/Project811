<#
run-upgrade.ps1
Purpose: Executes the Windows 11 in-place upgrade silently, handling reboot logic
depending on user presence. Runs under SYSTEM.
#>

$Root     = "C:\Win11Upgrade"
$LogFile  = Join-Path $Root "run-upgrade.log"
$IsoPath  = Join-Path $Root "Win11_24H2.iso"

# --- Logging helper ---
function Log {
    param([string]$msg)
    $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "[$t] $msg"
}

function Abort {
    param([string]$msg)
    Log "FATAL: $msg"
    throw $msg
}

Log "=== run-upgrade started under $env:USERNAME ==="

# --- Find mounted ISO drive ---
try {
    $disk = Get-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
    if ($disk -and $disk.Attached) {
        $vol = $disk | Get-Volume -ErrorAction SilentlyContinue
        if ($vol) {
            $DriveLetter = "$($vol.DriveLetter):"
            Log "ISO already mounted at drive $DriveLetter"
        }
    }
    if (-not $DriveLetter) {
        Log "ISO not mounted, searching available drives..."
        $DriveLetter = (Get-Volume | Where-Object { Test-Path "$($_.DriveLetter):\sources\setup.exe" } | Select-Object -First 1).DriveLetter + ":"
    }
    if (-not $DriveLetter) { Abort "Unable to determine ISO mount point." }
    Log "Using drive $DriveLetter for setup."
}
catch { Abort "Error locating ISO drive: $_" }

# --- Find setup.exe ---
$SetupExe = Join-Path $DriveLetter "setup.exe"
if (!(Test-Path $SetupExe)) { Abort "setup.exe not found at $SetupExe" }
Log "Confirmed setup.exe exists."

# --- Apply upgrade bypass registry keys ---
try {
    $mo = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\MoSetup"
    if (!(Test-Path $mo)) { New-Item -Path $mo -Force | Out-Null }
    Set-ItemProperty -Path $mo -Name "AllowUpgradesWithUnsupportedTPMOrCPU" -Value 1 -Type DWord -Force
    Log "Set MoSetup bypass key."
}
catch { Log "WARNING: Failed to set bypass key - $($_.Exception.Message)" }

# --- Detect logged-in user ---
try {
    $users = (quser 2>$null)
    if ($users -match "Active") {
        $UserActive = $true
        Log "Active user detected via quser."
    } else {
        # fallback check
        $session = (Get-CimInstance -Class Win32_ComputerSystem).UserName
        if ($session) {
            $UserActive = $true
            Log "Active user detected via Win32_ComputerSystem: $session"
        } else {
            $UserActive = $false
            Log "No active user session detected."
        }
    }
}
catch {
    Log "Error checking user state: $_"
    $UserActive = $false
}

# --- Build setup arguments ---
if ($UserActive) {
    $Args = "/auto upgrade /quiet /NoReboot /Compat IgnoreWarning /DynamicUpdate Disable /Eula accept"
    Log "User logged in — running upgrade with /NoReboot"
} else {
    $Args = "/auto upgrade /quiet /Compat IgnoreWarning /DynamicUpdate Disable /Eula accept"
    Log "No user logged in — running upgrade with reboot allowed"
}

# --- Launch upgrade ---
try {
    Log "Launching setup.exe..."
    Start-Process -FilePath $SetupExe -ArgumentList $Args -WindowStyle Hidden -NoNewWindow
    Log "setup.exe launched successfully."
}
catch { Abort "Failed to launch setup.exe: $_" }

# --- Optional cleanup registration ---
try {
    $CleanupBat = Join-Path $Root "Cleanup_Win11Upgrade.bat"
    if (Test-Path $CleanupBat) {
        New-Item -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Force | Out-Null
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
            -Name "Win11Cleanup" -Value "cmd /c `"$CleanupBat`""
        Log "Registered cleanup script for post-upgrade."
    } else {
        Log "Cleanup file not found, skipping registration."
    }
}
catch { Log "Warning: could not register cleanup task. $_" }

Log "run-upgrade completed — system will reboot automatically if no user is logged in."
