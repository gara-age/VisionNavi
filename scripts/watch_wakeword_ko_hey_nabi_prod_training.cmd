@echo off
set SCRIPT_DIR=%~dp0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%watch_wakeword_ko_hey_nabi_prod_training.ps1" %*

