param(
  [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $projectRoot

. "$scriptDir\resolve_wakeword_python.ps1"

$venvRoot = Resolve-WakewordVenvRoot -ProjectRoot $projectRoot
if (-not $venvRoot) {
  $venvRoot = "D:\VisionNaviRuntime\wakeword-venv"
}

$pythonExe = Join-Path $venvRoot "Scripts\python.exe"

function Resolve-BootstrapPython {
  $candidates = @(
    "C:\Python311\python.exe",
    "C:\Users\USER\AppData\Local\Programs\Python\Python311\python.exe",
    "C:\Users\USER\AppData\Local\Python\bin\python.exe",
    "C:\anaconda\python.exe"
  )

  foreach ($candidate in $candidates) {
    if (-not (Test-Path $candidate)) {
      continue
    }

    try {
      $prefix = & $candidate -c "import sys; print(sys.base_prefix)"
      if ($LASTEXITCODE -eq 0 -and $prefix) {
        return $candidate
      }
    } catch {
      continue
    }
  }

  return $null
}

$bootstrapPython = Resolve-BootstrapPython
if (-not $bootstrapPython) {
  Write-Error "No healthy Python 3.11 bootstrap interpreter was found."
  exit 1
}

if ($Force -or -not (Test-Path $pythonExe)) {
  Write-Host "Creating wakeword venv at $venvRoot using $bootstrapPython"
  & $bootstrapPython -m venv $venvRoot
  if ($LASTEXITCODE -ne 0) {
    throw "wakeword venv creation failed"
  }
}

Write-Host "Upgrading pip in wakeword env..."
& $pythonExe -m pip install --upgrade pip setuptools wheel
if ($LASTEXITCODE -ne 0) {
  throw "pip upgrade failed"
}

Write-Host "Installing wakeword training dependencies..."
& $pythonExe -m pip install --upgrade "livekit-wakeword[train,export,voxcpm]"
if ($LASTEXITCODE -ne 0) {
  throw "wakeword dependency install failed"
}

Write-Host "Pinning VoxCPM-compatible transformer dependencies..."
& $pythonExe -m pip install --upgrade "transformers>=4.40,<4.46" "tokenizers>=0.19,<0.21"
if ($LASTEXITCODE -ne 0) {
  throw "wakeword transformer dependency install failed"
}

Write-Host "Wakeword environment is ready: $pythonExe"
