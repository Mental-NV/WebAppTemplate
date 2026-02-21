# Full-stack Web App Template
- ASP.NET Core + Minimal API + Vertical Slices + URL versioning + xUnity
- React + TypeScript + Vite + Vite tests
- Google Auth (JWT)

## Prereqs
- .NET SDK (recommended: .NET 10)
- Node.js 20+ (or 18+)

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

Then set the client id in both SPA and API config.

### Configure SPA env
Copy `.env.example` -> `.env.local` in `src/web`:
```bash
cd src/web
cp .env.example .env.local
```
Set:
- `VITE_GOOGLE_CLIENT_ID=...`

### Configure API settings
Edit `src/api/appsettings.json`:
- `Google:ClientId` should match the SPA client id
- `Jwt:SigningKey` MUST be changed for real apps (32+ bytes)

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

The Vite dev server proxies `/api/*` to `https://localhost:5001` (see `vite.config.ts`).

## Tests
```bash
cd tests/Api.Tests
dotnet test
```

```bash
cd src/web
npm run test
```

### Playwright E2E (local)
Recommended local runner:
```powershell
.\scripts\e2e.ps1
```

Optional flags:
- `-InstallBrowser` (first-time Chromium install)
- `-Headed`
- `-Debug`

What this does:
- builds SPA and copies assets to API `wwwroot` via `.\scripts\build.ps1`
- starts API in `ASPNETCORE_ENVIRONMENT=E2E` on `http://localhost:5000`
- uses a fresh SQLite DB file per run
- uses E2E auth mode (no Google popup automation)

Use `-BaseUrl` (or set `E2E_BASE_URL`) to run E2E against a different URL, including HTTPS.

## API endpoints
### Auth
- `POST /api/v1/auth/google` (exchange Google ID token for app JWT)
- `GET /api/v1/auth/me` (requires Bearer token)

### Todos (requires Bearer token)
- `GET /api/v1/todos`
- `POST /api/v1/todos`
- `PUT /api/v1/todos/{id}`
- `DELETE /api/v1/todos/{id}`

### E2E-only endpoints (`ASPNETCORE_ENVIRONMENT=E2E`)
- `POST /api/v1/e2e/auth/login` (issue local test JWT)
- `POST /api/v1/e2e/reset` (clear todos)

## Testing note
Backend integration tests use a **Test** authentication scheme so protected endpoints can be tested without real JWT/Google.
