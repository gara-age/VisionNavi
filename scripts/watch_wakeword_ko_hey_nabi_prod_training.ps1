param(
  [int]$RefreshSeconds = 5,
  [int]$Tail = 14,
  [switch]$Once
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $projectRoot

$id = "ko_hey_nabi"
$label = ([string]([char]0xD5E4) + [char]0xC774 + " " + [char]0xB098 + [char]0xBE44)
$configPattern = "ko_hey_nabi.yaml"
$outputRoot = "D:\VisionNaviWakeword\output"
$logRoot = "D:\VisionNaviWakeword\logs"
$outputDir = Join-Path $outputRoot $id
$runtimeModelPath = Join-Path $projectRoot "runtime\wakewords\models\ko_hey_nabi.onnx"
$runtimeManifestPath = Join-Path $projectRoot "runtime\wakewords\manifest.json"
$queueStdoutLog = Join-Path $logRoot "wakeword_training_ko_hey_nabi_prod.log"
$queueStderrLog = Join-Path $logRoot "wakeword_training_ko_hey_nabi_prod.error.log"

function Get-TrainingProcesses {
  return @(Get-CimInstance Win32_Process |
      Where-Object {
        $_.Name -eq "python.exe" -and
        $_.CommandLine -and
        $_.CommandLine -like "*runtime\wakewords\configs\$configPattern*"
      } |
      Select-Object ProcessId, Name, CommandLine)
}

function Get-QueueProcesses {
  return @(Get-CimInstance Win32_Process |
      Where-Object {
        $_.CommandLine -and
        $_.CommandLine -like "*start_wakeword_training_ko_hey_nabi_prod.ps1*"
      } |
      Select-Object ProcessId, Name, CommandLine)
}

function Get-LatestLogLine {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return "(log missing)"
  }

  $line = Get-Content $Path -Tail 1 -ErrorAction SilentlyContinue
  if ($null -eq $line -or [string]::IsNullOrWhiteSpace($line)) {
    return "(no log line yet)"
  }

  return $line.Trim()
}

function Get-OutputSummary {
  param([string]$DirectoryPath)

  if (-not (Test-Path $DirectoryPath)) {
    return [pscustomobject]@{
      Exists = $false
      FileCount = 0
      LatestWrite = $null
    }
  }

  $files = @(Get-ChildItem $DirectoryPath -Recurse -File -ErrorAction SilentlyContinue)
  $latest = if ($files.Count -gt 0) {
    ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
  } else {
    (Get-Item $DirectoryPath).LastWriteTime
  }

  return [pscustomobject]@{
    Exists = $true
    FileCount = $files.Count
    LatestWrite = $latest
  }
}

function Get-ManifestModelPath {
  if (-not (Test-Path $runtimeManifestPath)) {
    return "(manifest missing)"
  }

  $manifest = Get-Content $runtimeManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $profile = $manifest.profiles | Where-Object { $_.id -eq $id } | Select-Object -First 1
  if (-not $profile) {
    return "(profile missing)"
  }

  return $profile.model_path
}

function Write-Monitor {
  $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $trainingProcesses = Get-TrainingProcesses
  $queueProcesses = Get-QueueProcesses
  $outputSummary = Get-OutputSummary -DirectoryPath $outputDir
  $runtimeReady = Test-Path $runtimeModelPath
  $manifestPath = Get-ManifestModelPath

  Write-Host "VisionNavi ko_hey_nabi Prod Wakeword Monitor  $now" -ForegroundColor White
  Write-Host "Wakeword   : $id / $label"
  Write-Host "Output root: $outputRoot"
  Write-Host "Log root   : $logRoot"
  Write-Host ("-" * 72)

  if ($queueProcesses.Count -gt 0) {
    $queuePids = ($queueProcesses | Select-Object -ExpandProperty ProcessId) -join ", "
    Write-Host "Queue      : RUNNING ($queuePids)" -ForegroundColor Green
  } else {
    Write-Host "Queue      : not running" -ForegroundColor Yellow
  }

  if ($trainingProcesses.Count -gt 0) {
    $pids = ($trainingProcesses | Select-Object -ExpandProperty ProcessId) -join ", "
    Write-Host "Training   : RUNNING ($pids)" -ForegroundColor Green
  } else {
    Write-Host "Training   : not running" -ForegroundColor Yellow
  }

  if ($outputSummary.Exists) {
    Write-Host "Output     : $($outputSummary.FileCount) files / latest $($outputSummary.LatestWrite)"
  } else {
    Write-Host "Output     : missing" -ForegroundColor Yellow
  }

  if ($runtimeReady) {
    $runtimeFile = Get-Item $runtimeModelPath
    Write-Host "Runtime    : READY ($([math]::Round($runtimeFile.Length / 1KB, 1)) KB, $($runtimeFile.LastWriteTime))" -ForegroundColor Green
  } else {
    Write-Host "Runtime    : missing runtime/wakewords/models/ko_hey_nabi.onnx" -ForegroundColor Yellow
  }

  Write-Host "Manifest   : $manifestPath"
  Write-Host "Stdout     : $(Get-LatestLogLine -Path $queueStdoutLog)"
  Write-Host "Stderr     : $(Get-LatestLogLine -Path $queueStderrLog)"
  Write-Host ("-" * 72)

  $stdoutTail = if (Test-Path $queueStdoutLog) { @(Get-Content $queueStdoutLog -Tail $Tail -ErrorAction SilentlyContinue) } else { @() }
  $stderrTail = if (Test-Path $queueStderrLog) { @(Get-Content $queueStderrLog -Tail $Tail -ErrorAction SilentlyContinue) } else { @() }

  Write-Host ""
  Write-Host "[Stdout Tail]" -ForegroundColor White
  if ($stdoutTail.Count -gt 0) {
    $stdoutTail | ForEach-Object { Write-Host "  $_" }
  } else {
    Write-Host "  (no stdout yet)"
  }

  Write-Host ""
  Write-Host "[Stderr Tail]" -ForegroundColor White
  if ($stderrTail.Count -gt 0) {
    $stderrTail | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
  } else {
    Write-Host "  (no stderr yet)"
  }
}

do {
  Clear-Host
  Write-Monitor

  if ($Once) {
    break
  }

  Start-Sleep -Seconds $RefreshSeconds
} while ($true)
