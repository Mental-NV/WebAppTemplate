# CI script for WebAppTemplate
# Runs API and Web test suites

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ApiPath = Join-Path $ProjectRoot "src\api"
$WebPath = Join-Path $ProjectRoot "src\web"

Write-Host "Running CI tests..." -ForegroundColor Cyan

# Step 1: Run API tests (dotnet test from solution root)
Write-Host "`n[1/2] Running API tests..." -ForegroundColor Yellow
Push-Location $ProjectRoot
try {
    dotnet test --no-build --verbosity normal
    if ($LASTEXITCODE -ne 0) { throw "API tests failed" }
    Write-Host "API tests passed!" -ForegroundColor Green
}
finally {
    Pop-Location
}

# Step 2: Run Web tests (npm run test from src/web)
Write-Host "`n[2/2] Running Web tests..." -ForegroundColor Yellow
Push-Location $WebPath
try {
    npm run test
    if ($LASTEXITCODE -ne 0) { throw "Web tests failed" }
    Write-Host "Web tests passed!" -ForegroundColor Green
}
finally {
    Pop-Location
}

Write-Host "`nCI tests complete!" -ForegroundColor Green
