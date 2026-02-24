[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$backlogWrapper = Join-Path -Path $scriptDir -ChildPath "backlog.ps1"

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,
        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        $Actual,
        [Parameter(Mandatory)]
        $Expected,
        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message (expected='$Expected', actual='$Actual')"
    }
}

function Invoke-BacklogJson {
    param(
        [Parameter(Mandatory)]
        [string]$BacklogPath,
        [Parameter(Mandatory)]
        [string]$SchemaPath,
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [int[]]$AllowedExitCodes = @(0)
    )

    $outputLines = & $backlogWrapper -BacklogPath $BacklogPath -SchemaPath $SchemaPath @Arguments
    $exitCode = $LASTEXITCODE

    if ($AllowedExitCodes -notcontains $exitCode) {
        throw "Backlog CLI failed with exit code $exitCode for args: $($Arguments -join ' ')"
    }

    $output = [string]($outputLines | Out-String)
    if ([string]::IsNullOrWhiteSpace($output)) {
        throw "Backlog CLI returned no JSON output for args: $($Arguments -join ' ')"
    }

    $jsonText = Get-TrailingJsonObject -Text $output
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        throw "Backlog CLI returned no trailing JSON object for args: $($Arguments -join ' '). Raw output: $output"
    }

    try {
        $json = $jsonText | ConvertFrom-Json -Depth 100
    }
    catch {
        throw "Backlog CLI returned invalid JSON for args: $($Arguments -join ' '). Raw output: $output"
    }

    $json | Add-Member -NotePropertyName exitCode -NotePropertyValue $exitCode -Force
    return $json
}

function Get-TrailingJsonObject {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $lines = @($Text -split "`r?`n")
    $startLineIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].TrimStart().StartsWith("{", [System.StringComparison]::Ordinal)) {
            $startLineIndex = $i
            break
        }
    }

    if ($startLineIndex -lt 0) {
        return $null
    }

    return (($lines[$startLineIndex..($lines.Count - 1)]) -join [Environment]::NewLine).Trim()
}

function New-TempDirectory {
    $path = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("ralph-backlog-smoke-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

$tempDir = $null
try {
    if (-not (Test-Path -LiteralPath $backlogWrapper)) {
        throw "Backlog wrapper script not found: $backlogWrapper"
    }

    $tempDir = New-TempDirectory
    $tempBacklog = Join-Path -Path $tempDir -ChildPath "backlog.json"
    $tempSchema = Join-Path -Path $tempDir -ChildPath "backlog.schema.json"

    Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath ".ralph/backlog.json") -Destination $tempBacklog
    Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath ".ralph/backlog.schema.json") -Destination $tempSchema

    Write-Host "Ralph Backlog CLI smoke test (temp copy): $tempDir" -ForegroundColor Cyan

    $validate = Invoke-BacklogJson -BacklogPath $tempBacklog -SchemaPath $tempSchema -Arguments @("validate")
    Assert-True -Condition $validate.ok -Message "validate should succeed"
    Assert-Equal -Actual $validate.command -Expected "validate" -Message "validate command name mismatch"
    Assert-Equal -Actual ([int]$validate.data.version) -Expected 1 -Message "validate.version mismatch"
    Assert-Equal -Actual ([int]$validate.data.itemCount) -Expected 2 -Message "validate.itemCount mismatch"

    $active = Invoke-BacklogJson -BacklogPath $tempBacklog -SchemaPath $tempSchema -Arguments @("active")
    Assert-True -Condition $active.ok -Message "active should succeed"
    Assert-True -Condition (-not [bool]$active.data.found) -Message "active should report found=false initially"

    $next = Invoke-BacklogJson -BacklogPath $tempBacklog -SchemaPath $tempSchema -Arguments @("next")
    Assert-True -Condition $next.ok -Message "next should succeed"
    Assert-True -Condition ([bool]$next.data.found) -Message "next should return an item"
    Assert-Equal -Actual $next.data.item.id -Expected "task-001" -Message "next should return task-001 first"
    Assert-Equal -Actual $next.data.item.status -Expected "New" -Message "next item status should be New"

    $listEligible = Invoke-BacklogJson -BacklogPath $tempBacklog -SchemaPath $tempSchema -Arguments @("list", "--eligible", "true")
    Assert-True -Condition $listEligible.ok -Message "list --eligible should succeed"
    Assert-Equal -Actual ([int]$listEligible.data.count) -Expected 1 -Message "eligible list count mismatch"
    Assert-Equal -Actual $listEligible.data.items[0].id -Expected "task-001" -Message "eligible list first item mismatch"

    $invalidTransition = Invoke-BacklogJson -BacklogPath $tempBacklog -SchemaPath $tempSchema -Arguments @("status", "set", "--id", "task-001", "--to", "Done") -AllowedExitCodes @(1)
    Assert-True -Condition (-not [bool]$invalidTransition.ok) -Message "invalid transition should fail"
    Assert-Equal -Actual $invalidTransition.error.code -Expected "InvalidTransition" -Message "invalid transition error code mismatch"

    $takeNext = Invoke-BacklogJson -BacklogPath $tempBacklog -SchemaPath $tempSchema -Arguments @("take-next")
    Assert-True -Condition $takeNext.ok -Message "take-next should succeed"
    Assert-True -Condition ([bool]$takeNext.data.found) -Message "take-next should claim an item"
    Assert-Equal -Actual $takeNext.data.item.id -Expected "task-001" -Message "take-next claimed unexpected item"
    Assert-Equal -Actual $takeNext.data.item.status -Expected "InProgress" -Message "take-next should set InProgress"
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$takeNext.data.item.startedAt)) -Message "take-next should set startedAt"

    $activeAfterTake = Invoke-BacklogJson -BacklogPath $tempBacklog -SchemaPath $tempSchema -Arguments @("active")
    Assert-True -Condition ([bool]$activeAfterTake.data.found) -Message "active should report found=true after take-next"
    Assert-Equal -Actual $activeAfterTake.data.item.status -Expected "InProgress" -Message "active status should be InProgress after take-next"

    $toReview = Invoke-BacklogJson -BacklogPath $tempBacklog -SchemaPath $tempSchema -Arguments @("status", "set", "--id", "task-001", "--to", "InReview")
    Assert-True -Condition $toReview.ok -Message "status set -> InReview should succeed"
    Assert-Equal -Actual $toReview.data.item.status -Expected "InReview" -Message "status should be InReview"

    $toDone = Invoke-BacklogJson -BacklogPath $tempBacklog -SchemaPath $tempSchema -Arguments @("status", "set", "--id", "task-001", "--to", "Done")
    Assert-True -Condition $toDone.ok -Message "status set -> Done should succeed"
    Assert-Equal -Actual $toDone.data.item.status -Expected "Done" -Message "status should be Done"
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$toDone.data.item.doneAt)) -Message "Done should set doneAt"

    $nextAfterDone = Invoke-BacklogJson -BacklogPath $tempBacklog -SchemaPath $tempSchema -Arguments @("next")
    Assert-True -Condition ([bool]$nextAfterDone.data.found) -Message "next should return task-002 after task-001 done"
    Assert-Equal -Actual $nextAfterDone.data.item.id -Expected "task-002" -Message "next should return task-002 after dependency completion"

    $add = Invoke-BacklogJson -BacklogPath $tempBacklog -SchemaPath $tempSchema -Arguments @(
        "add",
        "--id", "task-010",
        "--title", "Smoke add command",
        "--description", "Added by smoke test.",
        "--priority", "5",
        "--depends", "task-002"
    )
    Assert-True -Condition $add.ok -Message "add should succeed"
    Assert-Equal -Actual $add.data.item.id -Expected "task-010" -Message "add returned unexpected id"
    Assert-Equal -Actual $add.data.item.description -Expected "Added by smoke test." -Message "add returned unexpected description"
    Assert-Equal -Actual $add.data.item.status -Expected "New" -Message "add should create New item"

    $showAdded = Invoke-BacklogJson -BacklogPath $tempBacklog -SchemaPath $tempSchema -Arguments @("show", "--id", "task-010")
    Assert-True -Condition $showAdded.ok -Message "show should succeed"
    Assert-True -Condition ([bool]$showAdded.data.found) -Message "show should find added item"
    Assert-Equal -Actual $showAdded.data.item.id -Expected "task-010" -Message "show returned unexpected item"

    Write-Host "Ralph Backlog CLI smoke test passed." -ForegroundColor Green
}
finally {
    if ($null -ne $tempDir -and (Test-Path -LiteralPath $tempDir)) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}
