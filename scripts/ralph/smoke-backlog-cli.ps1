[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$backlogWrapper = Join-Path -Path $scriptDir -ChildPath "backlog.ps1"
$fixturesDir = Join-Path -Path $scriptDir -ChildPath "testdata/backlog-cli"

$script:TestCount = 0
$script:PassedCount = 0

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

function Assert-ArrayEqual {
    param(
        [Parameter(Mandatory)]
        [object[]]$Actual,
        [Parameter(Mandatory)]
        [object[]]$Expected,
        [Parameter(Mandatory)]
        [string]$Message
    )

    $actualString = ($Actual | ForEach-Object { [string]$_ }) -join ","
    $expectedString = ($Expected | ForEach-Object { [string]$_ }) -join ","
    if ($actualString -ne $expectedString) {
        throw "$Message (expected='$expectedString', actual='$actualString')"
    }
}

function Assert-Contains {
    param(
        [Parameter(Mandatory)]
        [object[]]$Items,
        [Parameter(Mandatory)]
        [string]$ExpectedItem,
        [Parameter(Mandatory)]
        [string]$Message
    )

    $stringItems = @($Items | ForEach-Object { [string]$_ })
    if ($stringItems -notcontains $ExpectedItem) {
        throw "$Message (missing '$ExpectedItem'; actual='$($stringItems -join ",")')"
    }
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

function New-TempDirectory {
    $path = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("ralph-backlog-smoke-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function New-TestWorkspace {
    param(
        [Parameter(Mandatory)]
        [string]$TempRoot
    )

    $workspace = Join-Path -Path $TempRoot -ChildPath ([Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $workspace -Force | Out-Null

    $backlogPath = Join-Path -Path $workspace -ChildPath "backlog.json"
    $schemaPath = Join-Path -Path $workspace -ChildPath "backlog.schema.json"
    Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath ".ralph/backlog.schema.json") -Destination $schemaPath

    return [pscustomobject]@{
        Root = $workspace
        BacklogPath = $backlogPath
        SchemaPath = $schemaPath
    }
}

function Copy-FixtureBacklog {
    param(
        [Parameter(Mandatory)]
        [string]$FixtureName,
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    $fixturePath = Join-Path -Path $fixturesDir -ChildPath $FixtureName
    if (-not (Test-Path -LiteralPath $fixturePath)) {
        throw "Fixture not found: $fixturePath"
    }

    Copy-Item -LiteralPath $fixturePath -Destination $DestinationPath -Force
}

function Assert-ValidationErrorCodes {
    param(
        [Parameter(Mandatory)]
        $ValidateEnvelope,
        [Parameter(Mandatory)]
        [string[]]$ExpectedCodes,
        [Parameter(Mandatory)]
        [string]$MessagePrefix
    )

    Assert-True -Condition (-not [bool]$ValidateEnvelope.ok) -Message "$MessagePrefix should fail"
    Assert-Equal -Actual $ValidateEnvelope.command -Expected "validate" -Message "$MessagePrefix command mismatch"
    Assert-Equal -Actual $ValidateEnvelope.error.code -Expected "BacklogInvalid" -Message "$MessagePrefix top-level error code mismatch"

    $errors = @($ValidateEnvelope.error.details.errors)
    $codes = @($errors | ForEach-Object { [string]$_.code })
    foreach ($expectedCode in $ExpectedCodes) {
        Assert-Contains -Items $codes -ExpectedItem $expectedCode -Message "$MessagePrefix missing validation code"
    }
}

function Invoke-TestCase {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    $script:TestCount++
    Write-Host ("[{0}] {1}" -f $script:TestCount, $Name) -ForegroundColor DarkCyan
    & $ScriptBlock
    $script:PassedCount++
}

function Get-ItemIds {
    param([Parameter(Mandatory)]$Items)
    return @(@($Items) | ForEach-Object { [string]$_.id })
}

$tempDir = $null
try {
    if (-not (Test-Path -LiteralPath $backlogWrapper)) {
        throw "Backlog wrapper script not found: $backlogWrapper"
    }
    if (-not (Test-Path -LiteralPath $fixturesDir)) {
        throw "Fixtures directory not found: $fixturesDir"
    }

    $tempDir = New-TempDirectory
    Write-Host "Ralph Backlog CLI smoke suite (temp root): $tempDir" -ForegroundColor Cyan

    Invoke-TestCase -Name "Base fixture happy path + add/show + description-file" -ScriptBlock {
        $ws = New-TestWorkspace -TempRoot $tempDir
        Copy-FixtureBacklog -FixtureName "valid.base.json" -DestinationPath $ws.BacklogPath

        $validate = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("validate")
        Assert-True -Condition $validate.ok -Message "validate should succeed"
        Assert-Equal -Actual ([int]$validate.data.itemCount) -Expected 2 -Message "base itemCount mismatch"

        $active = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("active")
        Assert-True -Condition (-not [bool]$active.data.found) -Message "base active should be empty"

        $next = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("next")
        Assert-Equal -Actual $next.data.item.id -Expected "task-001" -Message "base next mismatch"
        Assert-Equal -Actual $next.data.item.status -Expected "New" -Message "base next status mismatch"

        $listEligible = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("list", "--eligible", "true")
        Assert-Equal -Actual ([int]$listEligible.data.count) -Expected 1 -Message "base eligible count mismatch"
        Assert-Equal -Actual $listEligible.data.items[0].id -Expected "task-001" -Message "base eligible first item mismatch"

        $showMissing = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("show", "--id", "task-999")
        Assert-True -Condition (-not [bool]$showMissing.data.found) -Message "show missing should return found=false"

        $invalidTransition = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("status", "set", "--id", "task-001", "--to", "Done") -AllowedExitCodes @(1)
        Assert-True -Condition (-not [bool]$invalidTransition.ok) -Message "invalid transition should fail"
        Assert-Equal -Actual $invalidTransition.error.code -Expected "InvalidTransition" -Message "invalid transition error code mismatch"

        $invalidStatus = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("status", "set", "--id", "task-001", "--to", "Bogus") -AllowedExitCodes @(2)
        Assert-True -Condition (-not [bool]$invalidStatus.ok) -Message "invalid status should fail"
        Assert-Equal -Actual $invalidStatus.error.code -Expected "UsageError" -Message "invalid status should return UsageError"

        $missingItem = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("status", "set", "--id", "task-404", "--to", "InProgress") -AllowedExitCodes @(1)
        Assert-True -Condition (-not [bool]$missingItem.ok) -Message "status set missing item should fail"
        Assert-Equal -Actual $missingItem.error.code -Expected "ItemNotFound" -Message "status set missing item error code mismatch"

        $takeNext = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("take-next")
        Assert-Equal -Actual $takeNext.data.item.id -Expected "task-001" -Message "take-next claimed unexpected item"
        Assert-Equal -Actual $takeNext.data.item.status -Expected "InProgress" -Message "take-next status mismatch"
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$takeNext.data.item.startedAt)) -Message "take-next should set startedAt"

        $activeAfterTake = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("active")
        Assert-True -Condition ([bool]$activeAfterTake.data.found) -Message "active should be present after take-next"
        Assert-Equal -Actual $activeAfterTake.data.item.status -Expected "InProgress" -Message "active status mismatch after take-next"

        $toReview = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("status", "set", "--id", "task-001", "--to", "InReview")
        Assert-Equal -Actual $toReview.data.item.status -Expected "InReview" -Message "status -> InReview mismatch"

        $toDone = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("status", "set", "--id", "task-001", "--to", "Done")
        Assert-Equal -Actual $toDone.data.item.status -Expected "Done" -Message "status -> Done mismatch"
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$toDone.data.item.doneAt)) -Message "Done should set doneAt"

        $nextAfterDone = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("next")
        Assert-Equal -Actual $nextAfterDone.data.item.id -Expected "task-002" -Message "next after dependency completion mismatch"

        $addInline = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @(
            "add",
            "--id", "task-010",
            "--title", "Smoke add inline",
            "--description", "Added by smoke test.",
            "--priority", "5",
            "--depends", "task-002"
        )
        Assert-Equal -Actual $addInline.data.item.id -Expected "task-010" -Message "add inline returned unexpected id"
        Assert-Equal -Actual $addInline.data.item.status -Expected "New" -Message "add inline should create New item"

        $descFile = Join-Path -Path $ws.Root -ChildPath "desc.txt"
        Set-Content -LiteralPath $descFile -Value "Description from file"
        $addFromFile = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @(
            "add",
            "--id", "task-011",
            "--title", "Smoke add file",
            "--description-file", $descFile,
            "--priority", "6"
        )
        Assert-Equal -Actual $addFromFile.data.item.description.Trim() -Expected "Description from file" -Message "add description-file mismatch"

        $duplicateAdd = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @(
            "add",
            "--id", "task-011",
            "--title", "Duplicate",
            "--description", "dup",
            "--priority", "1"
        ) -AllowedExitCodes @(1)
        Assert-True -Condition (-not [bool]$duplicateAdd.ok) -Message "duplicate add should fail"
        Assert-Equal -Actual $duplicateAdd.error.code -Expected "BacklogInvalid" -Message "duplicate add top-level code mismatch"

        $showAdded = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("show", "--id", "task-011")
        Assert-True -Condition ([bool]$showAdded.data.found) -Message "show should find item added via description-file"
        Assert-Equal -Actual $showAdded.data.item.id -Expected "task-011" -Message "show added item mismatch"
    }

    Invoke-TestCase -Name "Ordering, priority, tie-break, and eligibility filters" -ScriptBlock {
        $ws = New-TestWorkspace -TempRoot $tempDir
        Copy-FixtureBacklog -FixtureName "valid.ordering.json" -DestinationPath $ws.BacklogPath

        $validate = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("validate")
        Assert-True -Condition $validate.ok -Message "ordering validate should succeed"

        $next = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("next")
        Assert-Equal -Actual $next.data.item.id -Expected "task-b" -Message "next should select highest priority / id tie-break"

        $eligible = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("list", "--eligible", "true")
        Assert-Equal -Actual ([int]$eligible.data.count) -Expected 3 -Message "eligible count mismatch"
        Assert-ArrayEqual -Actual (Get-ItemIds -Items $eligible.data.items) -Expected @("task-b", "task-c", "task-a") -Message "eligible order mismatch"

        $notEligible = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("list", "--eligible", "false", "--status", "New")
        Assert-Equal -Actual ([int]$notEligible.data.count) -Expected 1 -Message "not-eligible New count mismatch"
        Assert-Equal -Actual $notEligible.data.items[0].id -Expected "task-d" -Message "blocked task mismatch"

        $doneOnly = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("list", "--status", "Done")
        Assert-Equal -Actual ([int]$doneOnly.data.count) -Expected 1 -Message "done filter count mismatch"
        Assert-Equal -Actual $doneOnly.data.items[0].id -Expected "task-zdone" -Message "done filter item mismatch"
    }

    Invoke-TestCase -Name "Active InProgress backlog blocks take-next" -ScriptBlock {
        $ws = New-TestWorkspace -TempRoot $tempDir
        Copy-FixtureBacklog -FixtureName "valid.active-inprogress.json" -DestinationPath $ws.BacklogPath

        $active = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("active")
        Assert-True -Condition ([bool]$active.data.found) -Message "active should be found"
        Assert-Equal -Actual $active.data.item.id -Expected "task-active" -Message "active item id mismatch"
        Assert-Equal -Actual $active.data.item.status -Expected "InProgress" -Message "active item status mismatch"

        $takeNext = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("take-next") -AllowedExitCodes @(1)
        Assert-True -Condition (-not [bool]$takeNext.ok) -Message "take-next should fail when active item exists"
        Assert-Equal -Actual $takeNext.error.code -Expected "ActiveItemExists" -Message "take-next active-item error code mismatch"
    }

    Invoke-TestCase -Name "Active InReview supports repair round-trip transitions" -ScriptBlock {
        $ws = New-TestWorkspace -TempRoot $tempDir
        Copy-FixtureBacklog -FixtureName "valid.active-inreview.json" -DestinationPath $ws.BacklogPath

        $active = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("active")
        Assert-Equal -Actual $active.data.item.status -Expected "InReview" -Message "active InReview fixture status mismatch"
        $originalStartedAt = [string]$active.data.item.startedAt

        $toProgress = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("status", "set", "--id", "task-review", "--to", "InProgress")
        Assert-Equal -Actual $toProgress.data.item.status -Expected "InProgress" -Message "InReview -> InProgress should be allowed"
        Assert-Equal -Actual ([string]$toProgress.data.item.startedAt) -Expected $originalStartedAt -Message "startedAt should be preserved during repair transition"

        $backToReview = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("status", "set", "--id", "task-review", "--to", "InReview")
        Assert-Equal -Actual $backToReview.data.item.status -Expected "InReview" -Message "InProgress -> InReview should be allowed"

        $toDone = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("status", "set", "--id", "task-review", "--to", "Done")
        Assert-Equal -Actual $toDone.data.item.status -Expected "Done" -Message "InReview -> Done should be allowed"
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$toDone.data.item.doneAt)) -Message "Done should set doneAt"
    }

    Invoke-TestCase -Name "Done-only backlog returns no eligible items" -ScriptBlock {
        $ws = New-TestWorkspace -TempRoot $tempDir
        Copy-FixtureBacklog -FixtureName "valid.done-only.json" -DestinationPath $ws.BacklogPath

        $next = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("next")
        Assert-True -Condition (-not [bool]$next.data.found) -Message "next should return found=false for done-only backlog"

        $takeNext = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("take-next")
        Assert-True -Condition $takeNext.ok -Message "take-next should succeed with no eligible items"
        Assert-True -Condition (-not [bool]$takeNext.data.found) -Message "take-next should return found=false for done-only backlog"
        Assert-Equal -Actual $takeNext.data.reason -Expected "NoEligibleItems" -Message "take-next no-eligible reason mismatch"

        $listDone = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("list", "--status", "Done")
        Assert-Equal -Actual ([int]$listDone.data.count) -Expected 2 -Message "done-only list count mismatch"
    }

    $validationCases = @(
        @{ Fixture = "invalid.missing-description.json"; Codes = @("SchemaViolation"); Name = "Schema violation: missing description" },
        @{ Fixture = "invalid.dependency-cycle.json"; Codes = @("DependencyCycle"); Name = "Runtime violation: dependency cycle" },
        @{ Fixture = "invalid.missing-dependency.json"; Codes = @("MissingDependency"); Name = "Runtime violation: missing dependency" },
        @{ Fixture = "invalid.two-active.json"; Codes = @("TooManyActiveItems"); Name = "Runtime violation: too many active items" },
        @{ Fixture = "invalid.status-timestamps.json"; Codes = @("InvalidTimestampsForStatus"); Name = "Runtime violation: invalid timestamps" },
        @{ Fixture = "invalid.duplicate-id.json"; Codes = @("DuplicateId"); Name = "Runtime violation: duplicate ids" },
        @{ Fixture = "invalid.self-dependency.json"; Codes = @("SelfDependency"); Name = "Runtime violation: self dependency" }
    )

    foreach ($case in $validationCases) {
        Invoke-TestCase -Name $case.Name -ScriptBlock {
            $ws = New-TestWorkspace -TempRoot $tempDir
            Copy-FixtureBacklog -FixtureName ([string]$case.Fixture) -DestinationPath $ws.BacklogPath
            $validate = Invoke-BacklogJson -BacklogPath $ws.BacklogPath -SchemaPath $ws.SchemaPath -Arguments @("validate") -AllowedExitCodes @(1)
            Assert-ValidationErrorCodes -ValidateEnvelope $validate -ExpectedCodes ([string[]]$case.Codes) -MessagePrefix ([string]$case.Name)
        }
    }

    Write-Host ("Ralph Backlog CLI smoke suite passed ({0}/{0} cases)." -f $script:PassedCount) -ForegroundColor Green
}
finally {
    if ($null -ne $tempDir -and (Test-Path -LiteralPath $tempDir)) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}

