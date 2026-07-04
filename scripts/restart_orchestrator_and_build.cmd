@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File "%SCRIPT_DIR%restart_orchestrator_and_build.ps1" -Mode ollama
exit /b 0
