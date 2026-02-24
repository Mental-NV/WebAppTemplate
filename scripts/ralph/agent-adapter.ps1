param(
    [Parameter(Mandatory)]
    [string]$RepoRoot,
    [Parameter(Mandatory)]
    [string]$WorktreePath,
    [Parameter(Mandatory)]
    [string]$BranchName,
    [Parameter(Mandatory)]
    [string]$PromptFile,
    [Parameter(Mandatory)]
    [string]$TaskId,
    [Parameter(Mandatory)]
    [int]$AttemptNumber,
    [Parameter(Mandatory)]
    [string]$OutputDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ProcessLaunchSpec {
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,
        [Parameter(Mandatory)]
        [string[]]$CommandArguments
    )

    $commandInfo = Get-Command -Name $CommandName -ErrorAction Stop
    $resolvedPath = if (-not [string]::IsNullOrWhiteSpace($commandInfo.Path)) { $commandInfo.Path } else { $null }

    if ($commandInfo.CommandType -eq [System.Management.Automation.CommandTypes]::ExternalScript -and
        -not [string]::IsNullOrWhiteSpace($resolvedPath) -and
        [System.IO.Path]::GetExtension($resolvedPath).Equals(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            FilePath = "pwsh"
            ArgumentList = @("-NoLogo", "-NoProfile", "-File", $resolvedPath) + $CommandArguments
            ResolvedCommandPath = $resolvedPath
            LauncherKind = "PwshExternalScript"
        }
    }

    return [pscustomobject]@{
        FilePath = $CommandName
        ArgumentList = $CommandArguments
        ResolvedCommandPath = $resolvedPath
        LauncherKind = "Direct"
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$stdoutPath = Join-Path -Path $OutputDir -ChildPath "agent.stdout.log"
$stderrPath = Join-Path -Path $OutputDir -ChildPath "agent.stderr.log"
$lastMessagePath = Join-Path -Path $OutputDir -ChildPath "agent.last-message.txt"
$resultPath = Join-Path -Path $OutputDir -ChildPath "agent.result.json"

$codexCmd = if ([string]::IsNullOrWhiteSpace($env:RALPH_CODEX_COMMAND)) { "codex" } else { $env:RALPH_CODEX_COMMAND }

$argList = @(
    "exec",
    "--cd", $WorktreePath,
    "--dangerously-bypass-approvals-and-sandbox",
    "--json",
    "--output-last-message", $lastMessagePath,
    "-"
)

if (-not [string]::IsNullOrWhiteSpace($env:RALPH_CODEX_MODEL)) {
    $argList = @("exec", "--cd", $WorktreePath, "--dangerously-bypass-approvals-and-sandbox", "--json", "--output-last-message", $lastMessagePath, "--model", $env:RALPH_CODEX_MODEL, "-")
}

$startedAt = [DateTimeOffset]::UtcNow
$launchSpec = Resolve-ProcessLaunchSpec -CommandName $codexCmd -CommandArguments $argList

$proc = Start-Process `
    -FilePath $launchSpec.FilePath `
    -ArgumentList $launchSpec.ArgumentList `
    -WorkingDirectory $WorktreePath `
    -RedirectStandardInput $PromptFile `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -PassThru `
    -Wait

$completedAt = [DateTimeOffset]::UtcNow

$result = [ordered]@{
    taskId = $TaskId
    attemptNumber = $AttemptNumber
    branchName = $BranchName
    repoRoot = $RepoRoot
    worktreePath = $WorktreePath
    promptFile = $PromptFile
    command = $codexCmd
    resolvedCommandPath = $launchSpec.ResolvedCommandPath
    launcherKind = $launchSpec.LauncherKind
    launcherCommand = $launchSpec.FilePath
    launcherArguments = $launchSpec.ArgumentList
    arguments = $argList
    startedAtUtc = $startedAt.ToString("o")
    completedAtUtc = $completedAt.ToString("o")
    exitCode = $proc.ExitCode
    stdoutPath = $stdoutPath
    stderrPath = $stderrPath
    outputLastMessagePath = $lastMessagePath
}

($result | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $resultPath

if ($proc.ExitCode -ne 0) {
    throw "Codex agent failed with exit code $($proc.ExitCode). See $stdoutPath and $stderrPath."
}
