param(
  [string[]]$Configs = @(
    "runtime/wakewords/configs/ko_hey_nabi.yaml",
    "runtime/wakewords/configs/ja_nee_navi.yaml",
    "runtime/wakewords/configs/ja_navisan.yaml"
  )
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $projectRoot

. "$scriptDir\resolve_wakeword_python.ps1"

$pythonExe = Resolve-WakewordPython -ProjectRoot $projectRoot
if (-not $pythonExe -or -not (Test-Path $pythonExe)) {
  Write-Error "Wakeword Python environment is missing. Run scripts/setup_wakeword_env.ps1 first."
  exit 1
}

$wakewordRoot = "D:\VisionNaviWakeword"
$requiredDirs = @(
  "$wakewordRoot\data",
  "$wakewordRoot\data\backgrounds",
  "$wakewordRoot\data\rirs",
  "$wakewordRoot\data\voxcpm",
  "$wakewordRoot\output",
  "$wakewordRoot\logs"
)

foreach ($dir in $requiredDirs) {
  if (-not (Test-Path $dir)) {
    Write-Error "Missing required wakeword directory: $dir"
    exit 1
  }
}

$backgroundCount = @(Get-ChildItem "$wakewordRoot\data\backgrounds" -File -Recurse -ErrorAction SilentlyContinue).Count
$rirCount = @(Get-ChildItem "$wakewordRoot\data\rirs" -File -Recurse -ErrorAction SilentlyContinue).Count
$voxcpmCount = @(Get-ChildItem "$wakewordRoot\data\voxcpm" -File -Recurse -ErrorAction SilentlyContinue).Count

if ($backgroundCount -lt 1) {
  Write-Error "No background audio files were found under $wakewordRoot\data\backgrounds"
  exit 1
}
if ($rirCount -lt 1) {
  Write-Error "No RIR files were found under $wakewordRoot\data\rirs"
  exit 1
}
if ($voxcpmCount -lt 1) {
  Write-Error "No VoxCPM files were found under $wakewordRoot\data\voxcpm"
  exit 1
}

$configArgs = ($Configs | ForEach-Object { (Resolve-Path $_).Path })
$configJson = $configArgs | ConvertTo-Json -Compress

$pythonCode = @"
import importlib.util
import json
import pathlib
import sys

import yaml

required_modules = [
    "torch",
    "numpy",
    "soundfile",
    "pronouncing",
    "audiomentations",
    "livekit.wakeword",
    "onnx",
    "onnxruntime",
    "yaml",
]
missing = [name for name in required_modules if importlib.util.find_spec(name) is None]
if missing:
    print("Missing Python modules: " + ", ".join(missing), file=sys.stderr)
    sys.exit(2)

from livekit.wakeword.cli import app  # noqa: F401
import voxcpm  # noqa: F401
from transformers import LlamaTokenizerFast  # noqa: F401

configs = json.loads(r'''$configJson''')
required_keys = ["model_name", "target_phrases", "tts_backend", "n_samples", "data_dir", "output_dir", "model", "augmentation", "steps"]
for config_path in configs:
    path = pathlib.Path(config_path)
    if not path.exists():
        print(f"Missing config: {path}", file=sys.stderr)
        sys.exit(3)
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    missing_keys = [key for key in required_keys if key not in data]
    if missing_keys:
        print(f"{path}: missing keys: {missing_keys}", file=sys.stderr)
        sys.exit(4)
    if int(data["n_samples"]) < 5000:
        print(f"{path}: n_samples should be at least 5000 for production retraining", file=sys.stderr)
        sys.exit(5)
    if int(data["steps"]) < 30000:
        print(f"{path}: steps should be at least 30000 for production retraining", file=sys.stderr)
        sys.exit(6)
    for dir_key in ["data_dir", "output_dir"]:
        if not pathlib.Path(str(data[dir_key])).exists():
            print(f"{path}: {dir_key} not found: {data[dir_key]}", file=sys.stderr)
            sys.exit(7)
print("Wakeword training preflight OK")
"@

Write-Host "== VisionNavi wakeword training preflight =="
Write-Host "Python: $pythonExe"
Write-Host "Background files: $backgroundCount"
Write-Host "RIR files       : $rirCount"
Write-Host "VoxCPM files    : $voxcpmCount"
Write-Host "Configs:"
$configArgs | ForEach-Object { Write-Host " - $_" }

$env:PYTHONUTF8 = "1"
$tempScript = Join-Path $env:TEMP "visionnavi_wakeword_preflight.py"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tempScript, $pythonCode, $utf8NoBom)
try {
  & $pythonExe $tempScript
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
} finally {
  Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
}

Write-Host "Preflight completed successfully."
