param(
  [int]$RefreshSeconds = 5,
  [int]$Tail = 8,
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
    Id = "ko_nabiya"
    Label = ([string]([char]0xB098) + [char]0xBE44 + [char]0xC57C)
    ConfigPattern = "ko_nabiya.yaml"
    OutputDir = "ko_nabiya"
  },
  @{
    Id = "ja_nee_navi"
    Label = ([string]([char]0x306D) + [char]0x3048 + [char]0x3001 + [char]0x30CA + [char]0x30D3)
    ConfigPattern = "ja_nee_navi.yaml"
    OutputDir = "ja_nee_navi"
  },
  @{
    Id = "ko_hey_nabi"
    Label = ([string]([char]0xD5E4) + [char]0xC774 + " " + [char]0xB098 + [char]0xBE44)
    ConfigPattern = "ko_hey_nabi.yaml"
    OutputDir = "ko_hey_nabi"
  },
  @{
    Id = "ja_navisan"
    Label = ([string]([char]0x30CA) + [char]0x30D3 + [char]0x3055 + [char]0x3093)
    ConfigPattern = "ja_navisan.yaml"
    OutputDir = "ja_navisan"
  }
)

$queueStdoutLog = Join-Path $logRoot "wakeword_training_prod_queue.log"
$queueStderrLog = Join-Path $logRoot "wakeword_training_prod_queue.error.log"

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
  param([string]$DirectoryPath)

  if (-not (Test-Path $DirectoryPath)) {
    return [pscustomobject]@{
      Exists = $false
      FileCount = 0
      LatestWrite = $null
    }
  }

  $files = @(Get-ChildItem $DirectoryPath -Recurse -File -ErrorAction SilentlyContinue)
  $latest = $null
  if ($files.Count -gt 0) {
    $latest = ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
  } else {
    $latest = (Get-Item $DirectoryPath).LastWriteTime
  }

  return [pscustomobject]@{
    Exists = $true
    FileCount = $files.Count
    LatestWrite = $latest
  }
}

function Get-QueueState {
  $queueProcess = @(Get-CimInstance Win32_Process |
      Where-Object {
        $_.CommandLine -and
        $_.CommandLine -like "*start_wakeword_training_all.ps1*" -and
        $_.CommandLine -like "*-Preset full*"
      } |
      Select-Object ProcessId, Name, CommandLine)

  $activeEntry = $null
  foreach ($entry in $entries) {
    $processes = Get-TrainingProcesses -Pattern $entry.ConfigPattern
    if ($processes.Count -gt 0) {
      $activeEntry = $entry
      break
    }
  }

  return [pscustomobject]@{
    QueueProcesses = $queueProcess
    ActiveEntry = $activeEntry
  }
}

function Write-EntryBlock {
  param([hashtable]$Entry)

  $processes = Get-TrainingProcesses -Pattern $Entry.ConfigPattern
  $outputDir = Join-Path $outputRoot $Entry.OutputDir
  $outputSummary = Get-OutputSummary -DirectoryPath $outputDir

  Write-Host ""
  Write-Host "[$($Entry.Id)] $($Entry.Label)" -ForegroundColor Cyan

  if ($processes.Count -gt 0) {
    $pidList = ($processes | Select-Object -ExpandProperty ProcessId) -join ", "
    Write-Host "  Process   : RUNNING ($pidList)" -ForegroundColor Green
  } else {
    Write-Host "  Process   : not running" -ForegroundColor Yellow
  }

  if ($outputSummary.Exists) {
    $latestText = if ($outputSummary.LatestWrite) { $outputSummary.LatestWrite } else { "-" }
    Write-Host "  Output    : $($outputSummary.FileCount) files / latest $latestText"
  } else {
    Write-Host "  Output    : missing"
  }
}

function Write-Header {
  $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $queueState = Get-QueueState
  Write-Host "VisionNavi Wakeword Prod Monitor  $now" -ForegroundColor White
  Write-Host "Output root: $outputRoot"
  Write-Host "Log root   : $logRoot"
  if ($queueState.QueueProcesses.Count -gt 0) {
    $queuePids = ($queueState.QueueProcesses | Select-Object -ExpandProperty ProcessId) -join ", "
    Write-Host "Queue      : RUNNING ($queuePids)" -ForegroundColor Green
  } else {
    Write-Host "Queue      : not running" -ForegroundColor Yellow
  }
  if ($queueState.ActiveEntry) {
    Write-Host "Active     : $($queueState.ActiveEntry.Id) / $($queueState.ActiveEntry.Label)" -ForegroundColor Cyan
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

  if ($stdoutTail.Count -gt 0) {
    Write-Host ""
    Write-Host "Queue stdout tail:" -ForegroundColor White
    foreach ($line in $stdoutTail) {
      Write-Host "  $line"
    }
  }

  if ($stderrTail.Count -gt 0) {
    Write-Host ""
    Write-Host "Queue stderr tail:" -ForegroundColor White
    foreach ($line in $stderrTail) {
      Write-Host "  $line"
    }
  }

  if ($Once) {
    break
  }

  Start-Sleep -Seconds $RefreshSeconds
} while ($true)
