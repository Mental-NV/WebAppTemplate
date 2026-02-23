import { expect, test } from '@playwright/test'

test('authenticated user can create, toggle, and delete a todo', async ({ page }) => {
  const title = `e2e-${Date.now()}`
  const isTodosListGet = (url: string, method: string) =>
    url.includes('/api/v1/todos') && method === 'GET'
  const isTodosCreatePost = (url: string, method: string) =>
    url.includes('/api/v1/todos') && method === 'POST'

  const initialTodosLoad = page.waitForResponse((response) =>
    isTodosListGet(response.url(), response.request().method()))

  await page.goto('/')

  await expect(page.getByText('Signed in')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Sign out' })).toBeVisible()
  await initialTodosLoad

  const createResponse = page.waitForResponse((response) =>
    isTodosCreatePost(response.url(), response.request().method()) && response.status() === 201)
  await page.getByPlaceholder('New todo title...').fill(title)
  await page.getByRole('button', { name: 'Add' }).click()
  await createResponse

  const row = page.locator('li', { hasText: title })
  await expect(row).toBeVisible()

  const labelText = row.locator('label span', { hasText: title })
  const checkbox = row.getByRole('checkbox')
  await checkbox.click()
  await expect(checkbox).toBeChecked()
  await expect(labelText).toHaveClass(/done/)

  await row.getByRole('button', { name: 'Delete' }).click()
  await expect(page.locator('li', { hasText: title })).toHaveCount(0)
})
