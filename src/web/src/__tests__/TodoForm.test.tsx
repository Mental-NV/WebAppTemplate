import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { vi } from 'vitest'
import TodoForm from '../ui/TodoForm'

describe('TodoForm', () => {
  it('trims the title and clears input after successful submit', async () => {
    const onCreate = vi.fn().mockResolvedValue(undefined)
    render(<TodoForm onCreate={onCreate} />)

    const input = screen.getByPlaceholderText(/new todo title/i)
    fireEvent.change(input, { target: { value: '  Buy milk  ' } })
    fireEvent.click(screen.getByRole('button', { name: /add/i }))

    await waitFor(() => expect(onCreate).toHaveBeenCalledWith('Buy milk'))
    expect(input).toHaveValue('')
  })

  it('does not submit whitespace-only input', async () => {
    const onCreate = vi.fn()
    render(<TodoForm onCreate={onCreate} />)

    fireEvent.change(screen.getByPlaceholderText(/new todo title/i), { target: { value: '   ' } })
    fireEvent.click(screen.getByRole('button', { name: /add/i }))

    await waitFor(() => expect(onCreate).not.toHaveBeenCalled())
  })
})
