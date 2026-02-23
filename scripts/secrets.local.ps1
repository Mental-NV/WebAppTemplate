$lines = & dotnet user-secrets list --project src/api
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
    Write-Host "Loaded user-secret: $envName = $value"
    $loaded++
  }
  else {
    Write-Warning "Skipping unrecognized line: $line"
  }
}

Write-Host "Loaded $loaded environment variable(s) from user-secrets."

# Copy this file to scripts/secrets.local.ps1 and replace placeholder values.
# These environment variables are used by publish/run scripts and the ASP.NET app.

# React build-time Google client ID (optional for local publish/build, required for real Google sign-in)
$env:VITE_GOOGLE_CLIENT_ID = $env:Google__ClientId


# HTTPS certificate for local published runs (required by scripts/run.ps1)
# Example generation/export (cross-platform, run once):
#   dotnet dev-certs https -ep ./.certs/webapptemplate-dev.pfx -p "changeit"
$env:ASPNETCORE_Kestrel__Certificates__Default__Path = ".certs/webapptemplate-dev.pfx"
$env:ASPNETCORE_Kestrel__Certificates__Default__Password = "REPLACE_ME_cert_password"
