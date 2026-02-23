# Publish script for WebAppTemplate
# Produces a single deployable artifact (API + React assets in publish/wwwroot)

param(
    [string]$Configuration = "Debug",
    [string]$OutputDir = "artifacts/publish/app",
    [switch]$CI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path -Path $PSScriptRoot -ChildPath "common.ps1")

$paths = Get-RepoPaths
$effectiveCi = Get-EffectiveCiMode -CiSwitch:$CI
$platform = Get-PlatformLabel

$artifactPaths = Get-PublishArtifactPaths -ProjectRoot $paths.ProjectRoot -OutputDir $OutputDir
$publishOutputDir = $artifactPaths.OutputDir

Write-Host "Publishing WebAppTemplate..." -ForegroundColor Cyan
Write-Host "Platform: $platform | CI: $effectiveCi | Configuration: $Configuration" -ForegroundColor Gray
Write-Host "Output: $publishOutputDir" -ForegroundColor Gray
Write-Host "Assumes scripts/build.ps1 and scripts/ci.ps1 already completed for the same configuration." -ForegroundColor Gray

$step = 0
$totalSteps = 4

$step++
Write-Host "`n[$step/$totalSteps] Preflight checks..." -ForegroundColor Yellow
Assert-CommandAvailable -Name "dotnet"

$step++
Write-Host "`n[$step/$totalSteps] Validating build stage outputs..." -ForegroundColor Yellow
$apiWwwRootIndexPath = Join-Path -Path $paths.ApiWwwRootDir -ChildPath "index.html"
if (-not (Test-Path -LiteralPath $apiWwwRootIndexPath)) {
    throw "Expected synced SPA asset at '$apiWwwRootIndexPath'. Run scripts/build.ps1 first."
}
if (-not (Test-Path -LiteralPath $paths.WebDistDir)) {
    throw "Expected web build output at '$($paths.WebDistDir)'. Run scripts/build.ps1 first."
}

$step++
Write-Host "`n[$step/$totalSteps] Publishing API..." -ForegroundColor Yellow
$publishArgs = @(
    "publish",
    $paths.ApiProjectPath,
    "--configuration", $Configuration,
    "--output", $publishOutputDir,
    "--no-build",
    "--no-restore"
)
Invoke-External -FilePath "dotnet" -Arguments $publishArgs -WorkingDirectory $paths.ProjectRoot -StepName "dotnet publish"

$step++
Write-Host "`n[$step/$totalSteps] Validating publish artifact..." -ForegroundColor Yellow
Assert-PublishArtifact `
    -PublishOutputDir $artifactPaths.OutputDir `
    -ApiDllPath $artifactPaths.ApiDllPath `
    -SpaIndexPath $artifactPaths.SpaIndexPath

Write-Host "`nPublish complete." -ForegroundColor Green
Write-Host "Artifact: $publishOutputDir" -ForegroundColor Gray
