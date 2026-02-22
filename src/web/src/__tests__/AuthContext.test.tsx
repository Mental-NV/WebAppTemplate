import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { vi } from 'vitest'
import { AuthProvider, useAuth } from '../auth/AuthContext'

const authStorageMocks = vi.hoisted(() => ({
  getAccessToken: vi.fn<() => string | null>(),
  setAccessToken: vi.fn<(token: string) => void>(),
  clearAccessToken: vi.fn<() => void>()
}))

const authApiMocks = vi.hoisted(() => ({
  exchangeGoogleIdToken: vi.fn(),
  me: vi.fn()
}))

vi.mock('../auth/authStorage', () => authStorageMocks)
vi.mock('../services/authApi', () => authApiMocks)

function Harness() {
  const auth = useAuth()

  return (
    <div>
      <div data-testid="token">{auth.accessToken ?? 'null'}</div>
      <div data-testid="user-email">{auth.user?.email ?? 'null'}</div>
      <div data-testid="authed">{String(auth.isAuthenticated)}</div>
      <button onClick={() => void auth.loginWithGoogleIdToken('google-id-token')}>Login</button>
      <button onClick={() => auth.logout()}>Logout</button>
      <button onClick={() => void auth.refreshMe()}>Refresh</button>
    </div>
  )
}

describe('AuthContext', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    authStorageMocks.getAccessToken.mockReturnValue(null)
    authApiMocks.exchangeGoogleIdToken.mockResolvedValue({
      accessToken: 'app-jwt',
      expiresAtUtc: '2026-01-01T00:00:00Z',
      user: { subject: 'sub-1', email: 'user@example.com', name: 'User', pictureUrl: null }
    })
    authApiMocks.me.mockResolvedValue({
      subject: 'sub-1',
      email: 'user@example.com',
      name: 'User'
    })
  })

  it('initializes unauthenticated when no stored token exists', async () => {
    render(
      <AuthProvider>
        <Harness />
      </AuthProvider>
    )

    expect(screen.getByTestId('token')).toHaveTextContent('null')
    expect(screen.getByTestId('authed')).toHaveTextContent('false')
    await waitFor(() => expect(authApiMocks.me).not.toHaveBeenCalled())
  })

  it('loads user on mount when a stored token exists', async () => {
    authStorageMocks.getAccessToken.mockReturnValue('stored-token')

    render(
      <AuthProvider>
        <Harness />
      </AuthProvider>
    )

    expect(screen.getByTestId('authed')).toHaveTextContent('true')
    await waitFor(() => expect(authApiMocks.me).toHaveBeenCalledWith('stored-token'))
    expect(screen.getByTestId('user-email')).toHaveTextContent('user@example.com')
  })

  it('clears invalid stored token when me fails on mount', async () => {
    authStorageMocks.getAccessToken.mockReturnValue('bad-token')
    authApiMocks.me.mockRejectedValueOnce(new Error('401'))

    render(
      <AuthProvider>
        <Harness />
      </AuthProvider>
    )

    await waitFor(() => expect(authStorageMocks.clearAccessToken).toHaveBeenCalled())
    expect(screen.getByTestId('token')).toHaveTextContent('null')
    expect(screen.getByTestId('user-email')).toHaveTextContent('null')
    expect(screen.getByTestId('authed')).toHaveTextContent('false')
  })

  it('logs in with exchanged token and hydrates user from the new token', async () => {
    render(
      <AuthProvider>
        <Harness />
      </AuthProvider>
    )

    fireEvent.click(screen.getByText('Login'))

    await waitFor(() => expect(authApiMocks.exchangeGoogleIdToken).toHaveBeenCalledWith('google-id-token'))
    await waitFor(() => expect(authStorageMocks.setAccessToken).toHaveBeenCalledWith('app-jwt'))
    await waitFor(() => expect(authApiMocks.me).toHaveBeenCalledWith('app-jwt'))
    expect(screen.getByTestId('token')).toHaveTextContent('app-jwt')
    expect(screen.getByTestId('user-email')).toHaveTextContent('user@example.com')
    expect(screen.getByTestId('authed')).toHaveTextContent('true')
  })

  it('logs out and clears token + user', async () => {
    authStorageMocks.getAccessToken.mockReturnValue('stored-token')

    render(
      <AuthProvider>
        <Harness />
      </AuthProvider>
    )

    await waitFor(() => expect(authApiMocks.me).toHaveBeenCalled())
    fireEvent.click(screen.getByText('Logout'))

    expect(authStorageMocks.clearAccessToken).toHaveBeenCalled()
    expect(screen.getByTestId('token')).toHaveTextContent('null')
    expect(screen.getByTestId('user-email')).toHaveTextContent('null')
    expect(screen.getByTestId('authed')).toHaveTextContent('false')
  })
})
