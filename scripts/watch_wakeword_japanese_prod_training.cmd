@echo off
set SCRIPT_DIR=%~dp0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%watch_wakeword_japanese_prod_training.ps1" %*
