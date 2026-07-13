Set-Location $PSScriptRoot\..

. "$PSScriptRoot\resolve_orchestrator_python.ps1"

$projectRoot = (Get-Location).Path
$pythonExe = Resolve-OrchestratorPython -ProjectRoot $projectRoot

if (-not $pythonExe) {
  Write-Error "Missing orchestrator environment. Run scripts/setup_orchestrator_env.ps1 first."
  exit 1
}

$env:MODEL_API_ENABLED = "true"
$env:MODEL_PROVIDER = "ollama"
$env:OLLAMA_BASE_URL = "http://127.0.0.1:11434"
$env:OLLAMA_MODEL = "qwen2.5:14b"
$env:OLLAMA_MODEL_KO = "exaone3.5:7.8b"
$env:OLLAMA_MODEL_JA = "dsasai/llama3-elyza-jp-8b"
$env:OLLAMA_PLANNER_MODEL = "qwen2.5:7b"
$env:OLLAMA_PLANNER_MODEL_KO = "exaone3.5:7.8b"
$env:OLLAMA_PLANNER_MODEL_JA = "dsasai/llama3-elyza-jp-8b"
$env:OLLAMA_VISION_MODEL = "qwen2.5vl:3b"
$env:OLLAMA_VISION_ENABLED = "true"
$env:OLLAMA_VISION_NUM_PREDICT = "256"
$env:OLLAMA_PLANNER_TEMPERATURE = "0.0"
$env:OLLAMA_PLANNER_NUM_PREDICT = "512"
$env:EXTERNAL_BROWSER_AGENT_MODEL = "qwen2.5:7b"
$env:EXTERNAL_BROWSER_AGENT_MAX_STEPS = "6"
$env:EXTERNAL_BROWSER_AGENT_STEP_TIMEOUT_S = "45"
$env:EXTERNAL_DESKTOP_AGENT_MODEL = "qwen2.5vl:3b"
$env:EXTERNAL_DESKTOP_AGENT_MAX_LOOPS = "10"
$env:EXTERNAL_DESKTOP_AGENT_TIMEOUT_S = "180"
$env:DEFAULT_BROWSER_EXECUTION_BACKEND = "external_browser_agent"
$env:DEFAULT_DESKTOP_EXECUTION_BACKEND = "external_desktop_agent"
$env:EXTERNAL_AGENT_FALLBACK_TO_INTERNAL = "true"
$env:MODEL_API_TIMEOUT_S = "120"
$env:PLAYWRIGHT_HEADLESS = "false"
$env:PLAYWRIGHT_USE_CDP = "true"
$env:PLAYWRIGHT_CDP_URL = "http://127.0.0.1:9222"
$env:ITERATIVE_BROWSER_LOOP_ENABLED = "true"
$env:ITERATIVE_BROWSER_MAX_STEPS = "12"
$env:WAKEWORD_BACKEND = "livekit-wakeword"
$env:WAKEWORD_MANIFEST_PATH = "runtime/wakewords/manifest.json"
$env:WAKEWORD_THRESHOLD = "0.5"
$env:WAKEWORD_DEBOUNCE_SECONDS = "2.0"
$env:PYTHONUTF8 = "1"

& $pythonExe -m uvicorn app.main:app --host 127.0.0.1 --port 8010 --app-dir orchestrator
