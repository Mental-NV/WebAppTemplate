param(
    [string]$ConfigPath = ".ralph/config.json",
    [switch]$Once,
    [switch]$ResumeOnly,
    [switch]$NoMerge,
    [switch]$CI,
    [int]$PollIntervalSeconds = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path -Path $PSScriptRoot -ChildPath "common.ps1")

$script:RalphLockHandle = $null
$script:RalphRunId = $null
$script:RalphConfig = $null
$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$worktreePath = $null
$script:RalphStepCounter = 0

function Resolve-RalphPath {
    param(
        [Parameter(Mandatory)]
        [string]$PathValue
    )

    return (Resolve-ProjectRelativePath -ProjectRoot $script:RepoRoot -Path $PathValue)
}

function Acquire-RalphLock {
    $lockPath = Resolve-RalphPath -PathValue ".ralph/ralph.loop.lock"
    $lockDir = Split-Path -Parent $lockPath
    if (-not [string]::IsNullOrWhiteSpace($lockDir)) {
        New-Item -ItemType Directory -Force -Path $lockDir | Out-Null
    }

    $script:RalphLockHandle = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
}

function Release-RalphLock {
    if ($null -ne $script:RalphLockHandle) {
        $script:RalphLockHandle.Dispose()
        $script:RalphLockHandle = $null
    }
}

function Get-OrCreateRunId {
    if (-not [string]::IsNullOrWhiteSpace($script:RalphRunId)) {
        return $script:RalphRunId
    }

    $script:RalphRunId = [DateTimeOffset]::UtcNow.ToString("yyyyMMdd-HHmmssZ")
    return $script:RalphRunId
}

function Invoke-BacklogCliJson {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $commandPrefix = [string]$script:RalphConfig.backlogCliCommand
    if ([string]::IsNullOrWhiteSpace($commandPrefix)) {
        throw "config.backlogCliCommand is not configured."
    }

    # v1 supports the configured prefix format from .ralph/config.json using simple whitespace splitting.
    $prefixParts = [regex]::Split($commandPrefix.Trim(), "\s+") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($prefixParts.Count -eq 0) {
        throw "config.backlogCliCommand is invalid."
    }

    $fullArgs = @()
    if ($prefixParts.Count -gt 1) {
        $fullArgs += $prefixParts[1..($prefixParts.Count - 1)]
    }

    $fullArgs += $Arguments

    if ($fullArgs -notcontains "--backlog") {
        $fullArgs += @("--backlog", [string]$script:RalphConfig.backlogPath)
    }
    if ($fullArgs -notcontains "--schema") {
        $fullArgs += @("--schema", [string]$script:RalphConfig.schemaPath)
    }
    if ($fullArgs -notcontains "--json") {
        $fullArgs += @("--json")
    }

    $rawLines = & $prefixParts[0] @fullArgs
    $exitCode = $LASTEXITCODE
    $raw = [string]($rawLines | Out-String)

    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Backlog CLI returned no output (exit code $exitCode) for args: $($Arguments -join ' ')"
    }

    $jsonText = Get-TrailingJsonObject -Text $raw
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        throw "Backlog CLI returned no trailing JSON object (exit code $exitCode) for args: $($Arguments -join ' ')"
    }

    try {
        $obj = $jsonText | ConvertFrom-Json -Depth 100
    }
    catch {
        throw "Backlog CLI returned non-JSON output (exit code $exitCode): $raw"
    }

    $obj | Add-Member -NotePropertyName exitCode -NotePropertyValue $exitCode -Force
    return $obj
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

function Invoke-GhJson {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [int[]]$AllowedExitCodes = @(0),
        [switch]$AllowPlainTextFallback
    )

    $outputLines = & gh @Arguments
    $exitCode = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exitCode) {
        throw "gh $($Arguments -join ' ') failed with exit code $exitCode."
    }

    $output = [string]($outputLines | Out-String)
    if ([string]::IsNullOrWhiteSpace($output)) {
        return $null
    }

    try {
        return ($output | ConvertFrom-Json -Depth 100)
    }
    catch {
        if ($AllowPlainTextFallback.IsPresent) {
            return $null
        }

        throw "gh returned non-JSON output for: gh $($Arguments -join ' ')"
    }
}

function Invoke-GhText {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [int[]]$AllowedExitCodes = @(0)
    )

    $outputLines = & gh @Arguments
    $exitCode = $LASTEXITCODE
    if ($AllowedExitCodes -notcontains $exitCode) {
        throw "gh $($Arguments -join ' ') failed with exit code $exitCode."
    }

    return [string]($outputLines | Out-String)
}

function Assert-GitWorkingTreeClean {
    param(
        [Parameter(Mandatory)]
        [string]$RepoPath
    )

    $status = Get-TrimmedText -InputObject (& git -C $RepoPath status --porcelain)
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        throw "Git working tree is not clean at '$RepoPath'."
    }
}

function Write-RalphStep {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $script:RalphStepCounter++
    Write-Host ("[Ralph:{0}] {1}" -f $script:RalphStepCounter, $Message) -ForegroundColor Cyan
}

function Get-TrimmedText {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return ""
    }

    if ($InputObject -is [string]) {
        return $InputObject.Trim()
    }

    $text = [string]($InputObject | Out-String)
    if ($null -eq $text) {
        return ""
    }

    return $text.Trim()
}

function Assert-DefaultBranchMatchesConfig {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RepoInfo,
        [Parameter(Mandatory)]
        [string]$BaseBranch
    )

    $defaultBranch = $RepoInfo.defaultBranchRef.name
    if ($defaultBranch -ne $BaseBranch) {
        throw "Configured baseBranch '$BaseBranch' does not match repository default branch '$defaultBranch'."
    }
}

function Test-RemoteBranchExists {
    param(
        [Parameter(Mandatory)]
        [string]$BranchName
    )

    & git -C $script:RepoRoot ls-remote --exit-code --heads origin $BranchName *> $null
    return ($LASTEXITCODE -eq 0)
}

function Get-BacklogActiveOrTakeNext {
    param(
        [switch]$ResumeOnlyMode
    )

    $active = Invoke-BacklogCliJson -Arguments @("active")
    if (-not $active.ok) {
        throw "backlog active failed: $($active | ConvertTo-Json -Depth 20)"
    }

    if ($active.data.found) {
        return $active.data.item
    }

    if ($ResumeOnlyMode.IsPresent) {
        throw "ResumeOnly was requested but there is no active backlog item."
    }

    $take = Invoke-BacklogCliJson -Arguments @("take-next")
    if (-not $take.ok) {
        throw "backlog take-next failed: $($take | ConvertTo-Json -Depth 20)"
    }

    if (-not $take.data.found) {
        return $null
    }

    return $take.data.item
}

function Write-ExecuteTaskPrompt {
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$BranchName,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $content = @"
# Ralph Task Execution

Task ID: $TaskId
Branch: $BranchName

## Title
$Title

## Description
$Description

## Requirements
- Implement the task fully.
- Run mechanical validation scripts/tests when appropriate.
- Commit all changes to the current branch.
- Push the branch to origin.
- Create or update a PR for this branch.
- Do not edit Ralph backlog files (`.ralph/backlog.json`).
"@

    Set-Content -LiteralPath $OutputPath -Value $content
}

function Write-RepairPrompt {
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][int]$PrNumber,
        [Parameter(Mandatory)][string]$PrUrl,
        [Parameter(Mandatory)][string]$FeedbackPacketPath,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $content = @"
# Ralph Repair Attempt

Task ID: $TaskId
PR: #$PrNumber ($PrUrl)

## Title
$Title

## Description
$Description

## Repair Inputs
- Feedback packet JSON: $FeedbackPacketPath

## Requirements
- Read the feedback packet and fix CI failures / requested changes.
- Commit the fixes and push to the same branch.
- Do not create a new branch.
- Do not edit Ralph backlog files (`.ralph/backlog.json`).
"@

    Set-Content -LiteralPath $OutputPath -Value $content
}

function Write-RalphPrBody {
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$AttemptDir,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $body = @"
## Ralph Task
- Task ID: ``$TaskId``
- Title: $Title

## Task Description
$Description

## Artifacts
- Ralph attempt dir: ``$AttemptDir``
"@

    Set-Content -LiteralPath $OutputPath -Value $body
}

function Run-LocalValidationCommands {
    param(
        [Parameter(Mandatory)]
        [string]$WorktreePath
    )

    $commands = @($script:RalphConfig.localValidationCommands)
    if ($commands.Count -eq 0) {
        return
    }

    foreach ($cmd in $commands) {
        if ([string]::IsNullOrWhiteSpace([string]$cmd)) {
            continue
        }

        Write-Host ">> local validation: $cmd" -ForegroundColor DarkGray
        Push-Location -LiteralPath $WorktreePath
        try {
            if ($CI.IsPresent) {
                $env:CI = "true"
            }
            & pwsh -NoLogo -NoProfile -Command $cmd
            if ($LASTEXITCODE -ne 0) {
                throw "Local validation command failed with exit code ${LASTEXITCODE}: $cmd"
            }
        }
        finally {
            Pop-Location
        }
    }
}

function Get-PrChecks {
    param(
        [Parameter(Mandatory)]
        [int]$PrNumber
    )

    $args = @("pr", "checks", "$PrNumber")
    if ([string]$script:RalphConfig.requiredChecksMode -eq "github-required") {
        $args += "--required"
    }
    $args += @("--json", "name,bucket,state,workflow,link")

    $outputLines = & gh @args 2>&1
    $exitCode = $LASTEXITCODE
    $output = [string]($outputLines | Out-String)

    if ($exitCode -notin @(0, 1, 8)) {
        throw "gh $($args -join ' ') failed with exit code $exitCode. $output"
    }

    if ([string]::IsNullOrWhiteSpace($output)) {
        return @()
    }

    try {
        $checks = $output | ConvertFrom-Json -Depth 100
        $normalized = @($checks)
        Write-Output -NoEnumerate $normalized
        return
    }
    catch {
        if ($output -match 'no required checks reported') {
            return @()
        }

        # Transient GitHub/GraphQL/network issue: treat as a pending pseudo-check so Ralph retries.
        $message = ($output -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
        Write-RalphStep "Warning: failed to query PR checks (transient); retrying. $message"
        $pseudo = [pscustomobject]@{
            name = "gh-pr-checks-query"
            bucket = "pending"
            state = "PENDING"
            workflow = "Ralph"
            link = $null
        }
        Write-Output -NoEnumerate @($pseudo)
        return
    }
}

function Get-MergeArgs {
    param(
        [Parameter(Mandatory)][int]$PrNumber,
        [Parameter(Mandatory)][string]$HeadSha
    )

    $args = @("pr", "merge", "$PrNumber")
    switch ([string]$script:RalphConfig.mergeMethod) {
        "squash" { $args += "--squash" }
        "merge" { $args += "--merge" }
        "rebase" { $args += "--rebase" }
        default { throw "Unsupported mergeMethod '$($script:RalphConfig.mergeMethod)'." }
    }

    $args += @("--match-head-commit", $HeadSha)
    return $args
}

function Remove-TaskBranchAfterMerge {
    param(
        [Parameter(Mandatory)]
        [string]$BranchName
    )

    if (-not [bool]$script:RalphConfig.deleteBranchOnMerge) {
        return
    }

    Write-RalphStep "Post-merge branch cleanup for '$BranchName'"

    try {
        $localBranchExists = -not [string]::IsNullOrWhiteSpace((Get-TrimmedText (& git -C $script:RepoRoot branch --list $BranchName)))
        if ($localBranchExists) {
            & git -C $script:RepoRoot branch -D $BranchName *> $null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Deleted local branch '$BranchName'" -ForegroundColor DarkGray
            }
            else {
                Write-Host "Local branch cleanup warning for '$BranchName' (exit $LASTEXITCODE)." -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "Local branch cleanup warning for '$BranchName': $($_.Exception.Message)" -ForegroundColor Yellow
    }

    try {
        if (Test-RemoteBranchExists -BranchName $BranchName) {
            & git -C $script:RepoRoot push origin --delete $BranchName *> $null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Deleted remote branch '$BranchName'" -ForegroundColor DarkGray
            }
            else {
                Write-Host "Remote branch cleanup warning for '$BranchName' (exit $LASTEXITCODE)." -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "Remote branch cleanup warning for '$BranchName': $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Commit-BacklogDoneToMain {
    param(
        [Parameter(Mandatory)]
        [string]$TaskId,
        [Parameter(Mandatory)]
        [string]$BaseBranch
    )

    $configuredBacklogPath = [string]$script:RalphConfig.backlogPath
    $resolvedBacklogPath = Resolve-RalphPath -PathValue $configuredBacklogPath
    $backlogPathspec = if ([System.IO.Path]::IsPathRooted($configuredBacklogPath)) {
        [System.IO.Path]::GetRelativePath($script:RepoRoot, $resolvedBacklogPath)
    }
    else {
        $configuredBacklogPath
    }

    $backlogPathspec = $backlogPathspec -replace '\\', '/'

    $currentBranch = Get-TrimmedText (& git -C $script:RepoRoot branch --show-current)
    if ($currentBranch -ne $BaseBranch) {
        throw "Cannot commit backlog on '$BaseBranch' because repo root is on '$currentBranch'."
    }

    $backlogStatus = Get-TrimmedText (& git -C $script:RepoRoot status --porcelain -- $backlogPathspec)
    if ([string]::IsNullOrWhiteSpace($backlogStatus)) {
        Write-RalphStep "No backlog changes detected to commit for task '$TaskId'"
        return
    }

    Write-RalphStep "Committing backlog Done state for '$TaskId' directly to '$BaseBranch'"
    Invoke-External -FilePath "git" -Arguments @("-C", $script:RepoRoot, "add", "--", $backlogPathspec) -WorkingDirectory $script:RepoRoot -StepName "git add backlog"

    $commitMessage = "chore(ralph): mark $TaskId done"
    Invoke-External -FilePath "git" -Arguments @("-C", $script:RepoRoot, "commit", "-m", $commitMessage) -WorkingDirectory $script:RepoRoot -StepName "git commit backlog"

    $maxPushAttempts = 3
    for ($attempt = 1; $attempt -le $maxPushAttempts; $attempt++) {
        Write-RalphStep "Syncing backlog commit with latest origin/$BaseBranch (attempt $attempt/$maxPushAttempts)"
        Invoke-External -FilePath "git" -Arguments @("fetch", "origin", "--prune") -WorkingDirectory $script:RepoRoot -StepName "git fetch backlog push"

        $rebaseOutputLines = & git -C $script:RepoRoot rebase "origin/$BaseBranch" 2>&1
        $rebaseExitCode = $LASTEXITCODE
        $rebaseOutput = [string]($rebaseOutputLines | Out-String)
        if ($rebaseExitCode -ne 0) {
            Write-Host "Backlog rebase failed; attempting rebase --abort" -ForegroundColor Yellow
            & git -C $script:RepoRoot rebase --abort *> $null
            $abortExitCode = $LASTEXITCODE
            if ($abortExitCode -ne 0) {
                Write-Host "Rebase abort warning (exit $abortExitCode)." -ForegroundColor Yellow
            }

            throw "Failed to rebase backlog commit onto origin/$BaseBranch. Resolve backlog conflict manually. $rebaseOutput"
        }

        Write-RalphStep "Pushing backlog commit to origin/$BaseBranch (attempt $attempt/$maxPushAttempts)"
        $pushOutputLines = & git -C $script:RepoRoot push origin $BaseBranch 2>&1
        $pushExitCode = $LASTEXITCODE
        $pushOutput = [string]($pushOutputLines | Out-String)
        if ($pushExitCode -eq 0) {
            return
        }

        $retryablePushFailure =
            ($pushOutput -match 'non-fast-forward') -or
            ($pushOutput -match '\[rejected\]') -or
            ($pushOutput -match 'failed to push some refs')

        if ($retryablePushFailure -and $attempt -lt $maxPushAttempts) {
            Write-RalphStep "Backlog push raced with another update; retrying after refetch/rebase"
            continue
        }

        throw "Failed to push backlog commit to origin/$BaseBranch. $pushOutput"
    }

    throw "Failed to push backlog commit to origin/$BaseBranch after $maxPushAttempts attempts."
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Parse-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100)
}

$processedOne = $false
$stopAfterCurrent = $false

try {
    $configFullPath = Resolve-RalphPath -PathValue $ConfigPath
    if (-not (Test-Path -LiteralPath $configFullPath)) {
        throw "Ralph config file not found: $configFullPath"
    }

    $script:RalphConfig = Parse-JsonFile -Path $configFullPath

    # Normalize config paths to repo-relative strings for backlog CLI and absolute paths for scripts/worktrees/artifacts.
    $script:RalphConfig.backlogPath = [string]$script:RalphConfig.backlogPath
    $script:RalphConfig.schemaPath = [string]$script:RalphConfig.schemaPath

    $baseBranch = [string]$script:RalphConfig.baseBranch
    $branchPrefix = [string]$script:RalphConfig.branchPrefix
    $worktreePath = Resolve-RalphPath -PathValue ([string]$script:RalphConfig.worktreePath)
    $runArtifactsRoot = Resolve-RalphPath -PathValue ([string]$script:RalphConfig.runArtifactsRoot)
    $agentAdapterScript = Resolve-RalphPath -PathValue ([string]$script:RalphConfig.agentAdapterScript)
    $feedbackCollectorScript = Resolve-RalphPath -PathValue ([string]$script:RalphConfig.feedbackCollectorScript)
    $pollSeconds = if ($PollIntervalSeconds -gt 0) { $PollIntervalSeconds } else { [int]$script:RalphConfig.pollIntervalSeconds }
    $maxRepairCycles = [int]$script:RalphConfig.maxRepairCycles

    Write-RalphStep "Loading Ralph config and acquiring loop lock"
    Acquire-RalphLock
    Ensure-Directory -Path (Resolve-RalphPath -PathValue ".ralph")
    Ensure-Directory -Path $runArtifactsRoot

    Write-Host "Running Ralph loop..." -ForegroundColor Cyan
    Write-Host "Base branch: $baseBranch | Worktree: $worktreePath" -ForegroundColor Gray

    Write-RalphStep "Running preflight checks (commands, git state, GitHub auth)"
    Assert-CommandAvailable -Name "git"
    Assert-CommandAvailable -Name "gh"
    Assert-CommandAvailable -Name "dotnet"

    Assert-GitWorkingTreeClean -RepoPath $script:RepoRoot

    $currentBranch = Get-TrimmedText (& git -C $script:RepoRoot branch --show-current)
    if ($currentBranch -ne $baseBranch) {
        throw "Ralph requires a clean '$baseBranch' checkout at repo root. Current branch: $currentBranch"
    }

    Invoke-External -FilePath "gh" -Arguments @("auth", "status") -WorkingDirectory $script:RepoRoot -StepName "gh auth status"
    $repoInfo = Invoke-GhJson -Arguments @("repo", "view", "--json", "nameWithOwner,defaultBranchRef")
    Assert-DefaultBranchMatchesConfig -RepoInfo $repoInfo -BaseBranch $baseBranch

    Write-RalphStep "Validating backlog"
    $validate = Invoke-BacklogCliJson -Arguments @("validate")
    if (-not $validate.ok) {
        throw "Backlog validation failed: $($validate | ConvertTo-Json -Depth 20)"
    }

    while ($true) {
        if ($stopAfterCurrent) {
            break
        }

        Write-RalphStep "Refreshing origin/$baseBranch"
        Invoke-External -FilePath "git" -Arguments @("fetch", "origin", "--prune") -WorkingDirectory $script:RepoRoot -StepName "git fetch"

        Write-RalphStep "Selecting backlog item (resume active or take next)"
        $item = Get-BacklogActiveOrTakeNext -ResumeOnlyMode:$ResumeOnly
        if ($null -eq $item) {
            Write-Host "No eligible backlog items remain. Ralph complete." -ForegroundColor Green
            break
        }

        if ($processedOne -and $Once.IsPresent) {
            break
        }

        $taskId = [string]$item.id
        $taskTitle = [string]$item.title
        $taskDescription = [string]$item.description
        $branchName = "$branchPrefix/$taskId"
        Write-RalphStep "Working task '$taskId' on branch '$branchName'"

        $runId = Get-OrCreateRunId
        $taskRunDir = Join-Path -Path $runArtifactsRoot -ChildPath (Join-Path -Path $runId -ChildPath $taskId)
        Ensure-Directory -Path $taskRunDir

        Write-RalphStep "Preparing worktree"
        if (Test-Path -LiteralPath $worktreePath) {
            & git -C $script:RepoRoot worktree remove $worktreePath --force *> $null
        }

        $remoteBranchExists = Test-RemoteBranchExists -BranchName $branchName
        if ($remoteBranchExists) {
            Invoke-External -FilePath "git" -Arguments @("worktree", "add", "--force", "-B", $branchName, $worktreePath, "origin/$branchName") -WorkingDirectory $script:RepoRoot -StepName "git worktree add (resume)"
        }
        else {
            Invoke-External -FilePath "git" -Arguments @("worktree", "add", "--force", "-B", $branchName, $worktreePath, "origin/$baseBranch") -WorkingDirectory $script:RepoRoot -StepName "git worktree add (new)"
        }

        Assert-GitWorkingTreeClean -RepoPath $worktreePath

        $repairCount = 0
        $prNumber = $null
        $prUrl = $null
        $taskCompleted = $false
        $taskMerged = $false
        $currentPrHeadSha = $null

        while (-not $taskCompleted) {
            $attemptDir = Join-Path -Path $taskRunDir -ChildPath ("attempt-" + ($repairCount + 1))
            Ensure-Directory -Path $attemptDir
            Write-RalphStep "Task '$taskId' attempt $($repairCount + 1): preparing prompt"

            $promptFile = Join-Path -Path $attemptDir -ChildPath "prompt.md"
            if ($repairCount -eq 0) {
                Write-ExecuteTaskPrompt -TaskId $taskId -Title $taskTitle -Description $taskDescription -BranchName $branchName -OutputPath $promptFile
            }
            else {
                Write-RalphStep "Task '$taskId' attempt $($repairCount + 1): collecting PR feedback for repair"
                & $feedbackCollectorScript -RepoRoot $script:RepoRoot -PrNumber $prNumber -BranchName $branchName -ExpectedHeadSha $currentPrHeadSha -OutputDir $attemptDir
                $feedbackPacket = Join-Path -Path $attemptDir -ChildPath "feedback.json"
                Write-RepairPrompt -TaskId $taskId -Title $taskTitle -Description $taskDescription -PrNumber $prNumber -PrUrl $prUrl -FeedbackPacketPath $feedbackPacket -OutputPath $promptFile
            }

            Write-RalphStep "Task '$taskId' attempt $($repairCount + 1): invoking Codex agent"
            & $agentAdapterScript `
                -RepoRoot $script:RepoRoot `
                -WorktreePath $worktreePath `
                -BranchName $branchName `
                -PromptFile $promptFile `
                -TaskId $taskId `
                -AttemptNumber ($repairCount + 1) `
                -OutputDir $attemptDir

            Write-RalphStep "Task '$taskId' attempt $($repairCount + 1): running local validations and git checks"
            Run-LocalValidationCommands -WorktreePath $worktreePath

            $wtBranch = Get-TrimmedText (& git -C $worktreePath branch --show-current)
            if ($wtBranch -ne $branchName) {
                throw "Agent left wrong branch checked out: $wtBranch"
            }

            $aheadCount = [int](Get-TrimmedText (& git -C $worktreePath rev-list --count "origin/$baseBranch..HEAD"))
            if ($aheadCount -le 0 -and -not $remoteBranchExists) {
                throw "No commits ahead of origin/$baseBranch after agent run for $taskId."
            }

            if (-not (Test-RemoteBranchExists -BranchName $branchName)) {
                Invoke-External -FilePath "git" -Arguments @("-C", $worktreePath, "push", "-u", "origin", $branchName) -WorkingDirectory $script:RepoRoot -StepName "git push fallback"
            }

            Write-RalphStep "Task '$taskId' attempt $($repairCount + 1): locating or creating PR"
            $prList = Invoke-GhJson -Arguments @(
                "pr", "list",
                "--head", $branchName,
                "--state", "open",
                "--limit", "1",
                "--json", "number,url,headRefName,headRefOid,title,state,reviewDecision,statusCheckRollup"
            )
            $prListItems = @($prList)

            if ($prListItems.Count -eq 0) {
                $prBodyFile = Join-Path -Path $attemptDir -ChildPath "pr-body.md"
                Write-RalphPrBody -TaskId $taskId -Title $taskTitle -Description $taskDescription -AttemptDir $attemptDir -OutputPath $prBodyFile
                $prTitle = "[$taskId] $taskTitle"
                $prUrl = (Invoke-GhText -Arguments @("pr", "create", "--base", $baseBranch, "--head", $branchName, "--title", $prTitle, "--body-file", $prBodyFile)).Trim()
                $prView = Invoke-GhJson -Arguments @("pr", "view", $branchName, "--json", "number,url,headRefOid,headRefName,state,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,reviews,comments")
                $prNumber = [int]$prView.number
                Write-RalphStep "Created PR #$prNumber for task '$taskId'"
            }
            else {
                $prNumber = [int]$prListItems[0].number
                $prUrl = [string]$prListItems[0].url
                Write-RalphStep "Using existing PR #$prNumber for task '$taskId'"
            }

            $currentBacklogItemEnvelope = Invoke-BacklogCliJson -Arguments @("show", "--id", $taskId)
            if (-not $currentBacklogItemEnvelope.ok) {
                throw "Failed to load backlog item '$taskId': $($currentBacklogItemEnvelope | ConvertTo-Json -Depth 20)"
            }
            if ($currentBacklogItemEnvelope.data.found -and [string]$currentBacklogItemEnvelope.data.item.status -eq "InProgress") {
                Write-RalphStep "Setting backlog item '$taskId' status to InReview"
                $setReview = Invoke-BacklogCliJson -Arguments @("status", "set", "--id", $taskId, "--to", "InReview")
                if (-not $setReview.ok) {
                    throw "Failed to set backlog item '$taskId' to InReview: $($setReview | ConvertTo-Json -Depth 20)"
                }
            }

            $repairNeeded = $false
            $readyToMerge = $false

            Write-RalphStep "Polling PR #$prNumber checks/reviews for task '$taskId'"
            while (-not $repairNeeded -and -not $readyToMerge) {
                $prView = Invoke-GhJson -Arguments @(
                    "pr", "view", "$prNumber",
                    "--json", "number,url,state,mergeable,mergeStateStatus,reviewDecision,headRefName,headRefOid,statusCheckRollup,reviews,comments,title,body"
                )

                $currentPrHeadSha = [string]$prView.headRefOid
                if ([string]$prView.state -ne "OPEN") {
                    throw "PR #$prNumber is no longer open (state=$($prView.state))."
                }

                if ([string]$prView.reviewDecision -eq "CHANGES_REQUESTED") {
                    $repairNeeded = $true
                    break
                }

                $checks = Get-PrChecks -PrNumber $prNumber
                $checksCount = @($checks).Count
                if ($checksCount -eq 0) {
                    Write-RalphStep "PR #$prNumber has no required checks; waiting for mergeable/review state"
                    if (([string]$prView.mergeable -eq "MERGEABLE") -and ([string]$prView.mergeStateStatus -notin @("DIRTY", "BEHIND"))) {
                        $readyToMerge = $true
                        break
                    }

                    Start-Sleep -Seconds $pollSeconds
                    continue
                }

                $hasFail = @($checks | Where-Object { $_.bucket -eq "fail" }).Count -gt 0
                $hasPending = @($checks | Where-Object { $_.bucket -in @("pending", "cancel") }).Count -gt 0
                if ($hasPending) {
                    Write-RalphStep "PR #$prNumber checks pending ($checksCount required checks observed); polling again"
                }

                if ($hasFail) {
                    Write-RalphStep "PR #$prNumber has failed required checks; entering repair loop"
                    $repairNeeded = $true
                    break
                }

                if ($hasPending) {
                    Start-Sleep -Seconds $pollSeconds
                    continue
                }

                if (([string]$prView.mergeable -eq "MERGEABLE") -and ([string]$prView.reviewDecision -ne "CHANGES_REQUESTED")) {
                    $readyToMerge = $true
                    break
                }

                Start-Sleep -Seconds $pollSeconds
            }

            if ($repairNeeded) {
                $repairCount++
                if ($repairCount -gt $maxRepairCycles) {
                    throw "Max repair cycles exceeded for $taskId."
                }

                Write-RalphStep "Task '$taskId' repair attempt required; setting status back to InProgress"
                $setInProgress = Invoke-BacklogCliJson -Arguments @("status", "set", "--id", $taskId, "--to", "InProgress")
                if (-not $setInProgress.ok) {
                    throw "Failed to set backlog item '$taskId' back to InProgress: $($setInProgress | ConvertTo-Json -Depth 20)"
                }

                $remoteBranchExists = $true
                continue
            }

            if ($NoMerge.IsPresent) {
                Write-Host "NoMerge enabled. Leaving task '$taskId' in InReview at PR $prUrl" -ForegroundColor Yellow
                $taskCompleted = $true
                $stopAfterCurrent = $true
                break
            }

            Write-RalphStep "Merging PR #$prNumber for task '$taskId'"
            $mergeArgs = Get-MergeArgs -PrNumber $prNumber -HeadSha $currentPrHeadSha
            $mergeOutputLines = & gh @mergeArgs 2>&1
            $mergeExitCode = $LASTEXITCODE
            $mergeOutput = [string]($mergeOutputLines | Out-String)
            $autoMergeRequested = $false

            if ($mergeExitCode -ne 0) {
                if ($mergeOutput -match 'base branch policy prohibits the merge' -or $mergeOutput -match 'add the `--auto` flag') {
                    Write-RalphStep "Direct merge blocked by branch policy for PR #$prNumber; requesting auto-merge"
                    $autoMergeArgs = @($mergeArgs + @("--auto"))
                    $autoMergeOutputLines = & gh @autoMergeArgs 2>&1
                    $autoMergeExitCode = $LASTEXITCODE
                    $autoMergeOutput = [string]($autoMergeOutputLines | Out-String)
                    if ($autoMergeExitCode -ne 0) {
                        throw "gh pr merge --auto failed with exit code $autoMergeExitCode. $autoMergeOutput"
                    }

                    $autoMergeRequested = $true
                }
                else {
                    throw "gh pr merge failed with exit code $mergeExitCode. $mergeOutput"
                }
            }

            if ($autoMergeRequested) {
                Write-RalphStep "Waiting for PR #$prNumber to merge after auto-merge request"
            }

            while ($true) {
                Invoke-External -FilePath "git" -Arguments @("fetch", "origin", "--prune") -WorkingDirectory $script:RepoRoot -StepName "git fetch post-merge"
                $mergedPr = Invoke-GhJson -Arguments @("pr", "view", "$prNumber", "--json", "state,mergedAt,mergeCommit,mergeStateStatus")
                if ($null -ne $mergedPr.mergedAt) {
                    break
                }

                if ([string]$mergedPr.state -ne "OPEN") {
                    throw "PR #$prNumber is not open and not merged (state=$($mergedPr.state))."
                }

                if (-not $autoMergeRequested) {
                    throw "PR #$prNumber did not report mergedAt after merge."
                }

                Write-RalphStep "PR #$prNumber auto-merge pending (mergeStateStatus=$($mergedPr.mergeStateStatus)); polling again"
                Start-Sleep -Seconds $pollSeconds
            }

            Write-RalphStep "Marking backlog item '$taskId' as Done"
            $setDone = Invoke-BacklogCliJson -Arguments @("status", "set", "--id", $taskId, "--to", "Done")
            if (-not $setDone.ok) {
                throw "Failed to mark backlog item '$taskId' Done: $($setDone | ConvertTo-Json -Depth 20)"
            }
            Commit-BacklogDoneToMain -TaskId $taskId -BaseBranch $baseBranch

            $taskCompleted = $true
            $processedOne = $true
            $taskMerged = $true
        }

        Write-RalphStep "Cleaning worktree for task '$taskId'"
        if (Test-Path -LiteralPath $worktreePath) {
            & git -C $script:RepoRoot worktree remove $worktreePath --force *> $null
        }
        if ($taskMerged) {
            Remove-TaskBranchAfterMerge -BranchName $branchName
        }

        if ($Once.IsPresent) {
            break
        }
    }
}
finally {
    try {
        if ($null -ne $worktreePath -and (Test-Path -LiteralPath $worktreePath)) {
            & git -C $script:RepoRoot worktree remove $worktreePath --force *> $null
        }
    }
    catch {
        Write-Host "Worktree cleanup warning: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Release-RalphLock
}
