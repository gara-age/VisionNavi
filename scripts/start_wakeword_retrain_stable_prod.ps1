param(
  [switch]$Background
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $projectRoot

$wakewordRoot = "D:\VisionNaviWakeword"
$logDir = Join-Path $wakewordRoot "logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$stdoutLog = Join-Path $logDir "wakeword_retrain_stable_prod.log"
$stderrLog = Join-Path $logDir "wakeword_retrain_stable_prod.error.log"

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
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog `
    -WindowStyle Hidden | Out-Null

  Write-Host "Started stable production wakeword retraining queue."
  Write-Host " - stdout: $stdoutLog"
  Write-Host " - stderr: $stderrLog"
  exit 0
}

$configs = @(
  "runtime/wakewords/configs/ko_hey_nabi.yaml",
  "runtime/wakewords/configs/ja_nee_navi.yaml",
  "runtime/wakewords/configs/ja_navisan.yaml"
)

Write-Host "== Preflight =="
& "$scriptDir\test_wakeword_training_preflight.ps1" -Configs $configs
if ($LASTEXITCODE -ne 0) {
  Write-Error "Preflight failed. Training was not started."
  exit $LASTEXITCODE
}

$runner = Join-Path $scriptDir "train_wakeword_model.ps1"
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
Write-Host "Stable production wakeword retraining queue completed."
