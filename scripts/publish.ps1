# Publish script for WebAppTemplate
# Produces a single deployable artifact (API + React assets in publish/wwwroot)

param(
    [string]$Configuration = "Release",
    [string]$OutputDir = "artifacts/publish/app",
    [switch]$NoRestore,
    [switch]$NoWebInstall,
    [switch]$UseNpmInstall,
    [switch]$NoApiPublish,
    [switch]$NoWebBuild,
    [switch]$NoCleanPublishWwwroot,
    [string]$SecretsFile = "scripts/secrets.local.ps1",
    [switch]$CI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path -Path $PSScriptRoot -ChildPath "common.ps1")

$paths = Get-RepoPaths
$effectiveCi = Get-EffectiveCiMode -CiSwitch:$CI
$platform = Get-PlatformLabel

$publishOutputDir = $OutputDir
if (-not [System.IO.Path]::IsPathRooted($publishOutputDir)) {
    $publishOutputDir = Join-Path -Path $paths.ProjectRoot -ChildPath $publishOutputDir
}
$publishWwwRootDir = Join-Path -Path $publishOutputDir -ChildPath "wwwroot"
$apiDllPath = Join-Path -Path $publishOutputDir -ChildPath "Api.dll"
$publishIndexPath = Join-Path -Path $publishWwwRootDir -ChildPath "index.html"

Write-Host "Publishing WebAppTemplate..." -ForegroundColor Cyan
Write-Host "Platform: $platform | CI: $effectiveCi | Configuration: $Configuration" -ForegroundColor Gray
Write-Host "Output: $publishOutputDir" -ForegroundColor Gray

$step = 0
$totalSteps = 8

$step++
Write-Host "`n[$step/$totalSteps] Loading optional secrets..." -ForegroundColor Yellow
[void](Import-OptionalSecretsFile -ProjectRoot $paths.ProjectRoot -SecretsFile $SecretsFile)

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
Write-Host "`n[$step/$totalSteps] Building web..." -ForegroundColor Yellow
if ($NoWebBuild.IsPresent) {
    Write-Host "Skipping web build (-NoWebBuild)." -ForegroundColor DarkGray
}
else {
    Invoke-External -FilePath "npm" -Arguments @("run", "build") -WorkingDirectory $paths.WebDir -StepName "Web build"
}

if (-not (Test-Path -LiteralPath $paths.WebDistDir)) {
    throw "Web build output was not found at '$($paths.WebDistDir)'."
}

$step++
Write-Host "`n[$step/$totalSteps] Publishing API..." -ForegroundColor Yellow
if ($NoApiPublish.IsPresent) {
    Write-Host "Skipping dotnet publish (-NoApiPublish)." -ForegroundColor DarkGray
}
else {
    $publishArgs = @(
        "publish",
        $paths.ApiProjectPath,
        "--configuration", $Configuration,
        "--output", $publishOutputDir
    )
    if (-not $NoRestore.IsPresent) {
        $publishArgs += "--no-restore"
    }
    Invoke-External -FilePath "dotnet" -Arguments $publishArgs -WorkingDirectory $paths.ProjectRoot -StepName "dotnet publish"
}

$step++
Write-Host "`n[$step/$totalSteps] Copying React build output into publish/wwwroot..." -ForegroundColor Yellow
if (-not (Test-Path -LiteralPath $publishOutputDir)) {
    throw "Publish output directory not found: $publishOutputDir"
}

Sync-DirectoryContents `
    -SourceDir $paths.WebDistDir `
    -DestinationDir $publishWwwRootDir `
    -CleanDestination:(-not $NoCleanPublishWwwroot.IsPresent) `
    -PreserveNames @(".gitkeep")

$step++
Write-Host "`n[$step/$totalSteps] Validating publish artifact..." -ForegroundColor Yellow
if (-not (Test-Path -LiteralPath $apiDllPath)) {
    throw "Publish validation failed: Api.dll was not found at '$apiDllPath'."
}
if (-not (Test-Path -LiteralPath $publishIndexPath)) {
    throw "Publish validation failed: SPA index.html was not found at '$publishIndexPath'."
}

Write-Host "`nPublish complete." -ForegroundColor Green
Write-Host "Artifact: $publishOutputDir" -ForegroundColor Gray
