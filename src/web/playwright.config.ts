import { defineConfig, devices } from '@playwright/test'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const baseURL = process.env.E2E_BASE_URL ?? 'http://localhost:5000'
const runId = process.env.E2E_RUN_ID ?? `${Date.now()}`
const dbConnection = process.env.E2E_DB_PATH ?? `Data Source=AppData\\e2e-${runId}.db`
const e2eJwtSigningKey = process.env.E2E_JWT_SIGNING_KEY ?? 'E2E_SIGNING_KEY_12345678901234567890123456789012'
const webDir = fileURLToPath(new URL('.', import.meta.url))
const repoRoot = path.resolve(webDir, '..', '..')
const apiDir = path.join(repoRoot, 'src', 'api')

export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  retries: 1,
  workers: 1,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL,
    ignoreHTTPSErrors: true,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure'
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] }
    }
  ],
  webServer: {
    command: 'dotnet run --no-launch-profile --urls "http://localhost:5000"',
    cwd: apiDir,
    url: baseURL,
    ignoreHTTPSErrors: true,
    timeout: 120_000,
    reuseExistingServer: false,
    env: {
      ...process.env,
      ASPNETCORE_ENVIRONMENT: 'E2E',
      ConnectionStrings__Default: dbConnection,
      Jwt__SigningKey: e2eJwtSigningKey
    }
  }
})
