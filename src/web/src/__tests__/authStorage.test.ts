import { beforeEach, describe, expect, it } from 'vitest'
import { clearAccessToken, getAccessToken, setAccessToken } from '../auth/authStorage'

describe('authStorage', () => {
  beforeEach(() => {
    localStorage.clear()
  })

  it('stores and reads the access token', () => {
    setAccessToken('jwt-123')
    expect(getAccessToken()).toBe('jwt-123')
  })

  it('clears the access token', () => {
    setAccessToken('jwt-123')
    clearAccessToken()
    expect(getAccessToken()).toBeNull()
  })
})
