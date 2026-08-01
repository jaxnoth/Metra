@echo off
setlocal
REM Double-click / Start Menu / installer entry. Batch is not subject to PowerShell execution policy.
REM Process-scoped Bypass only - does not change machine ExecutionPolicy.
REM Pass -NoPause when launched from the installer post-install task.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\bootstrap\Start-MetraSetup.ps1" %*
set EXITCODE=%ERRORLEVEL%
exit /b %EXITCODE%
