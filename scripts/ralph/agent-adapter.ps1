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

$proc = Start-Process `
    -FilePath $codexCmd `
    -ArgumentList $argList `
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
