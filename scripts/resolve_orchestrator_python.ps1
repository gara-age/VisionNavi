function Resolve-OrchestratorVenvRoot {
  param(
    [string]$ProjectRoot
  )

  $candidates = @()

  if ($env:VISIONNAVI_ORCHESTRATOR_VENV -and $env:VISIONNAVI_ORCHESTRATOR_VENV.Trim()) {
    $candidates += $env:VISIONNAVI_ORCHESTRATOR_VENV.Trim()
  }

  $candidates += @(
    "D:\VisionNaviRuntime\orchestrator-venv-new",
    "D:\VisionNaviRuntime\orchestrator-venv",
    (Join-Path $ProjectRoot "orchestrator\.venv")
  )

  foreach ($candidate in $candidates) {
    if (-not $candidate) {
      continue
    }
    $pythonPath = Join-Path $candidate "Scripts\python.exe"
    if (Test-Path $pythonPath) {
      return (Resolve-Path $candidate).Path
    }
  }

  return $null
}

function Resolve-OrchestratorPython {
  param(
    [string]$ProjectRoot
  )

  $venvRoot = Resolve-OrchestratorVenvRoot -ProjectRoot $ProjectRoot
  if (-not $venvRoot) {
    return $null
  }

  $pythonPath = Join-Path $venvRoot "Scripts\python.exe"
  if (Test-Path $pythonPath) {
    return (Resolve-Path $pythonPath).Path
  }

  return $null
}
