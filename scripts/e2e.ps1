# E2E script for WebAppTemplate
# Builds SPA assets, starts API via Playwright webServer, runs Playwright tests.

param(
    [switch]$Headed,
    [switch]$Debug,
    [switch]$InstallBrowser = $true,
    [string]$BaseUrl = "http://localhost:5000"
)

$ErrorActionPreference = "Stop"

if ($Headed -and $Debug) {
    throw "Use either -Headed or -Debug, not both."
}

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WebPath = Join-Path $ProjectRoot "src\web"
$RunId = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
$DbConnection = "Data Source=AppData\e2e-$RunId.db"

$env:E2E_RUN_ID = $RunId
$env:E2E_DB_PATH = $DbConnection
$env:E2E_BASE_URL = $BaseUrl
$env:VITE_E2E_AUTH_MODE = "true"

if (-not $env:VITE_GOOGLE_CLIENT_ID) {
    $env:VITE_GOOGLE_CLIENT_ID = "e2e-local-client-id"
}

Write-Host "Running E2E tests..." -ForegroundColor Cyan
Write-Host "Base URL: $BaseUrl" -ForegroundColor Gray
Write-Host "DB: $DbConnection" -ForegroundColor Gray

Write-Host "`n[1/2] Building application..." -ForegroundColor Yellow
& (Join-Path $PSScriptRoot "build.ps1")
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

Write-Host "`n[2/2] Running Playwright tests..." -ForegroundColor Yellow
Push-Location $WebPath
try {
    if ($InstallBrowser) {
        npm run test:e2e:install
        if ($LASTEXITCODE -ne 0) { throw "Playwright browser install failed" }
    }

    if ($Debug) {
        npm run test:e2e:debug
    }
    elseif ($Headed) {
        npm run test:e2e:headed
    }
    else {
        npm run test:e2e
    }

    if ($LASTEXITCODE -ne 0) { throw "E2E tests failed" }
}
finally {
    Pop-Location
}

Write-Host "`nE2E tests complete!" -ForegroundColor Green
