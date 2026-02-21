import { useState } from 'react'
import { GoogleLogin } from '@react-oauth/google'
import { useAuth } from '../auth/AuthContext'
import { e2eLogin } from '../services/authApi'

export default function LoginPanel() {
  const auth = useAuth()
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const isE2EAuthMode = import.meta.env.VITE_E2E_AUTH_MODE === 'true'

  if (auth.isAuthenticated) {
    return (
      <div className="loginPanel">
        <div className="loginMeta">
          <span className="pill">Signed in</span>
          {auth.user?.email && <span className="muted">{auth.user.email}</span>}
        </div>
        <button className="btn" type="button" onClick={() => auth.logout()}>Sign out</button>
      </div>
    )
  }

  if (isE2EAuthMode) {
    return (
      <div className="loginPanel">
        <button
          className="btn"
          type="button"
          disabled={pending}
          onClick={async () => {
            setPending(true)
            setError(null)
            try {
              const res = await e2eLogin()
              await auth.loginWithAccessToken(res.accessToken)
            } catch (e: any) {
              setError(e?.message ?? 'Failed to sign in for E2E.')
            } finally {
              setPending(false)
            }
          }}
        >
          {pending ? 'Signing in...' : 'Sign in (E2E)'}
        </button>
        {error && <div className="error small">{error}</div>}
        <div className="muted small">
          E2E auth mode: local test token flow
        </div>
      </div>
    )
  }

  return (
    <div className="loginPanel">
      <GoogleLogin
        onSuccess={async (credentialResponse) => {
          const idToken = credentialResponse.credential
          if (!idToken) return
          await auth.loginWithGoogleIdToken(idToken)
        }}
        onError={() => { /* no-op */ }}
      />
      <div className="muted small">
        Login uses Google ID token, API exchange, and app JWT
      </div>
    </div>
  )
}
