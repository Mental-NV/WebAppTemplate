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
- If you run the built SPA from the API (`http://localhost:5000` / `https://localhost:5001`), also add:
  - `http://localhost:5000`
  - `https://localhost:5001`

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
Swagger (dev only): http://localhost:5000/swagger

### 2) Frontend
```bash
cd src/web
npm install
npm run dev
```
Vite dev server: http://localhost:5173

If you are serving the SPA from the API on port `5000/5001`, build the frontend after changing `src/web/.env.local`:
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
