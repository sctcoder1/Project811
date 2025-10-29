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

# --- Run StageUpgrade task ---
try {
    if (Get-ScheduledTask -TaskName "Win11_StageUpgrade" -ErrorAction SilentlyContinue) {
        schtasks /run /tn "Win11_StageUpgrade" | Out-Null
        Log "Ran existing StageUpgrade task."
    } else {
        Log "ERROR: StageUpgrade task not found."
    }
}
catch {
    Log "FATAL: could not start StageUpgrade task. $_"
}

Start-Sleep -Seconds 5
Log "Bootstrap finished."
