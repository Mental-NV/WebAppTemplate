[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$BacklogPath = ".ralph/backlog.json",
    [string]$SchemaPath = ".ralph/backlog.schema.json",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$projectPath = Join-Path -Path $repoRoot -ChildPath "tools/Ralph.BacklogCli/Ralph.BacklogCli.csproj"

$passArgs = @($Args)
if ($passArgs -notcontains "--backlog") {
    $passArgs += @("--backlog", $BacklogPath)
}
if ($passArgs -notcontains "--schema") {
    $passArgs += @("--schema", $SchemaPath)
}
if ($passArgs -notcontains "--json") {
    $passArgs += @("--json")
}

& dotnet run --project $projectPath -- @passArgs
exit $LASTEXITCODE
