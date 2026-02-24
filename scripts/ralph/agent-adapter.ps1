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

function Write-AgentLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::DarkCyan
    )

    $timestamp = [DateTimeOffset]::UtcNow.ToString("o")
    Write-Host "[$timestamp] [Ralph-Agent] $Message" -ForegroundColor $Color
}

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
        $cmdShimPath = [System.IO.Path]::ChangeExtension($resolvedPath, ".cmd")
        if (Test-Path -LiteralPath $cmdShimPath) {
            return [pscustomobject]@{
                FilePath = $cmdShimPath
                ArgumentList = $CommandArguments
                ResolvedCommandPath = $cmdShimPath
                LauncherKind = "CmdShim"
            }
        }

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
Write-AgentLog -Message "Launching Codex via $($launchSpec.LauncherKind): $($launchSpec.FilePath)"
Write-AgentLog -Message "Prompt: $PromptFile" -Color DarkGray
Write-AgentLog -Message "Logs: stdout=$stdoutPath stderr=$stderrPath" -Color DarkGray

$proc = Start-Process `
    -FilePath $launchSpec.FilePath `
    -ArgumentList $launchSpec.ArgumentList `
    -WorkingDirectory $WorktreePath `
    -RedirectStandardInput $PromptFile `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -PassThru

$turnCompletedObservedAt = $null
$turnCompletedLine = $null
$nextWaitProgressLogAt = $startedAt.AddMinutes(1)

while (-not $proc.HasExited) {
    Start-Sleep -Seconds 2
    $proc.Refresh()

    if ($null -eq $turnCompletedObservedAt -and (Test-Path -LiteralPath $stdoutPath)) {
        try {
            $match = Select-String -Path $stdoutPath -SimpleMatch '"type":"turn.completed"' | Select-Object -First 1
            if ($null -ne $match) {
                $turnCompletedObservedAt = [DateTimeOffset]::UtcNow
                $turnCompletedLine = [string]$match.Line
                Write-AgentLog -Message "Observed turn.completed in stdout log; waiting for Codex process to exit..." -Color Yellow
                $nextWaitProgressLogAt = $turnCompletedObservedAt.AddMinutes(1)
            }
        }
        catch {
            Write-AgentLog -Message "Warning: failed to scan stdout log for turn.completed ($($_.Exception.Message)); will retry." -Color Yellow
        }
    }

    if ($null -ne $turnCompletedObservedAt -and [DateTimeOffset]::UtcNow -ge $nextWaitProgressLogAt) {
        $waitSeconds = [math]::Round(([DateTimeOffset]::UtcNow - $turnCompletedObservedAt).TotalSeconds, 1)
        Write-AgentLog -Message "Still waiting for Codex process exit after turn.completed ($waitSeconds s elapsed)." -Color Yellow
        $nextWaitProgressLogAt = [DateTimeOffset]::UtcNow.AddMinutes(1)
    }
}

$proc.WaitForExit()

$completedAt = [DateTimeOffset]::UtcNow
Write-AgentLog -Message "Codex process exited with code $($proc.ExitCode)"

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
    turnCompletedObservedAtUtc = if ($null -eq $turnCompletedObservedAt) { $null } else { $turnCompletedObservedAt.ToString("o") }
    turnCompletedObservedLine = $turnCompletedLine
    postTurnCompletedToExitSeconds = if ($null -eq $turnCompletedObservedAt) { $null } else { [math]::Round(($completedAt - $turnCompletedObservedAt).TotalSeconds, 3) }
    exitCode = $proc.ExitCode
    stdoutPath = $stdoutPath
    stderrPath = $stderrPath
    outputLastMessagePath = $lastMessagePath
}

($result | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $resultPath

if ($proc.ExitCode -ne 0) {
    throw "Codex agent failed with exit code $($proc.ExitCode). See $stdoutPath and $stderrPath."
}
