import { useEffect, useMemo, useState } from 'react'
import { createTodo, deleteTodo, getTodos, toggleTodo, type Todo } from '../services/todosApi'
import TodoForm from '../ui/TodoForm'
import { useAuth } from '../auth/AuthContext'

export default function TodoPage() {
  const auth = useAuth()
  const [items, setItems] = useState<Todo[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const completedCount = useMemo(() => items.filter(x => x.isCompleted).length, [items])

  async function refresh() {
    if (!auth.isAuthenticated) {
      setItems([])
      return
    }

    setLoading(true)
    setError(null)
    try {
      const data = await getTodos()
      setItems(data)
    } catch (e: any) {
      setError(e?.message ?? 'Failed to load')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { void refresh() }, [auth.isAuthenticated])

  async function onCreate(title: string) {
    const created = await createTodo(title)
    setItems(prev => [created, ...prev])
  }

  async function onToggle(id: number) {
    const updated = await toggleTodo(id)
    setItems(prev => prev.map(x => x.id === id ? updated : x))
  }

  async function onDelete(id: number) {
    await deleteTodo(id)
    setItems(prev => prev.filter(x => x.id !== id))
  }

  if (!auth.isAuthenticated) {
    return (
      <section className="card">
        <p>Please sign in with Google to access the protected CRUD endpoints.</p>
      </section>
    )
  }

  return (
    <section>
      <div className="meta">
        <span>Total: {items.length}</span>
        <span>Completed: {completedCount}</span>
      </div>

      <TodoForm onCreate={onCreate} />

      {loading && <p>Loading...</p>}
      {error && <p className="error">{error}</p>}

      <ul className="list">
        {items.map(item => (
          <li key={item.id} className="row">
            <label className="rowLeft">
              <input
                type="checkbox"
                checked={item.isCompleted}
                onChange={() => void onToggle(item.id)}
              />
              <span className={item.isCompleted ? 'done' : ''}>{item.title}</span>
            </label>

            <button className="btn danger" onClick={() => void onDelete(item.id)}>Delete</button>
          </li>
        ))}
      </ul>
    </section>
  )
}
