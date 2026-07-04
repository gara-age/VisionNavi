param(
  [switch]$Background
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

& (Join-Path $scriptDir "start_wakeword_training_all.ps1") -Preset full -Background:$Background
exit $LASTEXITCODE
