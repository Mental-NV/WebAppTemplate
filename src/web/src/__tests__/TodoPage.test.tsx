import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { vi } from 'vitest'
import TodoPage from '../pages/TodoPage'

const state = vi.hoisted(() => ({
  auth: {
    isAuthenticated: false
  },
  todosApi: {
    getTodos: vi.fn(),
    createTodo: vi.fn(),
    toggleTodo: vi.fn(),
    deleteTodo: vi.fn()
  }
}))

vi.mock('../auth/AuthContext', () => ({
  useAuth: () => state.auth
}))

vi.mock('../services/todosApi', () => ({
  getTodos: (...args: any[]) => state.todosApi.getTodos(...args),
  createTodo: (...args: any[]) => state.todosApi.createTodo(...args),
  toggleTodo: (...args: any[]) => state.todosApi.toggleTodo(...args),
  deleteTodo: (...args: any[]) => state.todosApi.deleteTodo(...args)
}))

function makeTodo(id: number, title: string, isCompleted = false) {
  return {
    id,
    title,
    isCompleted,
    createdAtUtc: '2026-01-01T00:00:00Z',
    updatedAtUtc: null as string | null
  }
}

describe('TodoPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    state.auth.isAuthenticated = false
    state.todosApi.getTodos.mockResolvedValue([])
    state.todosApi.createTodo.mockImplementation(async (title: string) => makeTodo(99, title, false))
    state.todosApi.toggleTodo.mockImplementation(async (id: number) => makeTodo(id, `Todo ${id}`, true))
    state.todosApi.deleteTodo.mockResolvedValue(undefined)
  })

  it('asks to sign in when not authenticated', async () => {
    render(<TodoPage />)
    expect(await screen.findByText(/Please sign in/i)).toBeInTheDocument()
    expect(state.todosApi.getTodos).not.toHaveBeenCalled()
  })

  it('loads todos when authenticated and shows loading state + counts', async () => {
    state.auth.isAuthenticated = true

    let resolveTodos!: (value: ReturnType<typeof makeTodo>[]) => void
    const todosPromise = new Promise<ReturnType<typeof makeTodo>[]>((resolve) => {
      resolveTodos = resolve
    })
    state.todosApi.getTodos.mockReturnValueOnce(todosPromise)

    render(<TodoPage />)

    expect(screen.getByText(/Loading/i)).toBeInTheDocument()
    resolveTodos([makeTodo(1, 'Task A', false), makeTodo(2, 'Task B', true)])

    expect(await screen.findByText('Task A')).toBeInTheDocument()
    expect(screen.getByText('Task B')).toBeInTheDocument()
    expect(screen.queryByText(/Loading/i)).not.toBeInTheDocument()
    expect(screen.getByText('Total: 2')).toBeInTheDocument()
    expect(screen.getByText('Completed: 1')).toBeInTheDocument()
  })

  it('shows an error when loading todos fails', async () => {
    state.auth.isAuthenticated = true
    state.todosApi.getTodos.mockRejectedValueOnce(new Error('Boom'))

    render(<TodoPage />)

    expect(await screen.findByText('Boom')).toBeInTheDocument()
  })

  it('creates, toggles, and deletes todos while keeping counters in sync', async () => {
    state.auth.isAuthenticated = true
    state.todosApi.getTodos.mockResolvedValueOnce([makeTodo(1, 'Task A', false)])
    state.todosApi.createTodo.mockResolvedValueOnce(makeTodo(2, 'New task', false))
    state.todosApi.toggleTodo.mockResolvedValueOnce(makeTodo(2, 'New task', true))
    state.todosApi.deleteTodo.mockResolvedValueOnce(undefined)

    render(<TodoPage />)

    expect(await screen.findByText('Task A')).toBeInTheDocument()
    expect(screen.getByText('Total: 1')).toBeInTheDocument()
    expect(screen.getByText('Completed: 0')).toBeInTheDocument()

    fireEvent.change(screen.getByPlaceholderText(/new todo title/i), { target: { value: 'New task' } })
    fireEvent.click(screen.getByRole('button', { name: /add/i }))

    await waitFor(() => expect(state.todosApi.createTodo).toHaveBeenCalledWith('New task'))
    expect(screen.getByText('New task')).toBeInTheDocument()
    expect(screen.getByText('Total: 2')).toBeInTheDocument()
    expect(screen.getByText('Completed: 0')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('checkbox', { name: /new task/i }))

    await waitFor(() => expect(state.todosApi.toggleTodo).toHaveBeenCalledWith(2))
    expect(screen.getByText('Completed: 1')).toBeInTheDocument()
    expect(screen.getByText('New task')).toHaveClass('done')

    fireEvent.click(screen.getAllByRole('button', { name: /delete/i })[0])

    await waitFor(() => expect(state.todosApi.deleteTodo).toHaveBeenCalled())
    expect(screen.getByText('Total: 1')).toBeInTheDocument()
  })
})
