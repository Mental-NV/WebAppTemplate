Set-StrictMode -Version Latest

function Test-TruthyEnvVar {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $false
    }

    switch ($value.Trim().ToLowerInvariant()) {
        "1" { return $true }
        "true" { return $true }
        "yes" { return $true }
        "on" { return $true }
        default { return $false }
    }
}

function Get-EffectiveCiMode {
    param(
        [switch]$CiSwitch
    )

    if ($CiSwitch.IsPresent) {
        return $true
    }

    return (Test-TruthyEnvVar -Name "GITHUB_ACTIONS") -or (Test-TruthyEnvVar -Name "CI")
}

function Assert-CommandAvailable {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found on PATH."
    }
}

function Get-PlatformLabel {
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        return "Windows"
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) {
        return "Linux"
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
        return "macOS"
    }

    return [string]$PSVersionTable.Platform
}

function Get-StablePerUserAppDataDir {
    param(
        [Parameter(Mandatory)]
        [string]$AppName
    )

    $baseDir = [Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($baseDir)) {
        $baseDir = [Environment]::GetEnvironmentVariable("HOME")
    }
    if ([string]::IsNullOrWhiteSpace($baseDir)) {
        $baseDir = [Environment]::GetEnvironmentVariable("USERPROFILE")
    }
    if ([string]::IsNullOrWhiteSpace($baseDir)) {
        throw "Could not determine a stable per-user application data directory."
    }

    return (Join-Path -Path $baseDir -ChildPath $AppName)
}

function Format-CommandForDisplay {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @()
    )

    $parts = @($FilePath)
    foreach ($arg in $Arguments) {
        if ($arg -match '\s|"') {
            $escaped = $arg -replace '"', '\"'
            $parts += """$escaped"""
        }
        else {
            $parts += $arg
        }
    }

    return ($parts -join " ")
}

function Invoke-External {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [string]$WorkingDirectory,

        [string]$StepName
    )

    $display = Format-CommandForDisplay -FilePath $FilePath -Arguments $Arguments
    Write-Host ">> $display" -ForegroundColor DarkGray

    $pushed = $false
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        Push-Location -LiteralPath $WorkingDirectory
        $pushed = $true
    }

    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            $name = if ([string]::IsNullOrWhiteSpace($StepName)) { $FilePath } else { $StepName }
            throw "$name failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        if ($pushed) {
            Pop-Location
        }
    }
}

function Get-RepoPaths {
    $scriptsDir = $PSScriptRoot
    $projectRoot = Split-Path -Parent $scriptsDir
    $srcDir = Join-Path -Path $projectRoot -ChildPath "src"
    $testsDir = Join-Path -Path $projectRoot -ChildPath "tests"
    $apiDir = Join-Path -Path $srcDir -ChildPath "api"
    $webDir = Join-Path -Path $srcDir -ChildPath "web"

    [pscustomobject]@{
        ScriptsDir               = $scriptsDir
        ProjectRoot              = $projectRoot
        SolutionPath             = Join-Path -Path $projectRoot -ChildPath "AppTemplate.sln"
        SrcDir                   = $srcDir
        TestsDir                 = $testsDir
        ApiDir                   = $apiDir
        ApiProjectPath           = Join-Path -Path $apiDir -ChildPath "Api.csproj"
        ApiWwwRootDir            = Join-Path -Path $apiDir -ChildPath "wwwroot"
        WebDir                   = $webDir
        WebDistDir               = Join-Path -Path $webDir -ChildPath "dist"
        WebPackageLockPath       = Join-Path -Path $webDir -ChildPath "package-lock.json"
        ApiUnitTestsProjectPath  = Join-Path -Path (Join-Path -Path $testsDir -ChildPath "Api.UnitTests") -ChildPath "Api.UnitTests.csproj"
        ApiTestsProjectPath      = Join-Path -Path (Join-Path -Path $testsDir -ChildPath "Api.Tests") -ChildPath "Api.Tests.csproj"
    }
}

function Resolve-ProjectRelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return (Join-Path -Path $ProjectRoot -ChildPath $Path)
}

function Get-PublishArtifactPaths {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$OutputDir
    )

    $resolvedOutputDir = Resolve-ProjectRelativePath -ProjectRoot $ProjectRoot -Path $OutputDir
    $publishWwwRootDir = Join-Path -Path $resolvedOutputDir -ChildPath "wwwroot"

    return [pscustomobject]@{
        OutputDir        = $resolvedOutputDir
        PublishWwwRootDir = $publishWwwRootDir
        ApiDllPath       = Join-Path -Path $resolvedOutputDir -ChildPath "Api.dll"
        SpaIndexPath     = Join-Path -Path $publishWwwRootDir -ChildPath "index.html"
    }
}

function Assert-PublishArtifact {
    param(
        [Parameter(Mandatory)]
        [string]$PublishOutputDir,

        [Parameter(Mandatory)]
        [string]$ApiDllPath,

        [Parameter(Mandatory)]
        [string]$SpaIndexPath
    )

    if (-not (Test-Path -LiteralPath $PublishOutputDir)) {
        throw "Publish output directory not found: $PublishOutputDir"
    }
    if (-not (Test-Path -LiteralPath $ApiDllPath)) {
        throw "Publish validation failed: Api.dll was not found at '$ApiDllPath'."
    }
    if (-not (Test-Path -LiteralPath $SpaIndexPath)) {
        throw "Publish validation failed: SPA index.html was not found at '$SpaIndexPath'."
    }
}

function Import-OptionalSecretsFile {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$SecretsFile
    )

    $resolvedPath = Resolve-ProjectRelativePath -ProjectRoot $ProjectRoot -Path $SecretsFile

    if (Test-Path -LiteralPath $resolvedPath) {
        Write-Host "Loading secrets from $resolvedPath" -ForegroundColor Gray
        . $resolvedPath
        return $resolvedPath
    }

    Write-Host "Secrets file not found (optional): $resolvedPath" -ForegroundColor DarkGray
    return $null
}

function Initialize-HttpsCertificateMaterialization {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [switch]$Required,

        [string]$Base64EnvVarName = "HTTPS_CERT_PFX_BASE64",

        [string]$PasswordEnvVarName = "HTTPS_CERT_PASSWORD",

        [string]$DefaultRelativeOutputPath = ".certs/webapptemplate-dev.pfx"
    )

    $base64Value = [Environment]::GetEnvironmentVariable($Base64EnvVarName)
    $passwordValue = [Environment]::GetEnvironmentVariable($PasswordEnvVarName)

    $hasBase64 = -not [string]::IsNullOrWhiteSpace($base64Value)
    $hasPassword = -not [string]::IsNullOrWhiteSpace($passwordValue)

    if (-not $hasBase64 -and -not $hasPassword) {
        if ($Required.IsPresent) {
            throw "HTTPS certificate materialization requires '$Base64EnvVarName' and '$PasswordEnvVarName'."
        }

        Write-Host "HTTPS certificate materialization skipped: '$Base64EnvVarName'/'$PasswordEnvVarName' are not set." -ForegroundColor DarkGray
        return $null
    }

    if (-not $hasBase64 -or -not $hasPassword) {
        throw "HTTPS certificate materialization requires both '$Base64EnvVarName' and '$PasswordEnvVarName'."
    }

    $targetPath = Resolve-ProjectRelativePath -ProjectRoot $ProjectRoot -Path $DefaultRelativeOutputPath

    $targetDir = Split-Path -Parent $targetPath
    if (-not [string]::IsNullOrWhiteSpace($targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    try {
        $bytes = [Convert]::FromBase64String($base64Value.Trim())
    }
    catch {
        throw "Failed to decode '$Base64EnvVarName' as base64. $($_.Exception.Message)"
    }

    [System.IO.File]::WriteAllBytes($targetPath, $bytes)
    [Environment]::SetEnvironmentVariable("ASPNETCORE_Kestrel__Certificates__Default__Path", $targetPath)
    [Environment]::SetEnvironmentVariable("ASPNETCORE_Kestrel__Certificates__Default__Password", $passwordValue)

    Write-Host "Materialized HTTPS certificate to $targetPath" -ForegroundColor Gray

    return [pscustomobject]@{
        Path               = $targetPath
        Password           = $passwordValue
        SourceEnvVarName   = $Base64EnvVarName
        PasswordEnvVarName = $PasswordEnvVarName
    }
}

function Install-WebDependencies {
    param(
        [Parameter(Mandatory)]
        [string]$WebDir,

        [Parameter(Mandatory)]
        [string]$LockFilePath,

        [switch]$UseNpmInstall
    )

    if ($UseNpmInstall.IsPresent) {
        Invoke-External -FilePath "npm" -Arguments @("install") -WorkingDirectory $WebDir -StepName "npm install"
        return
    }

    $effectiveCi = Get-EffectiveCiMode

    if (-not $effectiveCi) {
        Invoke-External -FilePath "npm" -Arguments @("install") -WorkingDirectory $WebDir -StepName "npm install"
        return
    }

    if (Test-Path -LiteralPath $LockFilePath) {
        Invoke-External -FilePath "npm" -Arguments @("ci") -WorkingDirectory $WebDir -StepName "npm ci"
        return
    }

    Write-Host "package-lock.json not found; falling back to npm install." -ForegroundColor Yellow
    Invoke-External -FilePath "npm" -Arguments @("install") -WorkingDirectory $WebDir -StepName "npm install"
}

function Sync-DirectoryContents {
    param(
        [Parameter(Mandatory)]
        [string]$SourceDir,

        [Parameter(Mandatory)]
        [string]$DestinationDir,

        [switch]$CleanDestination,

        [string[]]$PreserveNames = @()
    )

    if (-not (Test-Path -LiteralPath $SourceDir)) {
        throw "Source directory not found: $SourceDir"
    }

    if (-not (Test-Path -LiteralPath $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    if ($CleanDestination.IsPresent) {
        Get-ChildItem -LiteralPath $DestinationDir -Force | ForEach-Object {
            if ($PreserveNames -contains $_.Name) {
                return
            }

            Remove-Item -LiteralPath $_.FullName -Recurse -Force
        }
    }

    Get-ChildItem -LiteralPath $SourceDir -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $DestinationDir -Recurse -Force
    }
}

function Assert-RequiredEnvVarValues {
    param(
        [Parameter(Mandatory)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Required environment variable '$name' is missing or empty."
        }
    }
}

function Assert-EnvVarNotPlaceholder {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string[]]$PlaceholderPrefixes
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Required environment variable '$Name' is missing or empty."
    }

    foreach ($prefix in $PlaceholderPrefixes) {
        if ($value.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Environment variable '$Name' is still set to a placeholder value."
        }
    }
}
