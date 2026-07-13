param(
  [int]$RefreshSeconds = 10,
  [int]$Tail = 12,
  [switch]$Once
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $projectRoot

$wakewordRoot = "D:\VisionNaviWakeword"
$outputRoot = Join-Path $wakewordRoot "output"
$logRoot = Join-Path $wakewordRoot "logs"
$queueStdoutLog = Join-Path $logRoot "wakeword_retrain_stable_prod.log"
$queueStderrLog = Join-Path $logRoot "wakeword_retrain_stable_prod.error.log"
$ids = @("ko_hey_nabi", "ja_nee_navi", "ja_navisan")

function Get-ProcessesForText {
  param([string]$Text)
  return @(Get-CimInstance Win32_Process |
      Where-Object { $_.CommandLine -and $_.CommandLine -like "*$Text*" } |
      Select-Object ProcessId, Name, CommandLine)
}

function Get-LatestLogLine {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return "(log missing)" }
  $line = Get-Content $Path -Tail 1 -ErrorAction SilentlyContinue
  if ($null -eq $line -or [string]::IsNullOrWhiteSpace($line)) { return "(no log line yet)" }
  return $line.Trim()
}

function Get-OutputSummary {
  param([string]$Id)
  $dir = Join-Path $outputRoot $Id
  if (-not (Test-Path $dir)) {
    return [pscustomobject]@{ Exists = $false; FileCount = 0; LatestWrite = $null; Metrics = $null; RuntimeReady = $false }
  }
  $files = @(Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue)
  $latest = if ($files.Count -gt 0) { ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime } else { (Get-Item $dir).LastWriteTime }
  $metricsPath = Join-Path $dir "$Id`_metrics.json"
  $metrics = $null
  if (Test-Path $metricsPath) {
    try {
      $rows = @(Get-Content $metricsPath -Raw -Encoding UTF8 | ConvertFrom-Json)
      $optimalRows = @($rows | Where-Object { $_.note -eq "optimal_threshold" })
      $metrics = if ($optimalRows.Count -gt 0) {
        $optimalRows[$optimalRows.Count - 1]
      } elseif ($rows.Count -gt 0) {
        $rows[$rows.Count - 1]
      } else {
        $null
      }
    } catch {
      $metrics = $null
    }
  }
  $runtimeReady = Test-Path (Join-Path $projectRoot "runtime\wakewords\models\$Id.onnx")
  return [pscustomobject]@{ Exists = $true; FileCount = $files.Count; LatestWrite = $latest; Metrics = $metrics; RuntimeReady = $runtimeReady }
}

function Get-ScalarMetric {
  param(
    [object]$Value,
    [double]$Default = 0.0
  )
  if ($null -eq $Value) {
    return $Default
  }
  if ($Value -is [System.Array]) {
    if ($Value.Count -lt 1) {
      return $Default
    }
    return [double]$Value[$Value.Count - 1]
  }
  return [double]$Value
}

function Write-Monitor {
  $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $queueProcesses = Get-ProcessesForText -Text "start_wakeword_retrain_stable_prod.ps1"
  $trainingProcesses = @()
  foreach ($id in $ids) {
    $trainingProcesses += Get-ProcessesForText -Text "runtime\wakewords\configs\$id.yaml"
  }

  Write-Host "VisionNavi Stable Wakeword Retraining Monitor  $now" -ForegroundColor White
  Write-Host "Output root: $outputRoot"
  Write-Host "Log root   : $logRoot"
  Write-Host ("-" * 88)

  if ($queueProcesses.Count -gt 0) {
    Write-Host "Queue      : RUNNING ($($queueProcesses.ProcessId -join ', '))" -ForegroundColor Green
  } else {
    Write-Host "Queue      : not running" -ForegroundColor Yellow
  }
  if ($trainingProcesses.Count -gt 0) {
    Write-Host "Training   : RUNNING ($($trainingProcesses.ProcessId -join ', '))" -ForegroundColor Green
  } else {
    Write-Host "Training   : not running" -ForegroundColor Yellow
  }
  Write-Host "Stdout     : $(Get-LatestLogLine -Path $queueStdoutLog)"
  Write-Host "Stderr     : $(Get-LatestLogLine -Path $queueStderrLog)"
  Write-Host ("-" * 88)

  foreach ($id in $ids) {
    $summary = Get-OutputSummary -Id $id
    $status = if ($summary.RuntimeReady) { "runtime ready" } else { "runtime missing" }
    $metricText = "(metrics missing)"
    if ($summary.Metrics) {
      $recall = Get-ScalarMetric -Value $summary.Metrics.recall
      $fpph = Get-ScalarMetric -Value $summary.Metrics.fpph
      $threshold = Get-ScalarMetric -Value $summary.Metrics.threshold
      $note = if ($summary.Metrics.note -is [System.Array]) { $summary.Metrics.note[$summary.Metrics.note.Count - 1] } else { $summary.Metrics.note }
      $metricText = "recall=$([math]::Round($recall, 4)) fpph=$([math]::Round($fpph, 4)) threshold=$threshold note=$note"
    }
    Write-Host ("{0,-14} files={1,-6} latest={2,-22} {3,-15} {4}" -f $id, $summary.FileCount, $summary.LatestWrite, $status, $metricText)
  }

  Write-Host ""
  Write-Host "[Stdout Tail]" -ForegroundColor White
  if (Test-Path $queueStdoutLog) {
    Get-Content $queueStdoutLog -Tail $Tail -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $_" }
  } else {
    Write-Host "  (no stdout yet)"
  }

  Write-Host ""
  Write-Host "[Stderr Tail]" -ForegroundColor White
  if (Test-Path $queueStderrLog) {
    Get-Content $queueStderrLog -Tail $Tail -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
  } else {
    Write-Host "  (no stderr yet)"
  }
}

do {
  Clear-Host
  Write-Monitor
  if ($Once) { break }
  Start-Sleep -Seconds $RefreshSeconds
} while ($true)
