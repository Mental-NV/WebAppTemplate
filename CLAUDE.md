# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Full-stack web application template using ASP.NET Core Minimal API (backend) + React/Vite (frontend) with SQLite database.

## Common Commands

### Backend (API)
```bash
cd src/api
dotnet run                    # Run API at http://localhost:5000
dotnet test                   # Run tests from solution root
```

### Frontend (SPA)
```bash
cd src/web
npm install
npm run dev                   # Run at http://localhost:5173
npm run test                  # Run tests once
npm run test:watch            # Watch mode
```

### Run all tests
```bash
dotnet test
```

## Architecture

### Backend (src/api)
- **Pattern**: Vertical Slices - features organized in `src/api/Features/`
- **API Style**: Minimal APIs with route grouping for URL versioning (`/api/v1/`)
- **Database**: SQLite with Entity Framework Core
- **Authentication**: Google OAuth (SPA) + JWT bearer tokens (API-issued)
- **Testing**: xUnit integration tests with custom `TestAuthHandler` for authenticated test requests

### Frontend (src/web)
- **Framework**: React 19 with TypeScript
- **Build**: Vite 6 with proxy to API (`/api/*` → `http://localhost:5000`)
- **Testing**: Vitest with jsdom environment

## Key Configuration

### Environment Variables
- **Frontend**: `src/web/.env.local` - set `VITE_GOOGLE_CLIENT_ID`
- **Backend**: `src/api/appsettings.json` - configure `Google:ClientId` and `Jwt:SigningKey`

### Authentication Flow
1. SPA uses Google Sign-In to get a Google ID Token
2. SPA calls `POST /api/v1/auth/google` to exchange for app JWT
3. SPA includes JWT in `Authorization: Bearer <token>` header

## API Endpoints

- `POST /api/v1/auth/google` - Exchange Google ID token for app JWT
- `GET /api/v1/auth/me` - Get current user (protected)
- `GET/POST/PUT/DELETE /api/v1/todos` - Todo CRUD (protected)

Swagger UI available at http://localhost:5000/swagger in development.
