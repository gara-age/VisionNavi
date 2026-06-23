# VisionNavi

VisionNavi is a vision-first hybrid desktop agent for accessibility-oriented browser and Windows automation.

## Repository Layout

- `frontend/`: Flutter desktop UI for voice/text input, session status, and feedback
- `orchestrator/`: FastAPI-based local orchestrator and agent loop
- `contracts/`: Shared schemas exchanged between UI, orchestrator, and model services
- `docs/`: Architecture, roadmap, and design notes

## Target Flow

```text
STT -> Command Normalizer -> Intent Router / Safety Classifier
   -> Observe / Decide / Act / Verify / Recover
   -> Browser/Desktop execution
   -> UI/TTS feedback
```

## MVP Focus

1. Voice and text command intake
2. Command normalization and safety classification
3. Browser search-and-read flow
4. Notepad launch and text entry
5. Windows dark mode transition
6. Visible session state and interrupt controls

See [docs/architecture.md](/C:/Users/USER/Documents/VisionNavi/docs/architecture.md) and [docs/mvp-roadmap.md](/C:/Users/USER/Documents/VisionNavi/docs/mvp-roadmap.md) for details.

## Local Run

1. Run `powershell -ExecutionPolicy Bypass -File .\scripts\setup_orchestrator_env.ps1`
2. Run `powershell -ExecutionPolicy Bypass -File .\scripts\run_orchestrator.ps1`
3. In another shell, run the Flutter desktop app from `frontend/`

## Optional Remote Model API

Set these environment variables before running the orchestrator to enable LLM-assisted canonical command generation:

- `MODEL_API_ENABLED=true`
- `MODEL_API_URL=http://your-model-server/canonical-command`
- `MODEL_API_KEY=...` (optional)
- `MODEL_API_TIMEOUT_S=15` (optional)

Expected response JSON:

```json
{
  "normalized_text": "Windows dark mode",
  "task_domain": "desktop",
  "intent": "change_system_setting",
  "target_app": "windows_settings",
  "notes": ["remote_model"]
}
```

## Local Ollama With Qwen 2.5 14B

This desktop already has Ollama and `qwen2.5:14b` installed. To use it directly:

```powershell
$env:MODEL_API_ENABLED="true"
$env:MODEL_PROVIDER="ollama"
$env:OLLAMA_BASE_URL="http://127.0.0.1:11434"
$env:OLLAMA_MODEL="qwen2.5:14b"
powershell -ExecutionPolicy Bypass -File .\scripts\run_orchestrator.ps1
```

The orchestrator will call Ollama's local server and fall back to rule-based routing if the model call fails.

For this repository, you can also use the bundled launcher:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_orchestrator_ollama.ps1
```
