param(
  [ValidateSet("ollama", "dev")]
  [string]$Mode = "ollama",
  [int]$Port = 8010,
  [switch]$SkipPubGet
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..")
$frontendDir = Join-Path $projectRoot "frontend"
$restartScript = Join-Path $scriptDir "restart_orchestrator.ps1"

if (-not (Test-Path $restartScript)) {
  Write-Error "Missing restart script: $restartScript"
  exit 1
}

if (-not (Test-Path $frontendDir)) {
  Write-Error "Missing frontend directory: $frontendDir"
  exit 1
}

Write-Host "== VisionNavi orchestrator restart =="
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $restartScript -Mode $Mode -Port $Port
if ($LASTEXITCODE -ne 0) {
  Write-Error "Failed to restart orchestrator."
  exit $LASTEXITCODE
}

Set-Location $frontendDir

if (-not $SkipPubGet) {
  Write-Host ""
  Write-Host "== Flutter pub get =="
  & flutter pub get
  if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter pub get failed."
    exit $LASTEXITCODE
  }
}

Write-Host ""
Write-Host "== Flutter build windows =="
& flutter build windows
if ($LASTEXITCODE -ne 0) {
  Write-Error "flutter build windows failed."
  exit $LASTEXITCODE
}

Write-Host ""
Write-Host "VisionNavi orchestrator restart and Windows build completed successfully."
exit 0
