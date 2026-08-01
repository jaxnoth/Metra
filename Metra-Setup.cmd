@echo off
setlocal
REM Double-click entry for ZIP / blocked checkouts. Batch is not subject to PowerShell execution policy.
REM Process-scoped Bypass only - does not change machine ExecutionPolicy.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\bootstrap\Start-MetraSetup.ps1"
set EXITCODE=%ERRORLEVEL%
exit /b %EXITCODE%
