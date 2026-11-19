@echo off
setlocal
set "ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%_internal\TorTunnel-Control.ps1" -Root "%ROOT%"
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
