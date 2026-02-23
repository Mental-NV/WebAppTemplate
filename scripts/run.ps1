# Run script for WebAppTemplate published app
# Publishes (by default) and runs API + SPA as a single unit from the publish folder

param(
    [string]$Configuration = "Release",
    [string]$PublishOutputDir = "artifacts/publish/app",
    [string]$DbFilePath = "",
    [switch]$NoPublish,
    [string]$SecretsFile = "scripts/secrets.local.ps1",
    [string]$Environment = "Development",
    [int]$HttpPort = 5000,
    [int]$HttpsPort = 5001,
    [switch]$CI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path -Path $PSScriptRoot -ChildPath "common.ps1")

$paths = Get-RepoPaths
$effectiveCi = Get-EffectiveCiMode -CiSwitch:$CI
$platform = Get-PlatformLabel

$resolvedPublishOutputDir = $PublishOutputDir
if (-not [System.IO.Path]::IsPathRooted($resolvedPublishOutputDir)) {
    $resolvedPublishOutputDir = Join-Path -Path $paths.ProjectRoot -ChildPath $resolvedPublishOutputDir
}

$publishScript = Join-Path -Path $PSScriptRoot -ChildPath "publish.ps1"
$apiDllPath = Join-Path -Path $resolvedPublishOutputDir -ChildPath "Api.dll"
$spaIndexPath = Join-Path -Path (Join-Path -Path $resolvedPublishOutputDir -ChildPath "wwwroot") -ChildPath "index.html"

Write-Host "Running published WebAppTemplate..." -ForegroundColor Cyan
Write-Host "Platform: $platform | CI: $effectiveCi | Configuration: $Configuration" -ForegroundColor Gray
Write-Host "Publish output: $resolvedPublishOutputDir" -ForegroundColor Gray

$step = 0
$totalSteps = 6

$step++
Write-Host "`n[$step/$totalSteps] Loading secrets..." -ForegroundColor Yellow
[void](Import-OptionalSecretsFile -ProjectRoot $paths.ProjectRoot -SecretsFile $SecretsFile)
[void](Initialize-HttpsCertificateMaterialization -ProjectRoot $paths.ProjectRoot -Required)

$step++
Write-Host "`n[$step/$totalSteps] Preflight checks..." -ForegroundColor Yellow
Assert-CommandAvailable -Name "dotnet"
if (-not $NoPublish.IsPresent) {
    Assert-CommandAvailable -Name "pwsh"
}

$step++
Write-Host "`n[$step/$totalSteps] Preparing publish artifact..." -ForegroundColor Yellow
if ($NoPublish.IsPresent) {
    Write-Host "Skipping publish (-NoPublish)." -ForegroundColor DarkGray
}
else {
    $publishArgs = @(
        "-NoLogo",
        "-NoProfile",
        "-File", $publishScript,
        "-Configuration", $Configuration,
        "-OutputDir", $resolvedPublishOutputDir,
        "-SecretsFile", $SecretsFile
    )
    if ($CI.IsPresent) {
        $publishArgs += "-CI"
    }

    Invoke-External -FilePath "pwsh" -Arguments $publishArgs -WorkingDirectory $paths.ProjectRoot -StepName "publish.ps1"
}

$step++
Write-Host "`n[$step/$totalSteps] Validating publish artifact and required runtime secrets..." -ForegroundColor Yellow
if (-not (Test-Path -LiteralPath $apiDllPath)) {
    throw "Api.dll was not found in publish output: $apiDllPath"
}
if (-not (Test-Path -LiteralPath $spaIndexPath)) {
    throw "SPA index.html was not found in publish output: $spaIndexPath"
}

Assert-RequiredEnvVarValues -Names @(
    "ASPNETCORE_Kestrel__Certificates__Default__Path",
    "ASPNETCORE_Kestrel__Certificates__Default__Password",
    "Google__ClientId",
    "Jwt__SigningKey"
)

Assert-EnvVarNotPlaceholder -Name "ASPNETCORE_Kestrel__Certificates__Default__Path" -PlaceholderPrefixes @("REPLACE_ME")
Assert-EnvVarNotPlaceholder -Name "ASPNETCORE_Kestrel__Certificates__Default__Password" -PlaceholderPrefixes @("REPLACE_ME")
Assert-EnvVarNotPlaceholder -Name "Google__ClientId" -PlaceholderPrefixes @("REPLACE_ME")
Assert-EnvVarNotPlaceholder -Name "Jwt__SigningKey" -PlaceholderPrefixes @("REPLACE_ME")

$certPath = [Environment]::GetEnvironmentVariable("ASPNETCORE_Kestrel__Certificates__Default__Path")
if (-not [System.IO.Path]::IsPathRooted($certPath)) {
    $certPath = Join-Path -Path $paths.ProjectRoot -ChildPath $certPath
}
if (-not (Test-Path -LiteralPath $certPath)) {
    throw "HTTPS certificate file not found: $certPath"
}
[Environment]::SetEnvironmentVariable("ASPNETCORE_Kestrel__Certificates__Default__Path", $certPath)

$step++
Write-Host "`n[$step/$totalSteps] Configuring runtime environment..." -ForegroundColor Yellow
[Environment]::SetEnvironmentVariable("ASPNETCORE_ENVIRONMENT", $Environment)
[Environment]::SetEnvironmentVariable("ASPNETCORE_URLS", "http://localhost:$HttpPort;https://localhost:$HttpsPort")

$connectionStringFromEnv = [Environment]::GetEnvironmentVariable("ConnectionStrings__Default")
if ([string]::IsNullOrWhiteSpace($connectionStringFromEnv)) {
    $resolvedDbFilePath = $DbFilePath
    if ([string]::IsNullOrWhiteSpace($resolvedDbFilePath)) {
        $stableAppDataDir = Get-StablePerUserAppDataDir -AppName "WebAppTemplate"
        $resolvedDbFilePath = Join-Path -Path (Join-Path -Path $stableAppDataDir -ChildPath "AppData") -ChildPath "app.db"
    }
    elseif (-not [System.IO.Path]::IsPathRooted($resolvedDbFilePath)) {
        $resolvedDbFilePath = Join-Path -Path $paths.ProjectRoot -ChildPath $resolvedDbFilePath
    }

    $dbDir = Split-Path -Parent $resolvedDbFilePath
    if (-not [string]::IsNullOrWhiteSpace($dbDir)) {
        New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
    }

    [Environment]::SetEnvironmentVariable("ConnectionStrings__Default", "Data Source=$resolvedDbFilePath")
    $connectionStringFromEnv = [Environment]::GetEnvironmentVariable("ConnectionStrings__Default")
}

Write-Host "ASPNETCORE_ENVIRONMENT=$Environment" -ForegroundColor Gray
Write-Host "ASPNETCORE_URLS=$([Environment]::GetEnvironmentVariable('ASPNETCORE_URLS'))" -ForegroundColor Gray
Write-Host "HTTPS cert path=$certPath" -ForegroundColor Gray
Write-Host "ConnectionStrings__Default=$connectionStringFromEnv" -ForegroundColor Gray

$step++
Write-Host "`n[$step/$totalSteps] Starting published app..." -ForegroundColor Yellow
Invoke-External -FilePath "dotnet" -Arguments @("./Api.dll") -WorkingDirectory $resolvedPublishOutputDir -StepName "dotnet Api.dll"
