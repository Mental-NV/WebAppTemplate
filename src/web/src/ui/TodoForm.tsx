import { useState } from 'react'

export default function TodoForm({ onCreate }: { onCreate: (title: string) => Promise<void> | void }) {
  const [title, setTitle] = useState('')

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    const t = title.trim()
    if (!t) return
    await onCreate(t)
    setTitle('')
  }

  return (
    <form className="form" onSubmit={(e) => void submit(e)}>
      <input
        className="input"
        placeholder="New todo title..."
        value={title}
        onChange={(e) => setTitle(e.target.value)}
      />
      <button className="btn" type="submit">Add</button>
    </form>
  )
}
