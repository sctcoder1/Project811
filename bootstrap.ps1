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

# --- Inside bootstrap.ps1 ---
try {
    if (Test-Path $stage) {
        Log "Found stage-upgrade.ps1 at $stage"
        $taskName = "Win11_StageUpgrade"

        # Remove any previous version
        schtasks /delete /tn $taskName /f 2>$null

        # Build XML for the task definition (correct quoting, split args)
        $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <TimeTrigger>
      <StartBoundary>$(Get-Date).AddSeconds(30).ToString('s')</StartBoundary>
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
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -NoProfile -File "C:\Win11Upgrade\Project811-main\stage-upgrade.ps1"</Arguments>
      <WorkingDirectory>C:\Win11Upgrade\Project811-main</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

        $xmlPath = Join-Path $root "stage-task.xml"
        $xml | Out-File -Encoding unicode -FilePath $xmlPath -Force

        schtasks /create /tn $taskName /xml $xmlPath /ru SYSTEM /f | Out-Null
        schtasks /run /tn $taskName | Out-Null
        Log "Registered and started scheduled task $taskName successfully via XML method."
    }
    else {
        Log "ERROR: stage-upgrade.ps1 not found at $stage"
    }
}
catch {
    Log "FATAL during task creation: $_"
}

Start-Sleep -Seconds 5
Log "Bootstrap finished."
