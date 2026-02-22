# CI script for WebAppTemplate
# Runs API unit tests first, then broader API and Web test suites

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ApiPath = Join-Path $ProjectRoot "src\api"
$WebPath = Join-Path $ProjectRoot "src\web"

Write-Host "Running CI tests..." -ForegroundColor Cyan

# Step 1: Run API unit tests first
Write-Host "`n[1/3] Running API unit tests..." -ForegroundColor Yellow
Push-Location $ProjectRoot
try {
    dotnet test .\tests\Api.UnitTests\Api.UnitTests.csproj --no-build --verbosity normal
    if ($LASTEXITCODE -ne 0) { throw "API unit tests failed" }
    Write-Host "API unit tests passed!" -ForegroundColor Green
}
finally {
    Pop-Location
}

# Step 2: Run API tests (dotnet test from solution root)
Write-Host "`n[2/3] Running API tests..." -ForegroundColor Yellow
Push-Location $ProjectRoot
try {
    dotnet test --no-build --verbosity normal
    if ($LASTEXITCODE -ne 0) { throw "API tests failed" }
    Write-Host "API tests passed!" -ForegroundColor Green
}
finally {
    Pop-Location
}

# Step 3: Run Web tests (npm run test from src/web)
Write-Host "`n[3/3] Running Web tests..." -ForegroundColor Yellow
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
