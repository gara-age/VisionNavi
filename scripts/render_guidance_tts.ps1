param(
  [Parameter(Mandatory = $true)]
  [string]$Text,

  [Parameter(Mandatory = $true)]
  [ValidateSet("ko", "ja")]
  [string]$Language,

  [string]$Voice = "",

  [double]$Speed = 1.0,
  [double]$Volume = 1.0
)

$ErrorActionPreference = "Stop"
$workerPort = 8011

Set-Location $PSScriptRoot\..
$projectRoot = (Get-Location).Path

$payload = @{
  text = $Text
  language = $Language
  voice = if ([string]::IsNullOrWhiteSpace($Voice)) { $null } else { $Voice }
  speed = $Speed
  volume = $Volume
}

$workerScript = Join-Path $PSScriptRoot "start_tts_worker.ps1"
if (-not (Test-Path $workerScript)) {
  throw "Missing TTS worker start script: $workerScript"
}

& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $workerScript -Port $workerPort -Hidden -StartupTimeoutSec 120 | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Failed to start TTS worker."
}

function Invoke-SynthesizeWithRetry {
  param(
    [string]$Uri,
    [string]$BodyJson,
    [int]$MaxAttempts = 4
  )

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
      return Invoke-RestMethod `
        -Uri $Uri `
        -Method Post `
        -ContentType "application/json; charset=utf-8" `
        -Body $BodyJson `
        -TimeoutSec 180
    } catch {
      if ($attempt -ge $MaxAttempts) {
        throw
      }
      Start-Sleep -Milliseconds (500 * $attempt)
    }
  }
}

$bodyJson = $payload | ConvertTo-Json -Compress
$response = Invoke-SynthesizeWithRetry -Uri "http://127.0.0.1:$workerPort/synthesize" -BodyJson $bodyJson
$response | ConvertTo-Json -Compress
