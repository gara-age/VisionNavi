param(
  [ValidateSet("ollama", "dev")]
  [string]$Mode = "ollama",
  [int]$OrchestratorPort = 8010,
  [int]$TtsPort = 8011,
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

function Stop-ProcessesByIds {
  param(
    [int[]]$ProcessIds,
    [string]$Label
  )

  $uniqueIds = @($ProcessIds | Where-Object { $_ } | Select-Object -Unique)
  foreach ($processId in $uniqueIds) {
    try {
      $process = Get-Process -Id $processId -ErrorAction Stop
      Write-Host "Stopping $Label PID $processId ($($process.ProcessName))..."
      Stop-Process -Id $processId -Force -ErrorAction Stop
    } catch {
      Write-Warning "Failed to stop $Label PID ${processId}: $($_.Exception.Message)"
    }
  }
}

function Get-ManagedPythonProcessIds {
  param([string]$CurrentPythonExe)

  $matches = @()

  try {
    $rows = Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
      $_.Name -eq "python.exe" -and (
        $_.CommandLine -like "*uvicorn app.main:app*" -or
        $_.CommandLine -like "*runtime\\external_agents\\edge_tts_worker\\server.py*"
      )
    }

    foreach ($row in $rows) {
      if (
        $row.CommandLine -like "*D:\\VisionNaviRuntime\\orchestrator-venv*" -or
        $row.CommandLine -like "*C:\\Python311\\python.exe*" -or
        $row.CommandLine -like "*$CurrentPythonExe*"
      ) {
        $matches += [int]$row.ProcessId
      }
    }
  } catch {
    return @()
  }

  return @($matches | Select-Object -Unique)
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

Write-Host "== VisionNavi backend recovery restart =="
Write-Host "Python environment: $pythonExe"

$managedProcessIds = Get-ManagedPythonProcessIds -CurrentPythonExe $pythonExe
$portPids = @(
  @(Get-ListeningPids -TargetPort $OrchestratorPort)
  @(Get-ListeningPids -TargetPort $TtsPort)
) | Select-Object -Unique

$allBackendPids = @(
  @($managedProcessIds)
  @($portPids)
) | Select-Object -Unique

Stop-ProcessesByIds -ProcessIds $allBackendPids -Label "backend"
Start-Sleep -Seconds 2

$restartScript = Join-Path $PSScriptRoot "restart_orchestrator.ps1"
if (-not (Test-Path $restartScript)) {
  Write-Error "Missing restart script: $restartScript"
  exit 1
}

$restartArgs = @(
  "-NoLogo",
  "-NoProfile",
  "-ExecutionPolicy", "Bypass",
  "-File", $restartScript,
  "-Mode", $Mode,
  "-Port", "$OrchestratorPort",
  "-StartupTimeoutSec", "$StartupTimeoutSec"
)

if ($Hidden) {
  $restartArgs += "-Hidden"
}

if ($RunForeground) {
  & powershell.exe @restartArgs
  exit $LASTEXITCODE
}

& powershell.exe @restartArgs
exit $LASTEXITCODE
