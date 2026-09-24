@echo off
REM Launch Metra Ops tray host (user-session). Prefers MetraHost.exe when built.
setlocal
cd /d "%~dp0"

echo %*| find /I "-Stop" >nul
if not errorlevel 1 (
  powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\bootstrap\Start-MetraOpsHost.ps1" %*
  exit /b %ERRORLEVEL%
)

set "HOST_EXE="
if exist "%~dp0host\MetraHost\publish\MetraHost.exe" set "HOST_EXE=%~dp0host\MetraHost\publish\MetraHost.exe"
if not defined HOST_EXE if exist "%~dp0host\MetraHost\bin\Release\net8.0-windows\MetraHost.exe" set "HOST_EXE=%~dp0host\MetraHost\bin\Release\net8.0-windows\MetraHost.exe"
if not defined HOST_EXE if exist "%~dp0host\MetraHost\bin\Debug\net8.0-windows\MetraHost.exe" set "HOST_EXE=%~dp0host\MetraHost\bin\Debug\net8.0-windows\MetraHost.exe"

if defined HOST_EXE (
  start "" "%HOST_EXE%" --root "%~dp0." --no-browser %*
  endlocal
  exit /b 0
)

start "" powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0scripts\bootstrap\Start-MetraOpsHost.ps1" %*
endlocal
