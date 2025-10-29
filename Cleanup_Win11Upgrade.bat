@echo off
title Windows 11 Upgrade Cleanup
setlocal
set "ROOT=C:\Win11Upgrade"
set "LOG=%ROOT%\cleanup.log"
echo [%date% %time%] --- Cleanup starting --- >> "%LOG%"

:: Dismount any mounted ISO matching our file
echo [%date% %time%] Dismounting ISO if mounted... >> "%LOG%"
for /f "tokens=2 delims==" %%I in ('powershell -NoProfile -Command "Get-DiskImage -ImagePath '%ROOT%\Win11_24H2.iso' -ErrorAction SilentlyContinue | Where-Object { $_.Attached -eq $true } | Measure-Object | Select -ExpandProperty Count"') do set MOUNTED=%%I
powershell -NoProfile -Command "try { Dismount-DiskImage -ImagePath '%ROOT%\Win11_24H2.iso' -ErrorAction SilentlyContinue } catch {}" >> "%LOG%" 2>&1

:: Remove scheduled tasks created during process
echo [%date% %time%] Removing scheduled tasks... >> "%LOG%"
schtasks /delete /tn "Win11_Bootstrap" /f >nul 2>&1
schtasks /delete /tn "Win11_StageUpgrade" /f >nul 2>&1
schtasks /delete /tn "Win11_RunUpgrade" /f >nul 2>&1

:: Delete leftover files
echo [%date% %time%] Deleting upgrade files... >> "%LOG%"
if exist "%ROOT%" (
    rmdir /s /q "%ROOT%"
    echo [%date% %time%] Removed %ROOT% >> "%LOG%"
)

:: Optional: Clear any leftover RunOnce entries for safety
reg delete "HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce" /v "Win11Cleanup" /f >nul 2>&1

echo [%date% %time%] Cleanup complete. >> "%LOG%"
endlocal
exit /b 0
