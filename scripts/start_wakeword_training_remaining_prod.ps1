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

$configs = @(
  "runtime/wakewords/configs/ko_hey_nabi.yaml",
  "runtime/wakewords/configs/ja_nee_navi.yaml",
  "runtime/wakewords/configs/ja_navisan.yaml"
)

function Start-BackgroundSerialQueue {
  param([string[]]$ConfigPaths)

  $queueLogPath = Join-Path $logDir "wakeword_training_prod_remaining.log"
  $queueErrPath = Join-Path $logDir "wakeword_training_prod_remaining.error.log"

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

  Write-Host "Started remaining production wakeword training queue."
  Write-Host " - stdout: $queueLogPath"
  Write-Host " - stderr: $queueErrPath"
  Write-Host "Queue order:"
  foreach ($config in $ConfigPaths) {
    Write-Host " - $config"
  }
}

if ($Background) {
  Start-BackgroundSerialQueue -ConfigPaths $configs
  exit 0
}

foreach ($config in $configs) {
  Write-Host ""
  Write-Host "=============================="
  Write-Host "Training config: $config"
  Write-Host "=============================="
  & $runner -ConfigPath $config
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "Training failed for $config"
    continue
  }
}

Write-Host ""
Write-Host "Remaining wakeword training pipelines completed."
