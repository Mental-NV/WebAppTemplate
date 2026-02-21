import { expect, type APIRequestContext, type Page } from '@playwright/test'

export async function resetE2EState(request: APIRequestContext) {
  const res = await request.post('/api/v1/e2e/reset')
  if (!res.ok()) {
    throw new Error(`Reset endpoint failed with ${res.status()}: ${await res.text()}`)
  }
}

export async function signInForE2E(page: Page) {
  await page.goto('/')
  await page.getByRole('button', { name: 'Sign in (E2E)' }).click()
  await expect(page.getByText('Signed in')).toBeVisible()
}
