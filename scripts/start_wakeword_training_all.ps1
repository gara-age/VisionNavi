param(
  [switch]$Background,
  [ValidateSet("balanced", "full")]
  [string]$Preset = "balanced"
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
$tempRoot = Join-Path $wakewordRoot "temp"
New-Item -ItemType Directory -Path $logDir,$tempRoot -Force | Out-Null

$configSuffix = if ($Preset -eq "full") { "" } else { "_balanced" }
$configs = @(
  "runtime/wakewords/configs/ko_nabiya${configSuffix}.yaml",
  "runtime/wakewords/configs/ja_nee_navi${configSuffix}.yaml",
  "runtime/wakewords/configs/ko_hey_nabi${configSuffix}.yaml",
  "runtime/wakewords/configs/ja_navisan${configSuffix}.yaml"
)

function Start-BackgroundSerialQueue {
  param([string[]]$ConfigPaths)

  $queueBase = if ($Preset -eq "balanced") { "wakeword_training_dev_queue" } else { "wakeword_training_prod_queue" }
  $queueLogPath = Join-Path $logDir "$queueBase.log"
  $queueErrPath = Join-Path $logDir "$queueBase.error.log"

  Start-Process powershell.exe -ArgumentList @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $PSCommandPath,
    "-Preset",
    $Preset
  ) `
    -WorkingDirectory $projectRoot `
    -RedirectStandardOutput $queueLogPath `
    -RedirectStandardError $queueErrPath `
    -WindowStyle Hidden | Out-Null

  $queueLabel = if ($Preset -eq "balanced") { "development" } else { "production" }
  Write-Host "Started $queueLabel wakeword training queue."
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
    Write-Error "Training failed for $config"
    exit $LASTEXITCODE
  }
}

Write-Host ""
Write-Host "All wakeword training pipelines completed."
