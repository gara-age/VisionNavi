Set-Location $PSScriptRoot\..

if (-not (Test-Path .\.venv\Scripts\python.exe)) {
  Write-Error "Missing .venv. Run scripts/setup_orchestrator_env.ps1 first."
  exit 1
}

.\.venv\Scripts\python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload --app-dir orchestrator
