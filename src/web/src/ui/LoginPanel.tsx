import { GoogleLogin } from '@react-oauth/google'
import { useAuth } from '../auth/AuthContext'

export default function LoginPanel() {
  const auth = useAuth()

  if (auth.isAuthenticated) {
    return (
      <div className="loginPanel">
        <div className="loginMeta">
          <span className="pill">Signed in</span>
          {auth.user?.email && <span className="muted">{auth.user.email}</span>}
        </div>
        <button className="btn" onClick={() => auth.logout()}>Sign out</button>
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
        Login uses Google ID token → API exchange → app JWT
      </div>
    </div>
  )
}
