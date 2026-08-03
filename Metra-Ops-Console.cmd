@echo off
REM Operator escape hatch: Metra Ops in a visible PowerShell console (debug).
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\bootstrap\Start-MetraOps.ps1" %*
endlocal
