# bootstrap.ps1 (robust, idempotent)
$Root = "C:\Win11Upgrade"
$Log  = Join-Path $Root "bootstrap.log"
$Lock = Join-Path $Root "bootstrap.lock"
$Done = Join-Path $Root "bootstrap.done"
$StageUrl = "https://raw.githubusercontent.com/sctcoder1/Project811/main/stage-upgrade.ps1"
$StageScript = Join-Path $Root "stage-upgrade.ps1"

function Write-Log {
    param($m)
    $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $msg = "[$t] $m"
    Add-Content -Path $Log -Value $msg
}

# Prevent concurrent runs
if (Test-Path $
