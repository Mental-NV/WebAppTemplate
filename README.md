# Full-stack Web App Template
[![CI](https://github.com/Mental-NV/WebAppTemplate/actions/workflows/ci.yml/badge.svg)](https://github.com/Mental-NV/WebAppTemplate/actions/workflows/ci.yml)
- ASP.NET Core + Minimal API + Vertical Slices + URL versioning + xUnity
- React + TypeScript + Vite + Vitest + Playwright E2E tests
- Google Auth (JWT)

## Prereqs
- .NET SDK (recommended: .NET 10)
- Node.js 20+ (or 18+)
- PowerShell 7+ (`pwsh`) for cross-platform scripts

## Solution layout
- Backend API: `src/api`
- Frontend SPA: `src/web`
- Frontend E2E tests (Playwright): `src/web/tests/e2e`
- Backend tests (xUnit): `tests/Api.Tests`

## Google Auth (SPA -> API) + JWT bearer
This template uses:
1) **Google Sign-In in SPA** to obtain a **Google ID Token (JWT)**.
2) SPA sends the ID token to the API: `POST /api/v1/auth/google`.
3) API validates the Google ID token and returns an **app-issued JWT access token**.
4) SPA stores the access token and sends it as `Authorization: Bearer <token>` on API calls.

### Configure Google OAuth client
Create a Google OAuth client (Google Cloud Console) and add your dev origin:
- Authorized JavaScript origins: `http://localhost:5173`
- If you run the built SPA from the API, also add:
  - `https://localhost:5001`

Then set the client id via the secrets-loading flow below (`dotnet user-secrets`), which also initializes `VITE_GOOGLE_CLIENT_ID` for script-driven CI/build/run.

## Secrets Loading (`dotnet user-secrets` -> env vars)
`scripts/secrets.local.ps1` reads `dotnet user-secrets list` from `src/api`, parses the output, and exports the env vars required by `scripts/ci.ps1` / `scripts/run.ps1`. For HTTPS, the source-of-truth secrets are `HTTPS_CERT_PFX_BASE64` and `HTTPS_CERT_PASSWORD`; scripts derive/materialize the ASP.NET Kestrel certificate env vars from them.

Required secrets (stored in `dotnet user-secrets`):
- `Jwt__SigningKey`
- `Google__ClientId`
- `HTTPS_CERT_PASSWORD`
- `HTTPS_CERT_PFX_BASE64`

Special case:
- `VITE_GOOGLE_CLIENT_ID` is initialized automatically from `Google__ClientId`

Set them (API project already has a `UserSecretsId`):
```powershell
cd src/api
dotnet user-secrets set "Jwt__SigningKey" "replace-with-a-real-signing-key-at-least-32-chars"
dotnet user-secrets set "Google__ClientId" "your-google-client-id.apps.googleusercontent.com"
dotnet user-secrets set "HTTPS_CERT_PASSWORD" "changeit"
```

HTTPS cert example (materialized by scripts to `.certs/webapptemplate-dev.pfx`):
```powershell
cd ../..
New-Item -ItemType Directory -Force ./.certs | Out-Null
dotnet dev-certs https -ep ./.certs/webapptemplate-dev.pfx -p "changeit"
```

Set `HTTPS_CERT_PFX_BASE64` from the exported `.pfx` (PowerShell):
```powershell
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path ./.certs/webapptemplate-dev.pfx))
$b64 = [Convert]::ToBase64String($bytes)
cd src/api
dotnet user-secrets set "HTTPS_CERT_PFX_BASE64" $b64
```

CI/local automation materializes the certificate file from:
- `HTTPS_CERT_PFX_BASE64` (base64-encoded `.pfx`)
- `HTTPS_CERT_PASSWORD`

`scripts/ci.ps1` (when secrets are available) and `scripts/run.ps1` materialize to `.certs/webapptemplate-dev.pfx` and initialize:
- `ASPNETCORE_Kestrel__Certificates__Default__Path`
- `ASPNETCORE_Kestrel__Certificates__Default__Password`

If you run the web app directly with `npm run dev`, also provide `VITE_GOOGLE_CLIENT_ID` to the shell (or create `src/web/.env.local`). `scripts/ci.ps1` and `scripts/run.ps1` load it automatically via `scripts/secrets.local.ps1`.

## Run (dev)
### 1) Backend
```bash
cd src/api
dotnet run
```
Swagger (dev only): https://localhost:5001/swagger

### 2) Frontend
```bash
cd src/web
npm install
npm run dev
```
Vite dev server: http://localhost:5173

If you are serving the SPA from the API on `https://localhost:5001`, build the frontend after changing `src/web/.env.local`:
```bash
cd src/web
npm run build
```

The Vite dev server proxies `/api/*` to `http://localhost:5000` (see `vite.config.ts`).

## Tests
### Backend integration tests (xUnit)
```bash
cd tests/Api.Tests
dotnet test
```

### Frontend unit tests (Vitest)
```bash
cd src/web
npm test
```

### Frontend E2E tests (Playwright)
Prereqs:
- Run `scripts/build.ps1`, `scripts/ci.ps1`, and `scripts/publish.ps1` first (or `scripts/pipeline.ps1`)
- HTTPS cert secrets available (same as `scripts/run.ps1`)

Install Playwright browser:
```bash
cd src/web
npm run test:e2e:install
```

Run E2E:
```powershell
cd src/web
$env:E2E_AUTH_SECRET = "local-e2e-secret" # optional locally; defaults if omitted
npm run test:e2e:ci
```

Notes: 
- Playwright starts the published app via `scripts/run.ps1 -E2E` on `https://localhost:5001`
- E2E auth uses a test-only endpoint (`POST /api/v1/test/auth/login`) available only when `ASPNETCORE_ENVIRONMENT=E2E`
- The setup test stores the app JWT in SPA local storage key `access_token` and reuses Playwright `storageState`

## Ralph Loop (experimental, full-auto task queue)
Ralph is a single-agent queue runner that processes backlog items one by one:
- claims the next eligible task from `.ralph/backlog.json`
- creates/uses a task branch (`ralph/<task-id>`)
- invokes Codex CLI through `scripts/ralph/agent-adapter.ps1`
- creates/updates a PR, watches CI/reviews, collects failure feedback, and retries
- merges a green PR and marks the backlog item `Done`

### Backlog format
Files:
- Backlog: `.ralph/backlog.json`
- Schema: `.ralph/backlog.schema.json`
- Ralph config: `.ralph/config.json`

Backlog item fields:
- `id`
- `title`
- `description` (full task details sent to the agent)
- `priority` (higher runs first)
- `dependencies` (task ids that must be `Done`)
- `status` (`New | InProgress | InReview | Done`)
- `startedAt`
- `doneAt`

Rule:
- Ralph enforces `1 WIP` (`InProgress`/`InReview`) at a time.

### Backlog CLI (JSON output, script-friendly)
Wrapper script:
```powershell
pwsh -NoLogo -NoProfile -File ./scripts/ralph/backlog.ps1 validate
```

Examples:
```powershell
pwsh -NoLogo -NoProfile -File ./scripts/ralph/backlog.ps1 list
pwsh -NoLogo -NoProfile -File ./scripts/ralph/backlog.ps1 next
pwsh -NoLogo -NoProfile -File ./scripts/ralph/backlog.ps1 take-next
pwsh -NoLogo -NoProfile -File ./scripts/ralph/backlog.ps1 status set --id task-001 --to InReview
pwsh -NoLogo -NoProfile -File ./scripts/ralph/backlog.ps1 add --id task-010 --title "Task title" --description "Detailed task description" --priority 50
```

### Backlog CLI smoke test (safe: uses a temp copy)
```powershell
pwsh -NoLogo -NoProfile -File ./scripts/ralph/smoke-backlog-cli.ps1
```

What it checks:
- schema/runtime validation
- queue selection (`next`, `take-next`)
- status transitions (`InProgress`, `InReview`, `Done`)
- invalid transition error contract
- `add` and `show`

### Run Ralph loop
Prereqs:
- clean repo root checkout on `main`
- `gh` CLI installed + authenticated (`gh auth status`)
- Codex CLI available on PATH (`codex`) or set `RALPH_CODEX_COMMAND`

Run one task and stop after PR reaches green/merge (default behavior):
```powershell
pwsh -NoLogo -NoProfile -File ./scripts/ralph.ps1 -Once
```

Useful modes:
```powershell
# Resume only the active task (fail if none)
pwsh -NoLogo -NoProfile -File ./scripts/ralph.ps1 -ResumeOnly

# Stop at green PR without merging (leave item InReview)
pwsh -NoLogo -NoProfile -File ./scripts/ralph.ps1 -NoMerge
```

## Scripts (`pwsh`, Windows/Linux)
Run from repo root.

Defaults:
- Local script configuration default is `Debug` (`build.ps1`, `ci.ps1`, `publish.ps1`, `pipeline.ps1`)
- Remote GitHub Actions explicitly uses `Release`

Stage contract:
- `build.ps1` -> `ci.ps1` -> `publish.ps1` -> `run.ps1`
- Each later stage assumes the earlier stage(s) already completed and reuses their outputs

### Build stage (restore + build solution/web + copy SPA to `src/api/wwwroot`)
```powershell
pwsh -NoLogo -NoProfile -File ./scripts/build.ps1
```

### CI checks stage (API unit + integration + web tests; assumes `build.ps1` already ran)
```powershell
pwsh -NoLogo -NoProfile -File ./scripts/ci.ps1
```
CI HTTPS cert materialization inputs (optional in `ci.ps1`, required in `run.ps1`):
- `HTTPS_CERT_PFX_BASE64`
- `HTTPS_CERT_PASSWORD`
- Optional local secrets loader (default): `scripts/secrets.local.ps1` (`dotnet user-secrets`)

### Publish stage (single artifact; assumes `build.ps1` and `ci.ps1` already ran)
```powershell
pwsh -NoLogo -NoProfile -File ./scripts/publish.ps1
```
Default output: `artifacts/publish/app`

### Run stage (runs published app; assumes `publish.ps1` already ran)
```powershell
pwsh -NoLogo -NoProfile -File ./scripts/run.ps1
```
Published app HTTPS endpoint: `https://localhost:5001`

E2E mode (enables test-only auth endpoint and forces `ASPNETCORE_ENVIRONMENT=E2E`):
```powershell
pwsh -NoLogo -NoProfile -File ./scripts/run.ps1 -E2E
```
Optional E2E auth secret override:
```powershell
pwsh -NoLogo -NoProfile -File ./scripts/run.ps1 -E2E -E2EAuthSecret "my-local-secret"
```

### Pipeline wrapper (runs stages sequentially)
```powershell
pwsh -NoLogo -NoProfile -File ./scripts/pipeline.ps1
```
Useful examples:
- Run everything in local defaults (`Debug`): `./scripts/pipeline.ps1`
- Run all stages in `Release`: `./scripts/pipeline.ps1 -Configuration Release`
- Stop before starting the app: `./scripts/pipeline.ps1 -SkipRun`
- Reuse an existing publish and run only: `./scripts/pipeline.ps1 -SkipBuild -SkipCi -SkipPublish`

## GitHub Actions
Workflow: `.github/workflows/ci.yml`

- Runs on `pull_request`
- Runs on `push` to `main`
- Matrix: `ubuntu-latest`, `windows-latest`
- Single matrix job executes (in order, with `-Configuration Release`):
  - `scripts/build.ps1`
  - `scripts/ci.ps1`
  - `scripts/publish.ps1`
  - Playwright browser install (`chromium`)
  - Playwright E2E (`npx playwright test --project=chromium`) which launches `scripts/run.ps1 -E2E`
- HTTPS cert materialization happens in `scripts/run.ps1` during the Playwright E2E run (required there)
- `scripts/ci.ps1` also attempts cert materialization, but skips when cert secrets are not provided

GitHub Actions secrets used by the Playwright E2E step:
- `JWT__SIGNINGKEY`
- `HTTPS_CERT_PFX_BASE64`
- `HTTPS_CERT_PASSWORD`

GitHub Actions env used by CI:
- `Google__ClientId` / `VITE_GOOGLE_CLIENT_ID` are set to CI dummy values in workflow env (Google UI login is not used in E2E)
- `E2E_AUTH_SECRET` is provided to the Playwright run and sent as `X-E2E-Auth-Secret`

## API endpoints
### Auth
- `POST /api/v1/auth/google` (exchange Google ID token for app JWT)
- `GET /api/v1/auth/me` (requires Bearer token)

### Test Auth (E2E environment only)
- `POST /api/v1/test/auth/login` (mints app JWT for Playwright E2E; requires `X-E2E-Auth-Secret`)

### Todos (requires Bearer token)
- `GET /api/v1/todos`
- `POST /api/v1/todos`
- `PUT /api/v1/todos/{id}`
- `DELETE /api/v1/todos/{id}`


## Testing note
Backend integration tests use a **Test** authentication scheme so protected endpoints can be tested without real JWT/Google.

Playwright E2E tests do not click Google Sign-In. They use an **E2E-only** API endpoint to mint an app JWT, then preload SPA auth state (`localStorage['access_token']`) via Playwright `storageState`.
