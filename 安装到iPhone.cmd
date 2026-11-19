@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
where pwsh.exe >nul 2>nul
if errorlevel 1 (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0scripts\install-iphone.ps1"
) else (
    pwsh.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0scripts\install-iphone.ps1"
)
set "install_exit=%errorlevel%"
echo.
if not "%CI%"=="" exit /b %install_exit%
pause
exit /b %install_exit%