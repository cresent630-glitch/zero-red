@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
where pwsh.exe >nul 2>nul
if errorlevel 1 (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0scripts\github-ipa.ps1"
) else (
    pwsh.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0scripts\github-ipa.ps1"
)
set "ipa_exit=%errorlevel%"
echo.
if not "%CI%"=="" exit /b %ipa_exit%
pause
exit /b %ipa_exit%