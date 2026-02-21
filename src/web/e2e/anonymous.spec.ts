import { expect, test } from '@playwright/test'
import { resetE2EState } from './helpers'

test.beforeEach(async ({ request }) => {
  await resetE2EState(request)
})

test('anonymous users are prompted to sign in', async ({ page }) => {
  await page.goto('/')

  await expect(page.getByText('Please sign in with Google to access the protected CRUD endpoints.')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Sign in (E2E)' })).toBeVisible()
  await expect(page.getByPlaceholder('New todo title...')).toHaveCount(0)
})
