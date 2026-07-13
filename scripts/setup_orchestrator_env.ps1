Set-Location $PSScriptRoot\..

. "$PSScriptRoot\resolve_orchestrator_python.ps1"
$projectRoot = (Get-Location).Path
$preferredVenvRoot = if ($env:VISIONNAVI_ORCHESTRATOR_VENV -and $env:VISIONNAVI_ORCHESTRATOR_VENV.Trim()) {
  $env:VISIONNAVI_ORCHESTRATOR_VENV.Trim()
} else {
  "D:\VisionNaviRuntime\orchestrator-venv-new"
}

$venvRoot = $preferredVenvRoot

function Resolve-BootstrapPython {
  $candidates = @(
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
  Write-Error "No healthy bootstrap Python interpreter found."
  exit 1
}

if (-not (Test-Path $venvRoot)) {
  & $bootstrapPython -m venv $venvRoot
  if ($LASTEXITCODE -ne 0) { throw "venv creation failed" }
}

& "$venvRoot\Scripts\python.exe" -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed" }

& "$venvRoot\Scripts\python.exe" -m pip install -r orchestrator\requirements.txt
if ($LASTEXITCODE -ne 0) { throw "requirements install failed" }

& "$venvRoot\Scripts\python.exe" -m playwright install chromium
if ($LASTEXITCODE -ne 0) { throw "playwright install failed" }

Write-Host "VisionNavi orchestrator environment is ready."
