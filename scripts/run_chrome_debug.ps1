param(
  [int]$Port = 9222,
  [string]$ProfileDirectory = "Default"
)

$chromeCandidates = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
)

$chromePath = $chromeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chromePath) {
  Write-Error "Could not find chrome.exe."
  exit 1
}

$userDataDir = Join-Path $env:LocalAppData "Google\Chrome\User Data"
if (-not (Test-Path $userDataDir)) {
  Write-Error "Chrome user data directory was not found: $userDataDir"
  exit 1
}

Write-Host "Launching Chrome with remote debugging on port $Port"
Write-Host "Profile directory: $ProfileDirectory"
Write-Host "User data directory: $userDataDir"
Write-Host "If Chrome refuses to use the profile, close existing Chrome windows and try again."

Start-Process -FilePath $chromePath -ArgumentList @(
  "--remote-debugging-port=$Port",
  "--user-data-dir=$userDataDir",
  "--profile-directory=$ProfileDirectory"
)
