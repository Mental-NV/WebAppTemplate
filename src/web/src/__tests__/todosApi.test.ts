import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createTodo, deleteTodo, getTodos, toggleTodo } from '../services/todosApi'

const authStorageMocks = vi.hoisted(() => ({
  getAccessToken: vi.fn<() => string | null>()
}))

vi.mock('../auth/authStorage', () => authStorageMocks)

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' }
  })
}

describe('todosApi', () => {
  const fetchMock = vi.fn()

  beforeEach(() => {
    vi.clearAllMocks()
    authStorageMocks.getAccessToken.mockReturnValue('jwt-token')
    fetchMock.mockReset()
    vi.stubGlobal('fetch', fetchMock)
  })

  it('getTodos sends bearer token when available', async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse([]))

    await getTodos()

    expect(fetchMock).toHaveBeenCalledWith('/api/v1/todos', expect.objectContaining({
      headers: expect.objectContaining({
        Authorization: 'Bearer jwt-token',
        'Content-Type': 'application/json'
      })
    }))
  })

  it('createTodo posts JSON payload', async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({
      id: 1,
      title: 'Task',
      isCompleted: false,
      createdAtUtc: '2026-01-01T00:00:00Z',
      updatedAtUtc: null
    }))

    await createTodo('Task')

    expect(fetchMock).toHaveBeenCalledWith('/api/v1/todos', expect.objectContaining({
      method: 'POST',
      body: JSON.stringify({ title: 'Task' }),
      headers: expect.objectContaining({
        'Content-Type': 'application/json'
      })
    }))
  })

  it('throws normalized HTTP error text', async () => {
    fetchMock.mockResolvedValueOnce(new Response('Bad request', { status: 400 }))

    await expect(getTodos()).rejects.toThrow('HTTP 400: Bad request')
  })

  it('toggleTodo reads current todo then updates inverted completion', async () => {
    fetchMock
      .mockResolvedValueOnce(jsonResponse({
        id: 5,
        title: 'Toggle me',
        isCompleted: false,
        createdAtUtc: '2026-01-01T00:00:00Z',
        updatedAtUtc: null
      }))
      .mockResolvedValueOnce(jsonResponse({
        id: 5,
        title: 'Toggle me',
        isCompleted: true,
        createdAtUtc: '2026-01-01T00:00:00Z',
        updatedAtUtc: '2026-01-02T00:00:00Z'
      }))

    const result = await toggleTodo(5)

    expect(fetchMock).toHaveBeenNthCalledWith(1, '/api/v1/todos/5', expect.any(Object))
    expect(fetchMock).toHaveBeenNthCalledWith(2, '/api/v1/todos/5', expect.objectContaining({
      method: 'PUT',
      body: JSON.stringify({ title: 'Toggle me', isCompleted: true })
    }))
    expect(result.isCompleted).toBe(true)
  })

  it('deleteTodo succeeds on 204 and sends bearer token', async () => {
    fetchMock.mockResolvedValueOnce(new Response(null, { status: 204 }))

    await expect(deleteTodo(7)).resolves.toBeUndefined()
    expect(fetchMock).toHaveBeenCalledWith('/api/v1/todos/7', expect.objectContaining({
      method: 'DELETE',
      headers: { Authorization: 'Bearer jwt-token' }
    }))
  })

  it('deleteTodo throws on non-204 failure', async () => {
    fetchMock.mockResolvedValueOnce(new Response('Nope', { status: 500 }))

    await expect(deleteTodo(7)).rejects.toThrow('HTTP 500: Nope')
  })
})
