$repoRoot = Split-Path -Parent $PSScriptRoot
$apiProjectDir = Join-Path -Path $repoRoot -ChildPath "src/api"

$lines = & dotnet user-secrets list --project $apiProjectDir
if ($LASTEXITCODE -ne 0) {
  throw "dotnet user-secrets failed. Output: $lines"
}

$loaded = 0

foreach ($line in $lines) {
  if ([string]::IsNullOrWhiteSpace($line)) { continue }

  # Expected: Key:SubKey = value (value may contain '=' so capture the rest)
  if ($line -match '^\s*(?<key>[^=]+?)\s*=\s*(?<value>.*)\s*$') {
    $key = $Matches['key'].Trim()
    $value = $Matches['value']  # do NOT Trim() to preserve leading/trailing spaces if any

    # ASP.NET Core env-var mapping: ':' becomes '__'
    $envName = $key -replace ':', '__'

    Set-Item -Path ("Env:{0}" -f $envName) -Value $value
    Write-Host "Loaded user-secret: $envName"
    $loaded++
  }
  else {
    Write-Warning "Skipping unrecognized line: $line"
  }
}

Write-Host "Loaded $loaded environment variable(s) from user-secrets."

# Normalize a few aliases so scripts/run.ps1 sees the expected env names.
# Keep this file safe to commit: no real secret values are stored here.

if ([string]::IsNullOrWhiteSpace($env:VITE_GOOGLE_CLIENT_ID) -and -not [string]::IsNullOrWhiteSpace($env:Google__ClientId)) {
  $env:VITE_GOOGLE_CLIENT_ID = $env:Google__ClientId
}

# Allow user-secrets keys without ASPNETCORE_ prefix and map them to the runtime env names used by run.ps1.
if ([string]::IsNullOrWhiteSpace($env:ASPNETCORE_Kestrel__Certificates__Default__Path) -and -not [string]::IsNullOrWhiteSpace($env:Kestrel__Certificates__Default__Path)) {
  $env:ASPNETCORE_Kestrel__Certificates__Default__Path = $env:Kestrel__Certificates__Default__Path
}

if ([string]::IsNullOrWhiteSpace($env:ASPNETCORE_Kestrel__Certificates__Default__Password) -and -not [string]::IsNullOrWhiteSpace($env:Kestrel__Certificates__Default__Password)) {
  $env:ASPNETCORE_Kestrel__Certificates__Default__Password = $env:Kestrel__Certificates__Default__Password
}

# Non-secret convenience default for local cert path (only if not already provided).
if ([string]::IsNullOrWhiteSpace($env:ASPNETCORE_Kestrel__Certificates__Default__Path)) {
  $env:ASPNETCORE_Kestrel__Certificates__Default__Path = ".certs/webapptemplate-dev.pfx"
}
