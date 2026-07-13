param(
  [int]$Port = 8011,
  [switch]$Hidden,
  [switch]$RunForeground,
  [int]$StartupTimeoutSec = 120
)

$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot\..
. "$PSScriptRoot\resolve_orchestrator_python.ps1"

$projectRoot = (Get-Location).Path
$pythonExe = Resolve-OrchestratorPython -ProjectRoot $projectRoot
if (-not $pythonExe) {
  Write-Error "Missing orchestrator environment. Run scripts/setup_orchestrator_env.ps1 first."
  exit 1
}

function Get-ListeningPids {
  param([int]$TargetPort)

  $pids = @()
  try {
    $connections = Get-NetTCPConnection -LocalPort $TargetPort -State Listen -ErrorAction Stop
    $pids = $connections | Select-Object -ExpandProperty OwningProcess -Unique
  } catch {
    $netstatOutput = netstat -ano -p tcp | Select-String ":$TargetPort\s+.*LISTENING\s+(\d+)$"
    foreach ($line in $netstatOutput) {
      if ($line.Matches.Count -gt 0) {
        $pids += [int]$line.Matches[0].Groups[1].Value
      }
    }
    $pids = $pids | Select-Object -Unique
  }
  return @($pids)
}

function Wait-ForHealth {
  param(
    [int]$TargetPort,
    [int]$TimeoutSec
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $healthUrl = "http://127.0.0.1:$TargetPort/health"

  while ((Get-Date) -lt $deadline) {
    try {
      $response = Invoke-RestMethod -Uri $healthUrl -Method Get -TimeoutSec 5
      if ($response.status -eq "ok") {
        return $true
      }
    } catch {
      Start-Sleep -Milliseconds 700
    }
  }

  return $false
}

function Get-ListeningPid {
  param([int]$TargetPort)

  $pids = Get-ListeningPids -TargetPort $TargetPort
  if ($pids -and $pids.Count -gt 0) {
    return [int]$pids[0]
  }

  return $null
}

function Get-ProcessCommandLine {
  param([int]$ProcessId)

  try {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop
    return $process.CommandLine
  } catch {
    return $null
  }
}

function Stop-TtsWorkerProcesses {
  param([int]$TargetPort)

  $listeningPids = Get-ListeningPids -TargetPort $TargetPort
  $workerPids = @()
  try {
    $workerPids = Get-CimInstance Win32_Process -ErrorAction Stop |
      Where-Object {
        $_.Name -eq "python.exe" -and
        $_.CommandLine -like "*runtime*external_agents*edge_tts_worker*server.py*"
      } |
      Select-Object -ExpandProperty ProcessId -Unique
  } catch {
    $workerPids = @()
  }

  $processIds = @(
    @($listeningPids)
    @($workerPids)
  ) | Select-Object -Unique

  foreach ($processId in $processIds) {
    try {
      Stop-Process -Id $processId -Force -ErrorAction Stop
    } catch {
      Write-Warning "Failed to stop PID ${processId}: $($_.Exception.Message)"
    }
  }
  Start-Sleep -Seconds 1
}

if (Wait-ForHealth -TargetPort $Port -TimeoutSec 2) {
  $listeningPid = Get-ListeningPid -TargetPort $Port
  $commandLine = if ($listeningPid) { Get-ProcessCommandLine -ProcessId $listeningPid } else { $null }
  if ($commandLine -and $commandLine -like "*$pythonExe*") {
    Write-Host "TTS worker already healthy on http://127.0.0.1:$Port/health"
    exit 0
  }

  Write-Host "Healthy TTS worker is running on an outdated Python environment. Restarting it..."
}

Stop-TtsWorkerProcesses -TargetPort $Port
$env:TTS_PROVIDER = "edge"

$serverScript = Join-Path $projectRoot "runtime\external_agents\edge_tts_worker\server.py"
if (-not (Test-Path $serverScript)) {
  Write-Error "Missing TTS worker server script: $serverScript"
  exit 1
}

if ($RunForeground) {
  & $pythonExe $serverScript
  exit $LASTEXITCODE
}

$startProcessArgs = @{
  FilePath = $pythonExe
  ArgumentList = @($serverScript)
  WorkingDirectory = $projectRoot
  PassThru = $true
}

if ($Hidden) {
  $startProcessArgs["WindowStyle"] = "Hidden"
}

$process = Start-Process @startProcessArgs
Write-Host "Started TTS worker PID $($process.Id) on port $Port."

if (Wait-ForHealth -TargetPort $Port -TimeoutSec $StartupTimeoutSec) {
  Write-Host "TTS worker is healthy on http://127.0.0.1:$Port/health"
  exit 0
}

Write-Warning "TTS worker did not become healthy within ${StartupTimeoutSec}s."
exit 1
