import { beforeEach, describe, expect, it, vi } from 'vitest'
import { exchangeGoogleIdToken, me } from '../services/authApi'

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' }
  })
}

describe('authApi', () => {
  const fetchMock = vi.fn()

  beforeEach(() => {
    vi.clearAllMocks()
    fetchMock.mockReset()
    vi.stubGlobal('fetch', fetchMock)
  })

  it('exchangeGoogleIdToken posts idToken payload', async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({
      accessToken: 'jwt',
      expiresAtUtc: '2026-01-01T00:00:00Z',
      user: { subject: 's1', email: 'a@b.com', name: 'A', pictureUrl: null }
    }))

    await exchangeGoogleIdToken('google-token')

    expect(fetchMock).toHaveBeenCalledWith('/api/v1/auth/google', expect.objectContaining({
      method: 'POST',
      body: JSON.stringify({ idToken: 'google-token' }),
      headers: expect.objectContaining({
        'Content-Type': 'application/json'
      })
    }))
  })

  it('me sends bearer token', async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse({
      subject: 's1',
      email: 'a@b.com',
      name: 'A'
    }))

    const user = await me('jwt')

    expect(fetchMock).toHaveBeenCalledWith('/api/v1/auth/me', {
      headers: { Authorization: 'Bearer jwt' }
    })
    expect(user.email).toBe('a@b.com')
  })

  it('throws normalized HTTP error text for exchange', async () => {
    fetchMock.mockResolvedValueOnce(new Response('Denied', { status: 401 }))

    await expect(exchangeGoogleIdToken('bad')).rejects.toThrow('HTTP 401: Denied')
  })
})
