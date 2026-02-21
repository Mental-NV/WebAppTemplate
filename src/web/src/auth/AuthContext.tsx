import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import { clearAccessToken, getAccessToken, setAccessToken } from './authStorage'
import { exchangeGoogleIdToken, me, type AuthUser } from '../services/authApi'

type AuthState = {
  accessToken: string | null
  user: AuthUser | null
  isAuthenticated: boolean
  loginWithGoogleIdToken: (googleIdToken: string) => Promise<void>
  loginWithAccessToken: (token: string) => Promise<void>
  logout: () => void
  refreshMe: () => Promise<void>
}

const Ctx = createContext<AuthState | null>(null)

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [accessToken, setToken] = useState<string | null>(() => getAccessToken())
  const [user, setUser] = useState<AuthUser | null>(null)

  const isAuthenticated = !!accessToken

  async function refreshMeInternal(tokenOverride?: string | null) {
    const resolvedToken = tokenOverride ?? accessToken
    if (!resolvedToken) {
      setUser(null)
      return
    }

    try {
      const u = await me(resolvedToken)
      setUser(u)
    } catch {
      setUser(null)
      setToken(null)
      clearAccessToken()
    }
  }

  async function refreshMe() {
    await refreshMeInternal()
  }

  async function loginWithGoogleIdToken(googleIdToken: string) {
    const res = await exchangeGoogleIdToken(googleIdToken)
    setToken(res.accessToken)
    setAccessToken(res.accessToken)
    await refreshMeInternal(res.accessToken)
  }

  async function loginWithAccessToken(token: string) {
    setToken(token)
    setAccessToken(token)
    await refreshMeInternal(token)
  }

  function logout() {
    setUser(null)
    setToken(null)
    clearAccessToken()
  }

  useEffect(() => { void refreshMe() }, [])

  const value = useMemo<AuthState>(() => ({
    accessToken,
    user,
    isAuthenticated,
    loginWithGoogleIdToken,
    loginWithAccessToken,
    logout,
    refreshMe
  }), [accessToken, user])

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useAuth() {
  const v = useContext(Ctx)
  if (!v) throw new Error('useAuth must be used within AuthProvider')
  return v
}
