param(
  [ValidateSet("ollama", "dev")]
  [string]$Mode = "ollama",
  [int]$Port = 8010,
  [switch]$Hidden,
  [switch]$RunForeground,
  [int]$StartupTimeoutSec = 30
)

$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot\..

if (-not (Test-Path .\.venv\Scripts\python.exe)) {
  Write-Error "Missing .venv. Run scripts/setup_orchestrator_env.ps1 first."
  exit 1
}

function Get-ListeningPids {
  param([int]$TargetPort)

  $pids = @()

  try {
    $connections = Get-NetTCPConnection -LocalPort $TargetPort -State Listen -ErrorAction Stop
    $pids = $connections | Select-Object -ExpandProperty OwningProcess -Unique
  } catch {
    $netstatOutput = netstat -ano -p tcp | Select-String ":$TargetPort\s+.*LISTENING\s+(\d+)$"
    foreach ($line in $netstatOutput) {
      if ($line.Matches.Count -gt 0) {
        $pids += [int]$line.Matches[0].Groups[1].Value
      }
    }
    $pids = $pids | Select-Object -Unique
  }

  return @($pids)
}

function Stop-OrchestratorProcesses {
  param([int]$TargetPort)

  $listeningPids = Get-ListeningPids -TargetPort $TargetPort
  if (-not $listeningPids -or $listeningPids.Count -eq 0) {
    Write-Host "No orchestrator process is listening on port $TargetPort."
    return
  }

  foreach ($processId in $listeningPids) {
    try {
      $process = Get-Process -Id $processId -ErrorAction Stop
      Write-Host "Stopping PID $processId ($($process.ProcessName)) on port $TargetPort..."
      Stop-Process -Id $processId -Force -ErrorAction Stop
    } catch {
      Write-Warning "Failed to stop PID ${processId}: $($_.Exception.Message)"
    }
  }

  Start-Sleep -Seconds 1
}

function Wait-ForHealth {
  param(
    [int]$TargetPort,
    [int]$TimeoutSec
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $healthUrl = "http://127.0.0.1:$TargetPort/health"

  while ((Get-Date) -lt $deadline) {
    try {
      $response = Invoke-RestMethod -Uri $healthUrl -Method Get -TimeoutSec 3
      if ($response.status -eq "ok") {
        return $true
      }
    } catch {
      Start-Sleep -Milliseconds 700
    }
  }

  return $false
}

function Set-OrchestratorEnvironment {
  param([string]$SelectedMode)

  $env:DEFAULT_BROWSER_EXECUTION_BACKEND = "external_browser_agent"
  $env:DEFAULT_DESKTOP_EXECUTION_BACKEND = "external_desktop_agent"
  $env:EXTERNAL_AGENT_FALLBACK_TO_INTERNAL = "true"

  if ($SelectedMode -eq "ollama") {
    $env:MODEL_API_ENABLED = "true"
    $env:MODEL_PROVIDER = "ollama"
    $env:OLLAMA_BASE_URL = "http://127.0.0.1:11434"
    $env:OLLAMA_MODEL = "qwen2.5:14b"
    $env:OLLAMA_PLANNER_MODEL = "qwen2.5:7b"
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
    $env:MODEL_API_TIMEOUT_S = "120"
    $env:PLAYWRIGHT_HEADLESS = "false"
    $env:PLAYWRIGHT_USE_CDP = "true"
    $env:PLAYWRIGHT_CDP_URL = "http://127.0.0.1:9222"
    $env:ITERATIVE_BROWSER_LOOP_ENABLED = "true"
    $env:ITERATIVE_BROWSER_MAX_STEPS = "12"
  }

  $env:AUDIO_TRANSCRIPTION_MODEL = "medium"
  $env:AUDIO_TRANSCRIPTION_DEVICE = "cpu"
  $env:AUDIO_TRANSCRIPTION_COMPUTE_TYPE = "int8"
  $env:AUDIO_TRANSCRIPTION_BEAM_SIZE = "8"
  $env:AUDIO_TRANSCRIPTION_VAD_FILTER = "true"
}

Stop-OrchestratorProcesses -TargetPort $Port
Set-OrchestratorEnvironment -SelectedMode $Mode

$pythonExe = (Resolve-Path .\.venv\Scripts\python.exe).Path
$uvicornArgs = @("-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "$Port", "--app-dir", "orchestrator")
if ($Mode -eq "dev") {
  $uvicornArgs += "--reload"
}

if ($RunForeground) {
  Write-Host "Starting orchestrator in foreground mode on http://127.0.0.1:$Port ..."
  & $pythonExe @uvicornArgs
  exit $LASTEXITCODE
}

$startProcessArgs = @{
  FilePath = $pythonExe
  ArgumentList = $uvicornArgs
  WorkingDirectory = (Get-Location).Path
  PassThru = $true
}

if ($Hidden) {
  $startProcessArgs["WindowStyle"] = "Hidden"
}

$process = Start-Process @startProcessArgs
Write-Host "Started orchestrator PID $($process.Id) using mode '$Mode'."

if (Wait-ForHealth -TargetPort $Port -TimeoutSec $StartupTimeoutSec) {
  Write-Host "Orchestrator is healthy on http://127.0.0.1:$Port/health"
  exit 0
}

Write-Warning "Orchestrator did not become healthy within ${StartupTimeoutSec}s."
exit 1
