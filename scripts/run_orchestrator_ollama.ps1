Set-Location $PSScriptRoot\..

if (-not (Test-Path .\.venv\Scripts\python.exe)) {
  Write-Error "Missing .venv. Run scripts/setup_orchestrator_env.ps1 first."
  exit 1
}

$env:MODEL_API_ENABLED = "true"
$env:MODEL_PROVIDER = "ollama"
$env:OLLAMA_BASE_URL = "http://127.0.0.1:11434"
$env:OLLAMA_MODEL = "qwen2.5:14b"
$env:OLLAMA_PLANNER_MODEL = "qwen2.5:7b"
$env:OLLAMA_PLANNER_TEMPERATURE = "0.0"
$env:OLLAMA_PLANNER_NUM_PREDICT = "512"
$env:MODEL_API_TIMEOUT_S = "120"

.\.venv\Scripts\python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --app-dir orchestrator
