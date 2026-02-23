# Copy this file to scripts/secrets.local.ps1 and replace placeholder values.
# These environment variables are used by publish/run scripts and the ASP.NET app.

# React build-time Google client ID (optional for local publish/build, required for real Google sign-in)
$env:VITE_GOOGLE_CLIENT_ID = "REPLACE_ME.apps.googleusercontent.com"

# API runtime auth configuration (required by scripts/run.ps1)
$env:Google__ClientId = "REPLACE_ME.apps.googleusercontent.com"
$env:Jwt__SigningKey = "REPLACE_ME_with_a_real_signing_key_at_least_32_chars"

# HTTPS certificate source-of-truth secrets for local CI/published runs (required by scripts/run.ps1)
# Example generation/export (cross-platform, run once):
#   dotnet dev-certs https -ep ./.certs/webapptemplate-dev.pfx -p "changeit"
$env:HTTPS_CERT_PASSWORD = "REPLACE_ME_cert_password"
$env:HTTPS_CERT_PFX_BASE64 = "REPLACE_ME_base64_pfx"

# scripts/ci.ps1 and scripts/run.ps1 materialize to:
#   .certs/webapptemplate-dev.pfx
# and derive:
#   ASPNETCORE_Kestrel__Certificates__Default__Path
#   ASPNETCORE_Kestrel__Certificates__Default__Password
