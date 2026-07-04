Set-Location $PSScriptRoot\..

. "$PSScriptRoot\resolve_orchestrator_python.ps1"

$projectRoot = (Get-Location).Path
$pythonExe = Resolve-OrchestratorPython -ProjectRoot $projectRoot

if (-not $pythonExe) {
  Write-Error "Missing orchestrator environment. Run scripts/setup_orchestrator_env.ps1 first."
  exit 1
}

$env:DEFAULT_BROWSER_EXECUTION_BACKEND = "external_browser_agent"
$env:DEFAULT_DESKTOP_EXECUTION_BACKEND = "external_desktop_agent"
$env:EXTERNAL_AGENT_FALLBACK_TO_INTERNAL = "true"

& $pythonExe -m uvicorn app.main:app --host 127.0.0.1 --port 8010 --reload --app-dir orchestrator
