$root = "C:\Win11Upgrade"
$stage = Join-Path $root "Project811-main\stage-upgrade.ps1"
$log  = Join-Path $root "bootstrap.log"

function Log($m) {
    $t = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -Path $log -Value "[$t] $m"
}

Log "Bootstrap starting."
if (Test-Path $stage) {
    Log "Found stage-upgrade.ps1, scheduling..."
    $action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$stage`""
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))
    Register-ScheduledTask -TaskName "Win11_StageUpgrade" -Action $action -Trigger $trigger -RunLevel Highest -User "SYSTEM" -Force | Out-Null
    Start-ScheduledTask -TaskName "Win11_StageUpgrade"
    Log "Stage task registered and started."
} else {
    Log "ERROR: stage-upgrade.ps1 not found."
}
Start-Sleep -Seconds 5
Log "Bootstrap finished."
