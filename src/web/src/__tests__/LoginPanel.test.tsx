import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { vi } from 'vitest'
import LoginPanel from '../ui/LoginPanel'

const state = vi.hoisted(() => ({
  hasGoogleClientId: true,
  auth: {
    isAuthenticated: false,
    user: null as null | { email: string | null },
    loginWithGoogleIdToken: vi.fn<(token: string) => Promise<void>>(),
    logout: vi.fn<() => void>()
  },
  lastGoogleProps: null as any
}))

vi.mock('../auth/AuthContext', () => ({
  useAuth: () => state.auth
}))

vi.mock('../config/google', () => ({
  get hasGoogleClientId() {
    return state.hasGoogleClientId
  }
}))

vi.mock('@react-oauth/google', () => ({
  GoogleLogin: (props: any) => {
    state.lastGoogleProps = props
    return (
      <button onClick={() => void props.onSuccess?.({ credential: 'google-cred' })}>
        GoogleLogin Mock
      </button>
    )
  }
}))

describe('LoginPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    state.hasGoogleClientId = true
    state.auth.isAuthenticated = false
    state.auth.user = null
    state.auth.loginWithGoogleIdToken.mockResolvedValue(undefined)
    state.lastGoogleProps = null
  })

  it('renders signed-in state and signs out', () => {
    state.auth.isAuthenticated = true
    state.auth.user = { email: 'user@example.com' }

    render(<LoginPanel />)

    expect(screen.getByText(/signed in/i)).toBeInTheDocument()
    expect(screen.getByText('user@example.com')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /sign out/i }))
    expect(state.auth.logout).toHaveBeenCalled()
  })

  it('shows configuration message when Google auth is not configured', () => {
    state.hasGoogleClientId = false

    render(<LoginPanel />)

    expect(screen.getByText(/Google auth is not configured/i)).toBeInTheDocument()
    expect(screen.queryByText(/GoogleLogin Mock/i)).not.toBeInTheDocument()
  })

  it('passes credential from GoogleLogin to auth login', async () => {
    render(<LoginPanel />)

    fireEvent.click(screen.getByRole('button', { name: /googlelogin mock/i }))

    await waitFor(() => expect(state.auth.loginWithGoogleIdToken).toHaveBeenCalledWith('google-cred'))
  })

  it('ignores Google success callback without a credential', async () => {
    render(<LoginPanel />)

    await waitFor(() => expect(state.lastGoogleProps).toBeTruthy())
    await state.lastGoogleProps.onSuccess({ credential: undefined })

    expect(state.auth.loginWithGoogleIdToken).not.toHaveBeenCalled()
  })
})
