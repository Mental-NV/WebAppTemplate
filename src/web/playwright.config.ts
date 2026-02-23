import { defineConfig, devices } from '@playwright/test'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const baseURL = 'https://localhost:5001'
const thisDir = path.dirname(fileURLToPath(import.meta.url))
const authFile = path.resolve(thisDir, 'playwright/.auth/user.json')
const e2eAuthSecret = process.env.E2E_AUTH_SECRET ?? 'local-e2e-secret'
const ciFlag = process.env.CI ? ' -CI' : ''

export default defineConfig({
  testDir: './tests/e2e',
  timeout: 30_000,
  expect: {
    timeout: 10_000
  },
  use: {
    baseURL,
    ignoreHTTPSErrors: true,
    trace: 'on-first-retry'
  },
  webServer: {
    command: `pwsh -NoLogo -NoProfile -File ../../scripts/run.ps1 -PublishOutputDir artifacts/publish/app -E2E${ciFlag}`,
    url: baseURL,
    ignoreHTTPSErrors: true,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    env: {
      ...process.env,
      ASPNETCORE_ENVIRONMENT: 'E2E',
      E2E_AUTH_ENABLED: 'true',
      E2E_AUTH_SECRET: e2eAuthSecret
    }
  },
  projects: [
    {
      name: 'setup',
      testMatch: /auth\.setup\.ts/
    },
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        storageState: authFile
      },
      dependencies: ['setup']
    }
  ]
})
