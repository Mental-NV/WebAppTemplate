# Build script for WebAppTemplate
# Builds API and Web, then copies web output to API wwwroot (cross-platform, pwsh)

param(
    [string]$Configuration = "Debug",
    [switch]$NoRestore,
    [switch]$NoWebInstall,
    [switch]$UseNpmInstall,
    [switch]$SkipCopyToWwwroot,
    [switch]$NoCleanWwwroot,
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
Write-Host "Restore: $(-not $NoRestore) | Web install: $(-not $NoWebInstall) | Copy to wwwroot: $(-not $SkipCopyToWwwroot)" -ForegroundColor Gray

$step = 0
$totalSteps = 6

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
Write-Host "`n[$step/$totalSteps] Building API..." -ForegroundColor Yellow
$apiBuildArgs = @(
    "build",
    $paths.ApiProjectPath,
    "--configuration", $Configuration
)
if (-not $NoRestore.IsPresent) {
    $apiBuildArgs += "--no-restore"
}
Invoke-External -FilePath "dotnet" -Arguments $apiBuildArgs -WorkingDirectory $paths.ProjectRoot -StepName "API build"

$step++
Write-Host "`n[$step/$totalSteps] Building Web..." -ForegroundColor Yellow
Invoke-External -FilePath "npm" -Arguments @("run", "build") -WorkingDirectory $paths.WebDir -StepName "Web build"

$step++
Write-Host "`n[$step/$totalSteps] Syncing web output to API wwwroot..." -ForegroundColor Yellow
if ($SkipCopyToWwwroot.IsPresent) {
    Write-Host "Skipping copy to wwwroot (-SkipCopyToWwwroot)." -ForegroundColor DarkGray
}
else {
    if (-not (Test-Path -LiteralPath $paths.WebDistDir)) {
        throw "Web build output was not found at '$($paths.WebDistDir)'."
    }

    Sync-DirectoryContents `
        -SourceDir $paths.WebDistDir `
        -DestinationDir $paths.ApiWwwRootDir `
        -CleanDestination:(-not $NoCleanWwwroot.IsPresent) `
        -PreserveNames @(".gitkeep")

    Write-Host "Copied web files to $($paths.ApiWwwRootDir)" -ForegroundColor Green
}

Write-Host "`nBuild complete." -ForegroundColor Green
Write-Host "Run 'dotnet run' in src/api or use scripts/run.ps1 for published app execution." -ForegroundColor Gray
