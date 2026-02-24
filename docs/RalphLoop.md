# Ralph Loop High-Level Design

## Purpose

Ralph Loop is an automation loop that executes backlog items one at a time from `.ralph/backlog.json`, using a Codex-based agent to implement work on task branches and drive the task through pull request review and merge.

The design goal is operational reliability:

- Single agent execution (one loop instance at a time)
- One active backlog item at a time (1-WIP)
- Deterministic status transitions
- Recoverable retry/repair behavior for CI and review feedback

## Execution Model (Single-Agent / 1-WIP)

Ralph Loop enforces a serialized workflow at two levels:

- Loop process lock: `scripts/ralph.ps1` acquires `.ralph/ralph.loop.lock` so only one Ralph loop instance can run against the repo at once.
- Backlog active-item rule: the backlog validator allows at most one item in `InProgress` or `InReview`.

This produces a strict 1-WIP model:

- Ralph either resumes the existing active item, or
- takes the next eligible `New` item and starts it,
- but never works multiple backlog items concurrently.

## Main Workflow

### 1. Preflight and Validation

`scripts/ralph.ps1` performs startup checks before work begins:

- Loads `.ralph/config.json`
- Acquires the loop lock
- Verifies required tools (`git`, `gh`, `dotnet`)
- Verifies GitHub auth (`gh auth status`)
- Verifies repo root is clean and on configured base branch (typically `main`)
- Validates backlog structure and runtime rules via the backlog CLI

If any preflight step fails, the loop exits without mutating backlog state.

### 2. Backlog Item Selection (Resume or Take Next)

For each cycle, Ralph:

- Checks for an active backlog item (`InProgress` or `InReview`)
- If found, resumes that item
- If not found, calls `take-next` to select the next eligible `New` item

Eligibility for `take-next`:

- Item status is `New`
- All dependencies are `Done`
- Selection is sorted by priority descending, then id ascending

`take-next` transitions the item to `InProgress` and sets `startedAt`.

If no eligible item exists, the loop exits cleanly ("Ralph complete").

### 3. Branch and Worktree Preparation

For the selected item, Ralph creates a task branch using the configured prefix (for example `ralph/task-102`) and prepares an isolated worktree.

Behavior:

- If a remote task branch already exists, Ralph resumes from that branch
- Otherwise Ralph creates the task branch from the configured base branch
- Ralph requires the worktree to be clean before invoking the agent

This supports resuming interrupted work without creating new branches.

### 4. Codex Execution (Initial Attempt or Repair Attempt)

Each task runs in attempts:

- Attempt 1: Ralph writes an execution prompt with the backlog item title/description
- Later attempts: Ralph collects PR feedback and writes a repair prompt

Ralph invokes the agent via `scripts/ralph/agent-adapter.ps1`, which:

- Runs `codex exec` in the task worktree
- Captures stdout/stderr logs and last message
- Writes attempt metadata (`agent.result.json`)

Attempt artifacts are stored under the configured run artifacts root (for example `.ralph/runs/<runId>/<taskId>/attempt-N/`).

### 5. Local Validation and Push

After the agent run, Ralph:

- Runs configured local validation commands (if any)
- Verifies the task branch is still checked out
- Verifies the branch has commits (for new branches)
- Pushes the branch if needed

If these checks fail, the loop exits and the task remains resumable from its current branch/backlog state.

### 6. PR Creation / Reuse and Transition to InReview

Ralph then locates an open PR for the task branch:

- Reuses an existing open PR if present, or
- Creates a new PR targeting the base branch

After PR availability is confirmed, Ralph sets the backlog item from `InProgress` to `InReview` (if it is still `InProgress`).

This makes `InReview` the state representing "work submitted and awaiting checks/review/merge."

### 7. Polling, Repair Loop, and Merge

Ralph polls the PR for:

- Required checks status (via `gh pr checks`)
- Review decision (especially `CHANGES_REQUESTED`)
- Mergeability state

Outcomes:

- Checks pending: keep polling
- Checks failed: enter repair loop
- Review changes requested: enter repair loop
- Checks pass and mergeable: merge PR (unless `-NoMerge`)

Repair loop behavior:

- Collects feedback packet (checks, failed run logs, comments, reviews)
- Sets backlog item from `InReview` back to `InProgress`
- Invokes Codex again with a repair prompt
- Repeats until mergeable or max repair cycles exceeded

On successful merge:

- Ralph verifies merge completion
- Transitions backlog item from `InReview` to `Done`
- Cleans up worktree
- Optionally deletes local/remote task branch (config-driven)

## Backlog States and Transition Rules

### States

- `New`: not started; no timestamps set
- `InProgress`: active implementation/repair work; `startedAt` set, `doneAt` null
- `InReview`: active PR/checks/review stage; `startedAt` set, `doneAt` null
- `Done`: merged/completed; `startedAt` and `doneAt` set

### 1-WIP Rule

At most one item may be active at any time, where active means:

- `InProgress` or `InReview`

This is enforced by backlog runtime validation and by `take-next` refusing to start a new item if one is already active.

### Allowed Transitions

Ralph/backlog CLI only allows these status transitions:

- `New -> InProgress`
- `InProgress -> InReview`
- `InReview -> InProgress` (repair/rework)
- `InReview -> Done`

All other transitions are invalid, including:

- `New -> InReview`
- `New -> Done`
- `InProgress -> Done`
- Any transition out of `Done`

### Timestamp Semantics

Status transitions also control timestamps:

- Entering `InProgress` sets `startedAt` if not already set
- Entering `Done` sets `doneAt` (and ensures `startedAt` exists)
- Non-`Done` states require `doneAt = null`

## Failure and Recovery (High Level)

### CI Failures / Review Changes Requested

When required checks fail or reviewers request changes:

- Ralph treats the task as repairable
- Collects a feedback packet using `scripts/ralph/collect-pr-feedback.ps1`
- Moves status `InReview -> InProgress`
- Re-runs Codex on the same task branch and PR

This preserves task continuity and avoids branch/PR churn.

### Max Repair Cycles

Ralph limits automated repair attempts using `maxRepairCycles` in `.ralph/config.json`.

If the limit is exceeded, Ralph exits with an error for operator intervention. The item is not automatically marked `Done`; backlog/PR state remains as-is and can be resumed later.

### Resume After Interruption

Ralph is designed to resume safely after process interruption:

- Loop lock is reacquired on next run
- Ralph first checks for an active backlog item
- If an active item exists, it resumes that item instead of taking a new one
- If the task branch/PR already exists, Ralph reuses them

This supports restarting after agent crashes, machine restarts, or manual loop termination.

## Key Files and Components

### Backlog and Config

- `.ralph/backlog.json`: task source of truth (items, dependencies, status, timestamps)
- `.ralph/config.json`: Ralph loop operational config (branches, paths, merge behavior, polling, repair limits)

### Loop Orchestrator

- `scripts/ralph.ps1`: main Ralph loop orchestrator (selection, worktree, agent execution, PR polling, repair, merge, completion)

### Agent Adapter

- `scripts/ralph/agent-adapter.ps1`: wrapper that launches Codex, captures logs/artifacts, and standardizes attempt metadata

### Feedback Collector

- `scripts/ralph/collect-pr-feedback.ps1`: gathers PR state, required checks, failed run logs, and comments/reviews into a feedback packet for repair attempts

### Backlog CLI

- `tools/Ralph.BacklogCli/*`: schema/runtime validation, state transitions, and safe backlog mutations (including locking)
- `scripts/ralph/backlog.ps1`: convenience wrapper for invoking the backlog CLI with default backlog/schema paths

## Operational Notes

- Ralph validates backlog integrity before mutation and after each backlog mutation command.
- Ralph writes run/attempt artifacts to support auditability and debugging.
- Ralph intentionally documents and enforces workflow/state transitions rather than embedding task-specific implementation logic in the loop.
