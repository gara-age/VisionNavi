param(
  [int]$Tail = 8
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $projectRoot

$entries = @(
  @{ Kind = "prod"; Id = "ko_nabiya"; Phrase = ([string]([char]0xB098) + [char]0xBE44 + [char]0xC57C); Runtime = "ko_nabiya.onnx"; OutputDir = "ko_nabiya"; Log = "wakeword_training_prod_queue.log"; Err = "wakeword_training_prod_queue.error.log" },
  @{ Kind = "prod"; Id = "ko_hey_nabi"; Phrase = ([string]([char]0xD5E4) + [char]0xC774 + " " + [char]0xB098 + [char]0xBE44); Runtime = "ko_hey_nabi.onnx"; OutputDir = "ko_hey_nabi"; Log = "wakeword_training_prod_queue.log"; Err = "wakeword_training_prod_queue.error.log" },
  @{ Kind = "prod"; Id = "ja_nee_navi"; Phrase = ([string]([char]0x306D) + [char]0x3048 + [char]0x3001 + [char]0x30CA + [char]0x30D3); Runtime = "ja_nee_navi.onnx"; OutputDir = "ja_nee_navi"; Log = "wakeword_training_prod_queue.log"; Err = "wakeword_training_prod_queue.error.log" },
  @{ Kind = "prod"; Id = "ja_navisan"; Phrase = ([string]([char]0x30CA) + [char]0x30D3 + [char]0x3055 + [char]0x3093); Runtime = "ja_navisan.onnx"; OutputDir = "ja_navisan"; Log = "wakeword_training_prod_queue.log"; Err = "wakeword_training_prod_queue.error.log" },
  @{ Kind = "dev"; Id = "ko_nabiya_dev"; Phrase = ([string]([char]0xB098) + [char]0xBE44 + [char]0xC57C); Runtime = "ko_nabiya_dev.onnx"; OutputDir = "ko_nabiya_dev"; Log = "wakeword_training_dev_queue.log"; Err = "wakeword_training_dev_queue.error.log" },
  @{ Kind = "dev"; Id = "ja_nee_navi_dev"; Phrase = ([string]([char]0x306D) + [char]0x3048 + [char]0x3001 + [char]0x30CA + [char]0x30D3); Runtime = "ja_nee_navi_dev.onnx"; OutputDir = "ja_nee_navi_dev"; Log = "wakeword_training_dev_queue.log"; Err = "wakeword_training_dev_queue.error.log" },
  @{ Kind = "dev"; Id = "ko_hey_nabi_dev"; Phrase = ([string]([char]0xD5E4) + [char]0xC774 + " " + [char]0xB098 + [char]0xBE44); Runtime = "ko_hey_nabi_dev.onnx"; OutputDir = "ko_hey_nabi_dev"; Log = "wakeword_training_dev_queue.log"; Err = "wakeword_training_dev_queue.error.log" },
  @{ Kind = "dev"; Id = "ja_navisan_dev"; Phrase = ([string]([char]0x30CA) + [char]0x30D3 + [char]0x3055 + [char]0x3093); Runtime = "ja_navisan_dev.onnx"; OutputDir = "ja_navisan_dev"; Log = "wakeword_training_dev_queue.log"; Err = "wakeword_training_dev_queue.error.log" }
)

$runtimeModelDir = Join-Path $projectRoot "runtime/wakewords/models"
$outputRoot = "D:/VisionNaviWakeword/output"
$logDir = "D:/VisionNaviWakeword/logs"

Write-Host ""
Write-Host "VisionNavi Wakeword Training Status"
Write-Host "=================================="

foreach ($entry in $entries) {
  $runtimeModelPath = Join-Path $runtimeModelDir $entry.Runtime
  $outputModelPath = Join-Path $outputRoot "$($entry.OutputDir)/$($entry.Id).onnx"
  $outputDirPath = Join-Path $outputRoot $entry.OutputDir

  Write-Host ""
  Write-Host "[$($entry.Kind.ToUpper())] $($entry.Id) / $($entry.Phrase)"

  Write-Host " - runtime model : " -NoNewline
  if (Test-Path $runtimeModelPath) {
    $runtimeFile = Get-Item $runtimeModelPath
    Write-Host "READY ($([math]::Round($runtimeFile.Length / 1KB, 1)) KB, $($runtimeFile.LastWriteTime))" -ForegroundColor Green
  } else {
    Write-Host "missing" -ForegroundColor Yellow
  }

  Write-Host " - output model  : " -NoNewline
  if (Test-Path $outputModelPath) {
    $outputFile = Get-Item $outputModelPath
    Write-Host "exported ($([math]::Round($outputFile.Length / 1KB, 1)) KB, $($outputFile.LastWriteTime))" -ForegroundColor Green
  } else {
    Write-Host "not exported yet" -ForegroundColor Yellow
  }

  Write-Host " - output dir    : " -NoNewline
  if (Test-Path $outputDirPath) {
    $fileCount = (Get-ChildItem $outputDirPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Host "present ($fileCount files)" -ForegroundColor Cyan
  } else {
    Write-Host "missing" -ForegroundColor Yellow
  }
}

Write-Host ""
Write-Host "Recent logs"
Write-Host "-----------"
$seenLogs = @{}
foreach ($entry in $entries) {
  foreach ($logName in @($entry.Log, $entry.Err)) {
    if (-not $logName -or $seenLogs.ContainsKey($logName)) {
      continue
    }
    $seenLogs[$logName] = $true
    $logPath = Join-Path $logDir $logName
    if (Test-Path $logPath) {
      Write-Host ""
      Write-Host "[$logName]"
      Get-Content $logPath -Tail $Tail
    }
  }
}
