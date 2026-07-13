@echo off
setlocal

set SCRIPT_DIR=%~dp0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%watch_wakeword_dev_training.ps1" %*

endlocal
