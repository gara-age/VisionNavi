@echo off
set SCRIPT_DIR=%~dp0
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%start_wakeword_training_ko_hey_nabi_prod.ps1" %*

