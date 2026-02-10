import { render, screen } from '@testing-library/react'
import { vi } from 'vitest'
import { AuthProvider } from '../auth/AuthContext'
import TodoPage from '../pages/TodoPage'

// logged out by default
vi.mock('../auth/authStorage', () => ({
  getAccessToken: () => null,
  setAccessToken: () => {},
  clearAccessToken: () => {}
}))

vi.mock('../services/todosApi', () => ({
  getTodos: async () => [],
  createTodo: async (title: string) => ({ id: 1, title, isCompleted: false, createdAtUtc: new Date().toISOString(), updatedAtUtc: null }),
  toggleTodo: async () => ({ id: 1, title: 'x', isCompleted: true, createdAtUtc: new Date().toISOString(), updatedAtUtc: null }),
  deleteTodo: async () => {}
}))

describe('TodoPage', () => {
  it('asks to sign in when not authenticated', async () => {
    render(
      <AuthProvider>
        <TodoPage />
      </AuthProvider>
    )
    expect(await screen.findByText(/Please sign in/i)).toBeInTheDocument()
  })
})
