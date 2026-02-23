# Build script for WebAppTemplate
# Builds API and Web, then copies web output to API wwwroot (cross-platform, pwsh)

param(
    [string]$Configuration = "Debug",
    [switch]$UseNpmInstall,
    [switch]$CI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path -Path $PSScriptRoot -ChildPath "common.ps1")

$paths = Get-RepoPaths
$effectiveCi = Get-EffectiveCiMode -CiSwitch:$CI
$platform = Get-PlatformLabel

Write-Host "Building WebAppTemplate..." -ForegroundColor Cyan
Write-Host "Platform: $platform | CI: $effectiveCi | Configuration: $Configuration" -ForegroundColor Gray
Write-Host "This stage restores dependencies, builds solution + web, and syncs web assets into API wwwroot." -ForegroundColor Gray

$step = 0
$totalSteps = 6

$step++
Write-Host "`n[$step/$totalSteps] Preflight checks..." -ForegroundColor Yellow
Assert-CommandAvailable -Name "dotnet"
Assert-CommandAvailable -Name "npm"

$step++
Write-Host "`n[$step/$totalSteps] Restoring .NET dependencies..." -ForegroundColor Yellow
Invoke-External -FilePath "dotnet" -Arguments @("restore", $paths.SolutionPath) -WorkingDirectory $paths.ProjectRoot -StepName "dotnet restore"

$step++
Write-Host "`n[$step/$totalSteps] Installing web dependencies..." -ForegroundColor Yellow
Install-WebDependencies -WebDir $paths.WebDir -LockFilePath $paths.WebPackageLockPath -UseNpmInstall:$UseNpmInstall

$step++
Write-Host "`n[$step/$totalSteps] Building solution..." -ForegroundColor Yellow
$solutionBuildArgs = @(
    "build",
    $paths.SolutionPath,
    "--configuration", $Configuration,
    "--no-restore"
)
Invoke-External -FilePath "dotnet" -Arguments $solutionBuildArgs -WorkingDirectory $paths.ProjectRoot -StepName "Solution build"

$step++
Write-Host "`n[$step/$totalSteps] Building Web..." -ForegroundColor Yellow
Invoke-External -FilePath "npm" -Arguments @("run", "build") -WorkingDirectory $paths.WebDir -StepName "Web build"

$step++
Write-Host "`n[$step/$totalSteps] Syncing web output to API wwwroot..." -ForegroundColor Yellow
if (-not (Test-Path -LiteralPath $paths.WebDistDir)) {
    throw "Web build output was not found at '$($paths.WebDistDir)'."
}

Sync-DirectoryContents `
    -SourceDir $paths.WebDistDir `
    -DestinationDir $paths.ApiWwwRootDir `
    -CleanDestination `
    -PreserveNames @(".gitkeep")

Write-Host "Copied web files to $($paths.ApiWwwRootDir)" -ForegroundColor Green

Write-Host "`nBuild complete." -ForegroundColor Green
Write-Host "Next stages: scripts/ci.ps1 -> scripts/publish.ps1 -> scripts/run.ps1" -ForegroundColor Gray
