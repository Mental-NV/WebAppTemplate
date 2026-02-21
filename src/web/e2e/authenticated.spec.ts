import { expect, test } from '@playwright/test'
import { resetE2EState, signInForE2E } from './helpers'

test.beforeEach(async ({ request }) => {
  await resetE2EState(request)
})

test('e2e login and logout flow works', async ({ page }) => {
  await signInForE2E(page)
  await expect(page.getByText('Signed in')).toBeVisible()

  await page.getByRole('button', { name: 'Sign out' }).click()

  await expect(page.getByText('Please sign in with Google to access the protected CRUD endpoints.')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Sign in (E2E)' })).toBeVisible()
})

test('authenticated user can create, toggle, persist, and delete a todo', async ({ page }) => {
  const title = `Playwright Todo ${Date.now()}`

  await signInForE2E(page)

  await page.getByPlaceholder('New todo title...').fill(title)
  await page.getByRole('button', { name: 'Add' }).click()

  const row = page.getByRole('listitem').filter({ hasText: title })
  const checkbox = row.getByRole('checkbox')

  await expect(row).toBeVisible()
  await expect(page.getByText('Total: 1')).toBeVisible()

  await checkbox.click()
  await expect(checkbox).toBeChecked()

  await page.reload()

  const reloadedRow = page.getByRole('listitem').filter({ hasText: title })
  const reloadedCheckbox = reloadedRow.getByRole('checkbox')
  const reloadedDelete = reloadedRow.getByRole('button', { name: 'Delete' })

  await expect(reloadedRow).toBeVisible()
  await expect(reloadedCheckbox).toBeChecked()
  await expect(page.getByText('Completed: 1')).toBeVisible()

  await reloadedDelete.click()
  await expect(page.getByRole('listitem').filter({ hasText: title })).toHaveCount(0)
  await expect(page.getByText('Total: 0')).toBeVisible()
})
