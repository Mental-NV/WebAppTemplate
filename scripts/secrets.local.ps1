$repoRoot = Split-Path -Parent $PSScriptRoot
$apiProjectDir = Join-Path -Path $repoRoot -ChildPath "src/api"

$lines = & dotnet user-secrets list --project $apiProjectDir
if ($LASTEXITCODE -ne 0) {
  throw "dotnet user-secrets failed. Output: $lines"
}

$secrets = @{}

foreach ($line in $lines) {
  if ([string]::IsNullOrWhiteSpace($line)) { continue }

  if ($line -match '^\s*(?<key>[^=]+?)\s*=\s*(?<value>.*)\s*$') {
    $secrets[($Matches['key'].Trim() -replace ':', '__')] = $Matches['value']
  }
}

$requiredEnvNames = @(
  "Jwt__SigningKey",
  "Google__ClientId",
  "ASPNETCORE_Kestrel__Certificates__Default__Path",
  "ASPNETCORE_Kestrel__Certificates__Default__Password"
)

$loaded = 0
foreach ($envName in $requiredEnvNames) {
  if (-not [string]::IsNullOrWhiteSpace($secrets[$envName])) {
    Set-Item -Path ("Env:{0}" -f $envName) -Value $secrets[$envName]
    $loaded++
  }
}

$initializedViteGoogleClientId = $false
if ([string]::IsNullOrWhiteSpace($env:VITE_GOOGLE_CLIENT_ID) -and -not [string]::IsNullOrWhiteSpace($env:Google__ClientId)) {
  Set-Item -Path "Env:VITE_GOOGLE_CLIENT_ID" -Value $env:Google__ClientId
  $initializedViteGoogleClientId = $true
}

Write-Host "Loaded $loaded required environment variable(s) from dotnet user-secrets."
if ($initializedViteGoogleClientId) {
  Write-Host "Initialized VITE_GOOGLE_CLIENT_ID from Google__ClientId."
}
