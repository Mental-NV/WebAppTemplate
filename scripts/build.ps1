# Build script for WebAppTemplate
# Builds API and Web, copies web output to API's wwwroot

param(
    [string]$Configuration = "Debug"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ApiPath = Join-Path $ProjectRoot "src\api"
$WebPath = Join-Path $ProjectRoot "src\web"
$WwwRootPath = Join-Path $ApiPath "wwwroot"

Write-Host "Building WebAppTemplate..." -ForegroundColor Cyan
Write-Host "Configuration: $Configuration" -ForegroundColor Gray

# Step 1: Build API
Write-Host "`n[1/3] Building API..." -ForegroundColor Yellow
Push-Location $ApiPath
try {
    dotnet build --configuration $Configuration
    if ($LASTEXITCODE -ne 0) { throw "API build failed" }
}
finally {
    Pop-Location
}

# Step 2: Build Web (Vite)
Write-Host "`n[2/3] Building Web..." -ForegroundColor Yellow
Push-Location $WebPath
try {
    npm run build
    if ($LASTEXITCODE -ne 0) { throw "Web build failed" }
}
finally {
    Pop-Location
}

# Step 3: Copy web output to wwwroot
Write-Host "`n[3/3] Copying web output to wwwroot..." -ForegroundColor Yellow

# Create wwwroot if it doesn't exist
if (-not (Test-Path $WwwRootPath)) {
    New-Item -ItemType Directory -Path $WwwRootPath | Out-Null
}

# Remove existing files in wwwroot (except .gitkeep if any)
Get-ChildItem -Path $WwwRootPath -File | Remove-Item -Force

# Copy Vite dist contents to wwwroot
$DistPath = Join-Path $WebPath "dist"
if (Test-Path $DistPath) {
    Copy-Item -Path "$DistPath\*" -Destination $WwwRootPath -Recurse -Force
    Write-Host "Copied web files to $WwwRootPath" -ForegroundColor Green
} else {
    Write-Host "Warning: dist folder not found at $DistPath" -ForegroundColor Yellow
}

Write-Host "`nBuild complete!" -ForegroundColor Green
Write-Host "Run 'dotnet run' in src/api to start the application" -ForegroundColor Gray
