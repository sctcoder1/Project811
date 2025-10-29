<#
bootstrap.ps1
Purpose:
  Initial entry point triggered by Sophos.
  Creates C:\Win11Upgrade, downloads or uses existing repo,
  then schedules and starts Win11_StageUpgrade under SYSTEM.
#>

$ErrorActionPreference = "Stop"

# --- Config ---
$root  = "C:\Win11Upgrade"
$stage = Join-Path $root "Project811-main\stage-upgrade.ps1"
$log   = Join-Path $root "bootstrap.log"
$task  = "Win11_StageUpgrade"

# --- Logging helper ---
function Log($m) {
    try {
        if (-not (Test-Path $root)) { New-Item -ItemType Directory -Force -Path $root | Out-Null }
        $t = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Add-Content -Path $log -Value "[$t] $m"
    } catch {
        Write-Host $m
    }
}

Log "=== Bootstrap starting under $env:USERNAME ==="

# --- Safety / prep ---
# Unblock files so SYSTEM can run them
try {
    Get-ChildItem $root -Recurse -Include *.ps1 -ErrorAction SilentlyContinue | Unblock-File
    Log "Unblocked PowerShell scripts in $root."
} catch { Log "Warning: Could not unblock files. $_" }

# Remove old task if present (avoids conflict)
try {
    if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
        Log "Removed existing $task task."
    }
} catch { Log "Warning: could not remove old task. $_" }

# --- Create task only if stage script exists ---
if (Test-Path $stage) {
    Log "Found stage-upgrade.ps1 at $stage"

    # Use full PowerShell path (fixes 0x1 issue)
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    # Add NoProfile and working directory
    $args = "-ExecutionPolicy Bypass -NoProfile -File `"$stage`""
    $action = New-ScheduledTaskAction -Execute $ps -Argument $args -WorkingDirectory (Split-Path $stage)
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds(30))

    Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -RunLevel Highest -User "SYSTEM" -Force | Out-Null
    Start-ScheduledTask -TaskName $task
    Log "Registered and started scheduled task $task successfully."
} else {
    Log "ERROR: stage-upgrade.ps1 not found at expected path."
}

Start-Sleep -Seconds 5
Log "Bootstrap finished."
