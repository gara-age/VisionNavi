param(
  [switch]$Background
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $projectRoot

$runner = Join-Path $scriptDir "train_wakeword_model.ps1"
if (-not (Test-Path $runner)) {
  Write-Error "Missing runner script: $runner"
  exit 1
}

$wakewordRoot = "D:\VisionNaviWakeword"
$logDir = Join-Path $wakewordRoot "logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$config = "runtime/wakewords/configs/ko_hey_nabi.yaml"
$queueLogPath = Join-Path $logDir "wakeword_training_ko_hey_nabi_prod.log"
$queueErrPath = Join-Path $logDir "wakeword_training_ko_hey_nabi_prod.error.log"

if ($Background) {
  Start-Process powershell.exe -ArgumentList @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $PSCommandPath
  ) `
    -WorkingDirectory $projectRoot `
    -RedirectStandardOutput $queueLogPath `
    -RedirectStandardError $queueErrPath `
    -WindowStyle Hidden | Out-Null

  Write-Host "Started ko_hey_nabi production wakeword training."
  Write-Host " - stdout: $queueLogPath"
  Write-Host " - stderr: $queueErrPath"
  Write-Host " - config: $config"
  exit 0
}

Write-Host ""
Write-Host "=============================="
Write-Host "Training config: $config"
Write-Host "=============================="
& $runner -ConfigPath $config
if ($LASTEXITCODE -ne 0) {
  Write-Error "Training failed for $config"
  exit $LASTEXITCODE
}

Write-Host ""
Write-Host "ko_hey_nabi production wakeword training completed."

