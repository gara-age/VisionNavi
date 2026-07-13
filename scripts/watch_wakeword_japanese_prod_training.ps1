param(
  [int]$RefreshSeconds = 5,
  [int]$Tail = 12,
  [switch]$Once
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $projectRoot

$outputRoot = "D:\VisionNaviWakeword\output"
$logRoot = "D:\VisionNaviWakeword\logs"

$entries = @(
  @{
    Id = "ja_nee_navi"
    Label = ([string]([char]0x306D) + [char]0x3048 + [char]0x3001 + [char]0x30CA + [char]0x30D3)
    ConfigPattern = "ja_nee_navi.yaml"
    OutputDir = "ja_nee_navi"
    PositiveDir = "positive_train"
  },
  @{
    Id = "ja_navisan"
    Label = ([string]([char]0x30CA) + [char]0x30D3 + [char]0x3055 + [char]0x3093)
    ConfigPattern = "ja_navisan.yaml"
    OutputDir = "ja_navisan"
    PositiveDir = "positive_train"
  }
)

$queueStdoutLog = Join-Path $logRoot "wakeword_training_japanese_prod.log"
$queueStderrLog = Join-Path $logRoot "wakeword_training_japanese_prod.error.log"

function Get-TrainingProcesses {
  param([string]$Pattern)

  return @(Get-CimInstance Win32_Process |
      Where-Object {
        $_.Name -eq "python.exe" -and
        $_.CommandLine -and
        $_.CommandLine -like "*runtime\wakewords\configs\$Pattern*"
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
  param([string]$DirectoryPath, [string]$PositiveSubdir)

  if (-not (Test-Path $DirectoryPath)) {
    return [pscustomobject]@{
      Exists = $false
      FileCount = 0
      PositiveCount = 0
      LatestWrite = $null
    }
  }

  $files = @(Get-ChildItem $DirectoryPath -Recurse -File -ErrorAction SilentlyContinue)
  $positiveDir = Join-Path $DirectoryPath $PositiveSubdir
  $positiveCount = if (Test-Path $positiveDir) {
    @(Get-ChildItem $positiveDir -File -ErrorAction SilentlyContinue).Count
  } else {
    0
  }

  $latest = if ($files.Count -gt 0) {
    ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
  } else {
    (Get-Item $DirectoryPath).LastWriteTime
  }

  return [pscustomobject]@{
    Exists = $true
    FileCount = $files.Count
    PositiveCount = $positiveCount
    LatestWrite = $latest
  }
}

function Get-QueueProcesses {
  return @(Get-CimInstance Win32_Process |
      Where-Object {
        $_.CommandLine -and
        $_.CommandLine -like "*start_wakeword_training_japanese_prod.ps1*"
      } |
      Select-Object ProcessId, Name, CommandLine)
}

function Get-ActiveEntry {
  foreach ($entry in $entries) {
    $processes = Get-TrainingProcesses -Pattern $entry.ConfigPattern
    if ($processes.Count -gt 0) {
      return $entry
    }
  }
  return $null
}

function Write-EntryBlock {
  param([hashtable]$Entry)

  $processes = Get-TrainingProcesses -Pattern $Entry.ConfigPattern
  $outputDir = Join-Path $outputRoot $Entry.OutputDir
  $outputSummary = Get-OutputSummary -DirectoryPath $outputDir -PositiveSubdir $Entry.PositiveDir

  Write-Host ""
  Write-Host "[$($Entry.Id)] $($Entry.Label)" -ForegroundColor Cyan

  if ($processes.Count -gt 0) {
    $pidList = ($processes | Select-Object -ExpandProperty ProcessId) -join ", "
    Write-Host "  Process       : RUNNING ($pidList)" -ForegroundColor Green
  } else {
    Write-Host "  Process       : not running" -ForegroundColor Yellow
  }

  if ($outputSummary.Exists) {
    $latestText = if ($outputSummary.LatestWrite) { $outputSummary.LatestWrite } else { "-" }
    Write-Host "  Output files  : $($outputSummary.FileCount)"
    Write-Host "  positive_train: $($outputSummary.PositiveCount)"
    Write-Host "  Latest write  : $latestText"
  } else {
    Write-Host "  Output        : missing"
  }
}

function Write-Header {
  $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $queueProcesses = Get-QueueProcesses
  $activeEntry = Get-ActiveEntry
  Write-Host "VisionNavi Wakeword Japanese Prod Monitor  $now" -ForegroundColor White
  Write-Host "Output root: $outputRoot"
  Write-Host "Log root   : $logRoot"
  if ($queueProcesses.Count -gt 0) {
    $queuePids = ($queueProcesses | Select-Object -ExpandProperty ProcessId) -join ", "
    Write-Host "Queue      : RUNNING ($queuePids)" -ForegroundColor Green
  } else {
    Write-Host "Queue      : not running" -ForegroundColor Yellow
  }
  if ($activeEntry) {
    Write-Host "Active     : $($activeEntry.Id) / $($activeEntry.Label)" -ForegroundColor Cyan
  } else {
    Write-Host "Active     : idle"
  }
  Write-Host "Queue stdout: $(Get-LatestLogLine -Path $queueStdoutLog)"
  Write-Host "Queue stderr: $(Get-LatestLogLine -Path $queueStderrLog)"
  Write-Host ("-" * 72)
}

do {
  Clear-Host
  Write-Header
  foreach ($entry in $entries) {
    Write-EntryBlock -Entry $entry
  }

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

  if (-not $Once) {
    Start-Sleep -Seconds $RefreshSeconds
  }
} while (-not $Once)
