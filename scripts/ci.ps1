# CI script for WebAppTemplate
# Cross-platform (pwsh) CI/local verification for API + Web

param(
    [string]$Configuration = "Debug",
    [switch]$SkipApiUnitTests,
    [switch]$SkipApiIntegrationTests,
    [switch]$SkipWebTests,
    [string]$SecretsFile = "scripts/secrets.local.ps1",
    [switch]$CI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path -Path $PSScriptRoot -ChildPath "common.ps1")

$paths = Get-RepoPaths
$effectiveCi = Get-EffectiveCiMode -CiSwitch:$CI
$platform = Get-PlatformLabel

Write-Host "Running CI checks..." -ForegroundColor Cyan
Write-Host "Platform: $platform | CI: $effectiveCi | Configuration: $Configuration" -ForegroundColor Gray
Write-Host "Assumes scripts/build.ps1 already completed for the same configuration." -ForegroundColor Gray

$step = 0
$totalSteps = 7

$step++
Write-Host "`n[$step/$totalSteps] Preflight checks..." -ForegroundColor Yellow
Assert-CommandAvailable -Name "dotnet"
Assert-CommandAvailable -Name "npm"

$step++
Write-Host "`n[$step/$totalSteps] Loading optional secrets..." -ForegroundColor Yellow
[void](Import-OptionalSecretsFile -ProjectRoot $paths.ProjectRoot -SecretsFile $SecretsFile)

$step++
Write-Host "`n[$step/$totalSteps] Materializing optional HTTPS certificate..." -ForegroundColor Yellow
[void](Initialize-HttpsCertificateMaterialization -ProjectRoot $paths.ProjectRoot)

$step++
Write-Host "`n[$step/$totalSteps] Validating build outputs..." -ForegroundColor Yellow
$apiWwwRootIndexPath = Join-Path -Path $paths.ApiWwwRootDir -ChildPath "index.html"
if (-not (Test-Path -LiteralPath $paths.WebDistDir)) {
    throw "Expected web build output at '$($paths.WebDistDir)'. Run scripts/build.ps1 first."
}
if (-not (Test-Path -LiteralPath $apiWwwRootIndexPath)) {
    throw "Expected synced SPA asset at '$apiWwwRootIndexPath'. Run scripts/build.ps1 first."
}

$dotnetTestCommonArgs = @(
    "--configuration", $Configuration,
    "--no-build",
    "--no-restore",
    "--verbosity", "normal"
)

$step++
Write-Host "`n[$step/$totalSteps] Running API unit tests..." -ForegroundColor Yellow
if ($SkipApiUnitTests.IsPresent) {
    Write-Host "Skipping API unit tests (-SkipApiUnitTests)." -ForegroundColor DarkGray
}
else {
    $apiUnitTestArgs = @("test", $paths.ApiUnitTestsProjectPath) + $dotnetTestCommonArgs
    Invoke-External -FilePath "dotnet" -Arguments $apiUnitTestArgs -WorkingDirectory $paths.ProjectRoot -StepName "API unit tests"
    Write-Host "API unit tests passed." -ForegroundColor Green
}

$step++
Write-Host "`n[$step/$totalSteps] Running API integration tests..." -ForegroundColor Yellow
if ($SkipApiIntegrationTests.IsPresent) {
    Write-Host "Skipping API integration tests (-SkipApiIntegrationTests)." -ForegroundColor DarkGray
}
else {
    $apiIntegrationTestArgs = @("test", $paths.ApiTestsProjectPath) + $dotnetTestCommonArgs
    Invoke-External -FilePath "dotnet" -Arguments $apiIntegrationTestArgs -WorkingDirectory $paths.ProjectRoot -StepName "API integration tests"
    Write-Host "API integration tests passed." -ForegroundColor Green
}

$step++
Write-Host "`n[$step/$totalSteps] Running Web tests..." -ForegroundColor Yellow
if ($SkipWebTests.IsPresent) {
    Write-Host "Skipping Web tests (-SkipWebTests)." -ForegroundColor DarkGray
}
else {
    Invoke-External -FilePath "npm" -Arguments @("run", "test") -WorkingDirectory $paths.WebDir -StepName "Web tests"
    Write-Host "Web tests passed." -ForegroundColor Green
}

Write-Host "`nCI checks complete." -ForegroundColor Green
