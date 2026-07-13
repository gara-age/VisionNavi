param(
  [Parameter(Mandatory = $true)]
  [string]$ConfigPath,
  [switch]$SkipGenerate,
  [switch]$SkipAugment,
  [switch]$SkipTrain,
  [switch]$SkipExport
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $projectRoot

. "$scriptDir\resolve_wakeword_python.ps1"
$venvRoot = Resolve-WakewordVenvRoot -ProjectRoot $projectRoot
$pythonExe = if ($venvRoot) { Join-Path $venvRoot "Scripts\python.exe" } else { $null }
$cliBootstrap = "from livekit.wakeword.cli import app; app()"
$wakewordRoot = "D:\VisionNaviWakeword"
$tempRoot = Join-Path $wakewordRoot "temp"
$pipCacheRoot = Join-Path $wakewordRoot "pip-cache"

if (-not (Test-Path $pythonExe)) {
  Write-Host "Wakeword environment is missing. Bootstrapping it now..."
  & "$scriptDir\setup_wakeword_env.ps1"
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
  $venvRoot = Resolve-WakewordVenvRoot -ProjectRoot $projectRoot
  $pythonExe = if ($venvRoot) { Join-Path $venvRoot "Scripts\python.exe" } else { $null }
  if (-not (Test-Path $pythonExe)) {
    Write-Error "Missing wakeword training environment even after bootstrap."
    exit 1
  }
}

$resolvedConfig = Resolve-Path $ConfigPath
$env:PYTHONUTF8 = "1"
$env:TEMP = $tempRoot
$env:TMP = $tempRoot
$env:PIP_CACHE_DIR = $pipCacheRoot
$env:VISIONNAVI_SAFETENSORS_BACKEND = "pread"
New-Item -ItemType Directory -Path $tempRoot,$pipCacheRoot -Force | Out-Null

$configText = Get-Content $resolvedConfig -Raw -Encoding UTF8
$modelNameMatch = [regex]::Match($configText, '(?m)^model_name:\s*([A-Za-z0-9_\-]+)\s*$')
if (-not $modelNameMatch.Success) {
  Write-Error "Could not read model_name from config: $resolvedConfig"
  exit 1
}

$modelName = $modelNameMatch.Groups[1].Value.Trim()
$outputDirMatch = [regex]::Match($configText, '(?m)^output_dir:\s*"?([^\r\n"]+)"?\s*$')
if (-not $outputDirMatch.Success) {
  Write-Error "Could not read output_dir from config: $resolvedConfig"
  exit 1
}

$outputRoot = $outputDirMatch.Groups[1].Value.Trim()
$runtimeModelDir = Join-Path $projectRoot "runtime/wakewords/models"
$runtimeManifestPath = Join-Path $projectRoot "runtime/wakewords/manifest.json"
New-Item -ItemType Directory -Path $runtimeModelDir -Force | Out-Null

function Update-WakewordManifestProfileModelPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,
    [Parameter(Mandatory = $true)]
    [string]$ProfileId,
    [Parameter(Mandatory = $true)]
    [string]$ModelPath
  )

  if (-not (Test-Path $ManifestPath)) {
    Write-Warning "Wakeword manifest not found: $ManifestPath"
    return
  }

  $manifest = Get-Content $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if (-not $manifest.profiles) {
    Write-Warning "Wakeword manifest has no profiles: $ManifestPath"
    return
  }

  $profile = $manifest.profiles | Where-Object { $_.id -eq $ProfileId } | Select-Object -First 1
  if (-not $profile) {
    Write-Warning "Wakeword profile '$ProfileId' was not found in manifest."
    return
  }

  $profile.model_path = $ModelPath.Replace('\', '/')
  $manifestJson = $manifest | ConvertTo-Json -Depth 8
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($ManifestPath, $manifestJson, $utf8NoBom)

  Write-Host ""
  Write-Host "== Wakeword manifest synced =="
  Write-Host "$ProfileId -> $($profile.model_path)"
}

if ($modelName -like "ja_*" -or $modelName -eq "ko_hey_nabi") {
  $env:VISIONNAVI_VOXCPM_DEVICE = "cpu"
  $env:VISIONNAVI_VOXCPM_OPTIMIZE = "false"
  Write-Host "Using VoxCPM CPU / no-optimize mode for stable wakeword generation."
} else {
  Remove-Item Env:VISIONNAVI_VOXCPM_DEVICE -ErrorAction SilentlyContinue
  Remove-Item Env:VISIONNAVI_VOXCPM_OPTIMIZE -ErrorAction SilentlyContinue
}

Write-Host "== Wakeword config =="
Write-Host $resolvedConfig

if (-not $SkipGenerate) {
  Write-Host ""
  Write-Host "== Generate =="
  & $pythonExe -c $cliBootstrap generate $resolvedConfig
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not $SkipAugment) {
  Write-Host ""
  Write-Host "== Augment =="
  & $pythonExe -c $cliBootstrap augment $resolvedConfig
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not $SkipTrain) {
  Write-Host ""
  Write-Host "== Train =="
  & $pythonExe -c $cliBootstrap train $resolvedConfig
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not $SkipExport) {
  Write-Host ""
  Write-Host "== Export =="
  & $pythonExe -c $cliBootstrap export $resolvedConfig
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$exportedOnnxPath = Join-Path $outputRoot "$modelName\$modelName.onnx"
$runtimeOnnxPath = Join-Path $runtimeModelDir "$modelName.onnx"
if (Test-Path $exportedOnnxPath) {
  Copy-Item $exportedOnnxPath $runtimeOnnxPath -Force
  Write-Host ""
  Write-Host "== Runtime model synced =="
  Write-Host $runtimeOnnxPath
  $relativeRuntimeModelPath = "runtime/wakewords/models/$modelName.onnx"
  Update-WakewordManifestProfileModelPath `
    -ManifestPath $runtimeManifestPath `
    -ProfileId $modelName `
    -ModelPath $relativeRuntimeModelPath
}

Write-Host ""
Write-Host "Wakeword training pipeline completed."
