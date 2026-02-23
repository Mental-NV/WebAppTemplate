# Full-stack Web App Template
- ASP.NET Core + Minimal API + Vertical Slices + URL versioning + xUnity
- React + TypeScript + Vite + Vite tests
- Google Auth (JWT)

## Prereqs
- .NET SDK (recommended: .NET 10)
- Node.js 20+ (or 18+)
- PowerShell 7+ (`pwsh`) for cross-platform scripts

## Solution layout
- Backend API: `src/api`
- Frontend SPA: `src/web`
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
```bash
cd tests/Api.Tests
dotnet test
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
  - `scripts/run.ps1` (smoke step launches it and probes `https://localhost:5001/`)
- HTTPS cert materialization happens in `scripts/run.ps1` during the smoke step (required there)
- `scripts/ci.ps1` also attempts cert materialization, but skips when cert secrets are not provided

GitHub Actions secrets used by the smoke step:
- `GOOGLE__CLIENTID` (reused for both `Google__ClientId` and `VITE_GOOGLE_CLIENT_ID`)
- `JWT__SIGNINGKEY`
- `HTTPS_CERT_PFX_BASE64`
- `HTTPS_CERT_PASSWORD`

## API endpoints
### Auth
- `POST /api/v1/auth/google` (exchange Google ID token for app JWT)
- `GET /api/v1/auth/me` (requires Bearer token)

### Todos (requires Bearer token)
- `GET /api/v1/todos`
- `POST /api/v1/todos`
- `PUT /api/v1/todos/{id}`
- `DELETE /api/v1/todos/{id}`


## Testing note
Backend integration tests use a **Test** authentication scheme so protected endpoints can be tested without real JWT/Google.
