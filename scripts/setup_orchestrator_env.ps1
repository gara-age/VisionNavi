Set-Location $PSScriptRoot\..

. "$PSScriptRoot\resolve_orchestrator_python.ps1"
$projectRoot = (Get-Location).Path
$preferredVenvRoot = if ($env:VISIONNAVI_ORCHESTRATOR_VENV -and $env:VISIONNAVI_ORCHESTRATOR_VENV.Trim()) {
  $env:VISIONNAVI_ORCHESTRATOR_VENV.Trim()
} else {
  "D:\VisionNaviRuntime\orchestrator-venv"
}

$venvRoot = $preferredVenvRoot

if (-not (Test-Path $venvRoot)) {
  python -m venv $venvRoot
  if ($LASTEXITCODE -ne 0) { throw "venv creation failed" }
}

& "$venvRoot\Scripts\python.exe" -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed" }

& "$venvRoot\Scripts\python.exe" -m pip install -r orchestrator\requirements.txt
if ($LASTEXITCODE -ne 0) { throw "requirements install failed" }

& "$venvRoot\Scripts\python.exe" -m playwright install chromium
if ($LASTEXITCODE -ne 0) { throw "playwright install failed" }

Write-Host "VisionNavi orchestrator environment is ready."
