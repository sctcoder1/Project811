<#
bootstrap.ps1
Purpose:
  Initial entry point triggered by Sophos.
  Ensures C:\Win11Upgrade exists, unblocks scripts, then schedules
  and runs stage-upgrade.ps1 under SYSTEM via a well-formed XML task.
#>

$ErrorActionPreference = "Stop"

# --- Config ---
$Root  = "C:\Win11Upgrade"
$RepoDir = Join-Path $Root "Project811-main"
$StageScript = Join-Path $RepoDir "stage-upgrade.ps1"
$Log   = Join-Path $Root "bootstrap.log"
$Task  = "Win11_StageUpgrade"
$PsExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$XmlPath = Join-Path $Root "stage-task.xml"

# --- Logging helper ---
function Log($m) {
    try {
        if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Force -Path $Root | Out-Null }
        $t = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Add-Content -Path $Log -Value "[$t] $m"
    } catch { Write-Host $m }
}

Log "=== Bootstrap starting under $env:USERNAME ==="

# --- Prep ---
try {
    Get-ChildItem $Root -Recurse -Include *.ps1 -ErrorAction SilentlyContinue | Unblock-File
    Log "Unblocked PowerShell scripts in $Root."
} catch { Log "Warning: Could not unblock files. $_" }

# Remove previous task if it exists
try {
    if (Get-ScheduledTask -TaskName $Task -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $Task -Confirm:$false -ErrorAction SilentlyContinue
        Log "Removed old $Task task."
    }
} catch { Log "Warning: Could not remove old task. $_" }

# --- Create the scheduled task XML ---
try {
    if (Test-Path $StageScript) {
        Log "Found stage-upgrade.ps1 at $StageScript"

        $StageDir = Split-Path $StageScript -Parent
        Log "Using working directory: $StageDir"

        # Build XML content dynamically
        $XMLContent = @"
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
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$PsExe</Command>
      <Arguments>-ExecutionPolicy Bypass -NoProfile -File `"$StageScript`"</Arguments>
      <WorkingDirectory>$StageDir</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

        $XMLContent | Out-File -Encoding Unicode -FilePath $XmlPath -Force
        Log "Created task XML at $XmlPath"

        # Register and run the task
        $Create = schtasks /create /tn $Task /xml $XmlPath /ru SYSTEM /f 2>&1
        Log "schtasks /create output: $Create"

        $Run = schtasks /run /tn $Task 2>&1
        Log "schtasks /run output: $Run"

        Log "Task $Task registered and started successfully via XML."
    } else {
        Log "ERROR: stage-upgrade.ps1 not found at $StageScript"
    }
}
catch {
    Log "FATAL during task creation: $_"
}

Start-Sleep -Seconds 5
Log "Bootstrap finished."
