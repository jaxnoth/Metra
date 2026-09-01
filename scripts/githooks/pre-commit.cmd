@ECHO OFF
pwsh -NoProfile -File "%~dp0pre-commit.ps1" %*
exit /b %ERRORLEVEL%
