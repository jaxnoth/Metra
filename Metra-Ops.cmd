@echo off
REM Launch Metra Ops tray host (user-session). Loopback desk stays up without a console.
setlocal
cd /d "%~dp0"

echo %*| find /I "-Stop" >nul
if not errorlevel 1 (
  powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\bootstrap\Start-MetraOpsHost.ps1" %*
  exit /b %ERRORLEVEL%
)

start "" powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0scripts\bootstrap\Start-MetraOpsHost.ps1" %*
endlocal
