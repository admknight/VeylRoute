@echo off
setlocal
set "ROOT=%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "%ROOT%Verify-Windows.ps1"
set "RESULT=%errorlevel%"
echo.
if not "%RESULT%"=="0" (echo WINDOWS QUALIFICATION FAILED. Please keep the report.) else (echo Basic Windows checks passed. Network tests still required.)
pause
exit /b %RESULT%
