import { expect, test as setup } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const thisDir = path.dirname(fileURLToPath(import.meta.url))
const authFile = path.resolve(thisDir, '../../playwright/.auth/user.json')
const e2eAuthSecret = process.env.E2E_AUTH_SECRET ?? 'local-e2e-secret'

setup('create authenticated storage state', async ({ request, browser, baseURL }) => {
  mkdirSync(path.dirname(authFile), { recursive: true })

  const loginResponse = await request.post('/api/v1/test/auth/login', {
    headers: {
      'X-E2E-Auth-Secret': e2eAuthSecret
    },
    data: {
      subject: 'e2e-sub',
      email: 'e2e@example.test',
      name: 'E2E User'
    }
  })

  expect(loginResponse.ok()).toBeTruthy()
  const loginBody = (await loginResponse.json()) as { accessToken: string }
  expect(loginBody.accessToken).toBeTruthy()

  const meResponse = await request.get('/api/v1/auth/me', {
    headers: {
      Authorization: `Bearer ${loginBody.accessToken}`
    }
  })
  expect(meResponse.ok()).toBeTruthy()

  const context = await browser.newContext({ ignoreHTTPSErrors: true })
  const page = await context.newPage()
  await page.goto(baseURL ?? 'https://localhost:5001')
  await page.evaluate((token) => window.localStorage.setItem('access_token', token), loginBody.accessToken)
  await context.storageState({ path: authFile })
  await context.close()
})
