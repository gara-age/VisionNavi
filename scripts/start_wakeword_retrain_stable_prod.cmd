@echo off
setlocal
cd /d "%~dp0.."
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_wakeword_retrain_stable_prod.ps1" -Background
pause
