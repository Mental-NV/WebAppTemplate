# CI script for WebAppTemplate
# Runs API and Web test suites

param(
    [switch]$IncludeE2E = $true
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ApiPath = Join-Path $ProjectRoot "src\api"
$WebPath = Join-Path $ProjectRoot "src\web"
$TotalSteps = if ($IncludeE2E) { 3 } else { 2 }

Write-Host "Running CI tests..." -ForegroundColor Cyan

# Step 1: Run API tests (dotnet test from solution root)
Write-Host "`n[1/$TotalSteps] Running API tests..." -ForegroundColor Yellow
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
Write-Host "`n[2/$TotalSteps] Running Web tests..." -ForegroundColor Yellow
Push-Location $WebPath
try {
    npm run test
    if ($LASTEXITCODE -ne 0) { throw "Web tests failed" }
    Write-Host "Web tests passed!" -ForegroundColor Green
}
finally {
    Pop-Location
}

if ($IncludeE2E) {
    Write-Host "`n[3/$TotalSteps] Running E2E tests..." -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot "e2e.ps1")
    if ($LASTEXITCODE -ne 0) { throw "E2E tests failed" }
    Write-Host "E2E tests passed!" -ForegroundColor Green
}

Write-Host "`nCI tests complete!" -ForegroundColor Green
