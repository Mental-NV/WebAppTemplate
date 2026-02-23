# CI script for WebAppTemplate
# Cross-platform (pwsh) CI/local verification for API + Web

param(
    [string]$Configuration = "Debug",
    [switch]$NoRestore,
    [switch]$NoBuild,
    [switch]$NoWebInstall,
    [switch]$UseNpmInstall,
    [switch]$SkipApiUnitTests,
    [switch]$SkipApiIntegrationTests,
    [switch]$SkipWebTests,
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
Write-Host "Restore: $(-not $NoRestore) | Build: $(-not $NoBuild) | Web install: $(-not $NoWebInstall)" -ForegroundColor Gray

$step = 0
$totalSteps = 7

$step++
Write-Host "`n[$step/$totalSteps] Preflight checks..." -ForegroundColor Yellow
Assert-CommandAvailable -Name "dotnet"
Assert-CommandAvailable -Name "npm"

$step++
Write-Host "`n[$step/$totalSteps] Restoring .NET dependencies..." -ForegroundColor Yellow
if ($NoRestore.IsPresent) {
    Write-Host "Skipping dotnet restore (-NoRestore)." -ForegroundColor DarkGray
}
else {
    Invoke-External -FilePath "dotnet" -Arguments @("restore", $paths.SolutionPath) -WorkingDirectory $paths.ProjectRoot -StepName "dotnet restore"
}

$step++
Write-Host "`n[$step/$totalSteps] Installing web dependencies..." -ForegroundColor Yellow
if ($NoWebInstall.IsPresent) {
    Write-Host "Skipping npm install/ci (-NoWebInstall)." -ForegroundColor DarkGray
}
else {
    Install-WebDependencies -WebDir $paths.WebDir -LockFilePath $paths.WebPackageLockPath -UseNpmInstall:$UseNpmInstall
}

$step++
Write-Host "`n[$step/$totalSteps] Building solution..." -ForegroundColor Yellow
if ($NoBuild.IsPresent) {
    Write-Host "Skipping build (-NoBuild). Tests will still run with --no-build." -ForegroundColor DarkGray
}
else {
    $buildArgs = @("build", $paths.SolutionPath, "--configuration", $Configuration)
    if (-not $NoRestore.IsPresent) {
        $buildArgs += "--no-restore"
    }
    Invoke-External -FilePath "dotnet" -Arguments $buildArgs -WorkingDirectory $paths.ProjectRoot -StepName "dotnet build"
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
