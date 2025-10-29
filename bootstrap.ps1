# bootstrap.ps1
$ErrorActionPreference = "Stop"
$Root = "C:\Win11Upgrade"
$RepoPath = Join-Path $Root "Project811-main"
$Stage = Join-Path $RepoPath "stage-upgrade.ps1"
$Log = Join-Path $Root "bootstrap.log"

function Log($m){$t=(Get-Date).ToString("yyyy-MM-dd HH:mm:ss");Add-Content -Path $Log -Value "[$t] $m"}

Log "=== Bootstrap starting under $env:USERNAME ==="

try {
    if (!(Test-Path $Stage)) { throw "stage-upgrade.ps1 not found at $Stage" }

    # --- Optional: create log folder etc. ---
    Log "Executing stage-upgrade.ps1 directly..."
    powershell -ExecutionPolicy Bypass -NoProfile -File $Stage
    Log "Bootstrap complete."
}
catch {
    Log "FATAL: $_"
}
