param(
    [Parameter(Mandatory)]
    [string]$RepoRoot,
    [Parameter(Mandatory)]
    [int]$PrNumber,
    [Parameter(Mandatory)]
    [string]$BranchName,
    [string]$ExpectedHeadSha = "",
    [Parameter(Mandatory)]
    [string]$OutputDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "common.ps1")

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Invoke-GhJson {
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

    $output = [string]($outputLines | Out-String)
    if ([string]::IsNullOrWhiteSpace($output)) {
        return $null
    }

    return ($output | ConvertFrom-Json)
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

Push-Location -LiteralPath $RepoRoot
try {
    $prView = Invoke-GhJson -Arguments @(
        "pr", "view", "$PrNumber",
        "--json", "number,url,state,mergeable,mergeStateStatus,reviewDecision,headRefOid,headRefName,statusCheckRollup,reviews,comments,title,body"
    )
    ($prView | ConvertTo-Json -Depth 100) | Set-Content -LiteralPath (Join-Path $OutputDir "pr-view.json")

    $checks = Invoke-GhJson -Arguments @(
        "pr", "checks", "$PrNumber", "--required",
        "--json", "name,bucket,state,workflow,link"
    ) -AllowedExitCodes @(0, 1, 8)
    if ($null -eq $checks) { $checks = @() }
    ($checks | ConvertTo-Json -Depth 100) | Set-Content -LiteralPath (Join-Path $OutputDir "checks.json")

    $runs = Invoke-GhJson -Arguments @(
        "run", "list",
        "--branch", $BranchName,
        "--limit", "20",
        "--json", "databaseId,headSha,status,conclusion,name,workflowName,url,createdAt,updatedAt"
    )
    if ($null -eq $runs) { $runs = @() }
    ($runs | ConvertTo-Json -Depth 100) | Set-Content -LiteralPath (Join-Path $OutputDir "runs.json")

    $failedRuns = @()
    foreach ($run in $runs) {
        if (-not [string]::IsNullOrWhiteSpace($ExpectedHeadSha) -and $run.headSha -ne $ExpectedHeadSha) {
            continue
        }

        if ($run.status -ne "completed") {
            continue
        }

        if ($run.conclusion -notin @("failure", "timed_out", "startup_failure", "action_required", "cancelled")) {
            continue
        }

        $logFileName = "failed-run-$($run.databaseId).log"
        $logFilePath = Join-Path -Path $OutputDir -ChildPath $logFileName
        $logText = Invoke-GhText -Arguments @("run", "view", "$($run.databaseId)", "--log-failed") -AllowedExitCodes @(0, 1)
        Set-Content -LiteralPath $logFilePath -Value $logText

        $failedRuns += [pscustomobject]@{
            databaseId = $run.databaseId
            name = $run.name
            workflowName = $run.workflowName
            conclusion = $run.conclusion
            url = $run.url
            logFile = $logFileName
        }
    }

    $issueComments = Invoke-GhJson -Arguments @("api", "repos/{owner}/{repo}/issues/$PrNumber/comments", "--paginate")
    if ($null -eq $issueComments) { $issueComments = @() }
    ($issueComments | ConvertTo-Json -Depth 100) | Set-Content -LiteralPath (Join-Path $OutputDir "issue-comments.json")

    $reviewComments = Invoke-GhJson -Arguments @("api", "repos/{owner}/{repo}/pulls/$PrNumber/comments", "--paginate")
    if ($null -eq $reviewComments) { $reviewComments = @() }
    ($reviewComments | ConvertTo-Json -Depth 100) | Set-Content -LiteralPath (Join-Path $OutputDir "review-comments.json")

    $reviews = Invoke-GhJson -Arguments @("api", "repos/{owner}/{repo}/pulls/$PrNumber/reviews", "--paginate")
    if ($null -eq $reviews) { $reviews = @() }
    ($reviews | ConvertTo-Json -Depth 100) | Set-Content -LiteralPath (Join-Path $OutputDir "reviews.json")

    $condensedIssueComments = @($issueComments | ForEach-Object {
        [pscustomobject]@{
            id = $_.id
            user = $_.user.login
            body = $_.body
            createdAt = $_.created_at
            updatedAt = $_.updated_at
            url = $_.html_url
        }
    })

    $condensedReviewComments = @($reviewComments | ForEach-Object {
        [pscustomobject]@{
            id = $_.id
            path = $_.path
            line = $_.line
            side = $_.side
            body = $_.body
            user = $_.user.login
            createdAt = $_.created_at
            url = $_.html_url
        }
    })

    $condensedReviews = @($reviews | ForEach-Object {
        [pscustomobject]@{
            id = $_.id
            state = $_.state
            body = $_.body
            user = $_.user.login
            submittedAt = $_.submitted_at
        }
    })

    $feedback = [ordered]@{
        pr = [ordered]@{
            number = $prView.number
            url = $prView.url
            headRefName = $prView.headRefName
            headRefOid = $prView.headRefOid
            reviewDecision = $prView.reviewDecision
            mergeable = $prView.mergeable
            mergeStateStatus = $prView.mergeStateStatus
        }
        checks = @($checks)
        failedRuns = @($failedRuns)
        newIssueComments = $condensedIssueComments
        newReviewComments = $condensedReviewComments
        newReviews = $condensedReviews
        summary = [ordered]@{
            repairReason = "FailedRequiredChecksOrReviewChangesRequested"
            collectedAtUtc = [DateTimeOffset]::UtcNow.ToString("o")
        }
    }

    ($feedback | ConvertTo-Json -Depth 100) | Set-Content -LiteralPath (Join-Path $OutputDir "feedback.json")
}
finally {
    Pop-Location
}
