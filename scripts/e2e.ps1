# E2E pipeline script for WebAppTemplate
# Runs build -> ci -> publish -> e2e sequentially, with optional per-stage skips

param(
    [string]$Configuration = "Debug",
    [string]$PublishOutputDir = "artifacts/publish/app",
    [string]$SecretsFile = "scripts/secrets.local.ps1",
    [switch]$UseNpmInstall,
    [switch]$SkipBuild,
    [switch]$SkipCi,
    [switch]$SkipPublish,
    [switch]$SkipE2E,
    [switch]$CI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path -Path $PSScriptRoot -ChildPath "common.ps1")

$paths = Get-RepoPaths
$effectiveCi = Get-EffectiveCiMode -CiSwitch:$CI
$platform = Get-PlatformLabel

$buildScript = Join-Path -Path $PSScriptRoot -ChildPath "build.ps1"
$ciScript = Join-Path -Path $PSScriptRoot -ChildPath "ci.ps1"
$publishScript = Join-Path -Path $PSScriptRoot -ChildPath "publish.ps1"

$buildParams = [ordered]@{
    Configuration = $Configuration
}
if ($UseNpmInstall.IsPresent) {
    $buildParams.UseNpmInstall = $true
}
if ($CI.IsPresent) {
    $buildParams.CI = $true
}

$ciParams = [ordered]@{
    Configuration = $Configuration
    SecretsFile = $SecretsFile
}
if ($CI.IsPresent) {
    $ciParams.CI = $true
}

$publishParams = [ordered]@{
    Configuration = $Configuration
    OutputDir = $PublishOutputDir
}
if ($CI.IsPresent) {
    $publishParams.CI = $true
}

$stages = @(
    [pscustomobject]@{
        Name = "Build"
        Kind = "Script"
        ScriptPath = $buildScript
        Skip = $SkipBuild.IsPresent
        Parameters = $buildParams
    },
    [pscustomobject]@{
        Name = "CI"
        Kind = "Script"
        ScriptPath = $ciScript
        Skip = $SkipCi.IsPresent
        Parameters = $ciParams
    },
    [pscustomobject]@{
        Name = "Publish"
        Kind = "Script"
        ScriptPath = $publishScript
        Skip = $SkipPublish.IsPresent
        Parameters = $publishParams
    },
    [pscustomobject]@{
        Name = "E2E"
        Kind = "Custom"
        Skip = $SkipE2E.IsPresent
        Parameters = [ordered]@{}
    }
)

$enabledStages = @($stages | Where-Object { -not $_.Skip })

Write-Host "Running WebAppTemplate E2E pipeline..." -ForegroundColor Cyan
Write-Host "Platform: $platform | CI: $effectiveCi | Configuration: $Configuration" -ForegroundColor Gray
Write-Host "Publish output: $(Resolve-ProjectRelativePath -ProjectRoot $paths.ProjectRoot -Path $PublishOutputDir)" -ForegroundColor Gray
Write-Host ("Stages: " + (($stages | ForEach-Object {
    if ($_.Skip) { "{0}=skip" -f $_.Name.ToLowerInvariant() } else { "{0}=run" -f $_.Name.ToLowerInvariant() }
}) -join " | ")) -ForegroundColor Gray

if ($enabledStages.Count -eq 0) {
    Write-Host "No stages selected. Nothing to do." -ForegroundColor Yellow
    return
}

$stageIndex = 0
$totalStages = $enabledStages.Count

foreach ($stage in $stages) {
    if ($stage.Skip) {
        Write-Host "Skipping $($stage.Name) (-Skip$($stage.Name))." -ForegroundColor DarkGray
        continue
    }

    $stageIndex++
    Write-Host "`n[$stageIndex/$totalStages] $($stage.Name)..." -ForegroundColor Yellow

    if ($stage.Kind -eq "Custom" -and $stage.Name -eq "E2E") {
        Invoke-External `
            -FilePath "npm" `
            -Arguments @("run", "test:e2e:install") `
            -WorkingDirectory $paths.WebDir `
            -StepName "Playwright browser install"

        Invoke-External `
            -FilePath "npm" `
            -Arguments @("run", "test:e2e:ci") `
            -WorkingDirectory $paths.WebDir `
            -StepName "Web E2E tests"
        continue
    }

    $stageParams = [ordered]@{}
    $displayArgs = @()
    foreach ($entry in $stage.Parameters.GetEnumerator()) {
        $stageParams[$entry.Key] = $entry.Value
        $displayArgs += "-$($entry.Key)"

        if (-not ($entry.Value -is [bool])) {
            $displayArgs += [string]$entry.Value
        }
    }

    Write-Host (">> " + (Format-CommandForDisplay -FilePath $stage.ScriptPath -Arguments $displayArgs)) -ForegroundColor DarkGray
    & $stage.ScriptPath @stageParams
}

Write-Host "`nE2E pipeline complete." -ForegroundColor Green
