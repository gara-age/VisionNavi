@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
start "VisionNavi Orchestrator" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File "%SCRIPT_DIR%restart_orchestrator.ps1" -Mode ollama -RunForeground
exit /b 0
