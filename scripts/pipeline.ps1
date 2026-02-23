# Pipeline script for WebAppTemplate
# Runs build -> ci -> publish -> run sequentially, with optional per-stage skips

param(
    [string]$Configuration = "Debug",
    [string]$PublishOutputDir = "artifacts/publish/app",
    [string]$SecretsFile = "scripts/secrets.local.ps1",
    [string]$Environment = "Development",
    [string]$DbFilePath = "",
    [int]$HttpPort = 5000,
    [int]$HttpsPort = 5001,
    [switch]$UseNpmInstall,
    [switch]$SkipBuild,
    [switch]$SkipCi,
    [switch]$SkipPublish,
    [switch]$SkipRun,
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
$runScript = Join-Path -Path $PSScriptRoot -ChildPath "run.ps1"

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

$runParams = [ordered]@{
    PublishOutputDir = $PublishOutputDir
    SecretsFile = $SecretsFile
    Environment = $Environment
    DbFilePath = $DbFilePath
    HttpPort = $HttpPort
    HttpsPort = $HttpsPort
}
if ($CI.IsPresent) {
    $runParams.CI = $true
}

$stages = @(
    [pscustomobject]@{
        Name = "Build"
        ScriptPath = $buildScript
        Skip = $SkipBuild.IsPresent
        Parameters = $buildParams
    },
    [pscustomobject]@{
        Name = "CI"
        ScriptPath = $ciScript
        Skip = $SkipCi.IsPresent
        Parameters = $ciParams
    },
    [pscustomobject]@{
        Name = "Publish"
        ScriptPath = $publishScript
        Skip = $SkipPublish.IsPresent
        Parameters = $publishParams
    },
    [pscustomobject]@{
        Name = "Run"
        ScriptPath = $runScript
        Skip = $SkipRun.IsPresent
        Parameters = $runParams
    }
)

$enabledStages = @($stages | Where-Object { -not $_.Skip })

Write-Host "Running WebAppTemplate pipeline..." -ForegroundColor Cyan
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

Write-Host "`nPipeline complete." -ForegroundColor Green
