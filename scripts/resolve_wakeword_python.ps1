function Resolve-WakewordVenvRoot {
  param(
    [string]$ProjectRoot
  )

  $candidates = @()

  if ($env:VISIONNAVI_WAKEWORD_VENV -and $env:VISIONNAVI_WAKEWORD_VENV.Trim()) {
    $candidates += $env:VISIONNAVI_WAKEWORD_VENV.Trim()
  }

  $candidates += @(
    "D:\VisionNaviRuntime\wakeword-venv",
    (Join-Path $ProjectRoot "runtime\.venv-wakeword")
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

function Resolve-WakewordPython {
  param(
    [string]$ProjectRoot
  )

  $venvRoot = Resolve-WakewordVenvRoot -ProjectRoot $ProjectRoot
  if (-not $venvRoot) {
    return $null
  }

  $pythonPath = Join-Path $venvRoot "Scripts\python.exe"
  if (Test-Path $pythonPath) {
    return (Resolve-Path $pythonPath).Path
  }

  return $null
}

