import { getAccessToken } from '../auth/authStorage'

export type Todo = {
  id: number
  title: string
  isCompleted: boolean
  createdAtUtc: string
  updatedAtUtc: string | null
}

const base = '' // Vite proxy handles /api -> backend in dev

async function http<T>(input: RequestInfo, init?: RequestInit): Promise<T> {
  const token = getAccessToken()

  const res = await fetch(input, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { 'Authorization': `Bearer ${token}` } : {}),
      ...(init?.headers ?? {})
    }
  })

  if (!res.ok) {
    const txt = await res.text()
    throw new Error(`HTTP ${res.status}: ${txt}`)
  }

  return (await res.json()) as T
}

export async function getTodos(): Promise<Todo[]> {
  return await http<Todo[]>(`${base}/api/v1/todos`)
}

export async function createTodo(title: string): Promise<Todo> {
  return await http<Todo>(`${base}/api/v1/todos`, {
    method: 'POST',
    body: JSON.stringify({ title })
  })
}

export async function updateTodo(id: number, title: string, isCompleted: boolean): Promise<Todo> {
  return await http<Todo>(`${base}/api/v1/todos/${id}`, {
    method: 'PUT',
    body: JSON.stringify({ title, isCompleted })
  })
}

export async function toggleTodo(id: number): Promise<Todo> {
  const current = await http<Todo>(`${base}/api/v1/todos/${id}`)
  return await updateTodo(id, current.title, !current.isCompleted)
}

export async function deleteTodo(id: number): Promise<void> {
  const token = getAccessToken()
  const res = await fetch(`${base}/api/v1/todos/${id}`, {
    method: 'DELETE',
    headers: token ? { 'Authorization': `Bearer ${token}` } : {}
  })

  if (!res.ok && res.status != 204) {
    const txt = await res.text()
    throw new Error(`HTTP ${res.status}: ${txt}`)
  }
}
