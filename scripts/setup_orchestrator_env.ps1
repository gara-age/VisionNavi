Set-Location $PSScriptRoot\..

if (-not (Test-Path .\.venv)) {
  python -m venv .venv
  if ($LASTEXITCODE -ne 0) { throw "venv creation failed" }
}

.\.venv\Scripts\python -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed" }

.\.venv\Scripts\python -m pip install -r orchestrator\requirements.txt
if ($LASTEXITCODE -ne 0) { throw "requirements install failed" }

.\.venv\Scripts\python -m playwright install chromium
if ($LASTEXITCODE -ne 0) { throw "playwright install failed" }

Write-Host "VisionNavi orchestrator environment is ready."
