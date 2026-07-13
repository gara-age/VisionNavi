@echo off
setlocal
set SCRIPT_DIR=%~dp0
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%watch_wakeword_prod_training.ps1" %*
endlocal
