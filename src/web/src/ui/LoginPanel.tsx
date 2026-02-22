import { GoogleLogin } from '@react-oauth/google'
import { useAuth } from '../auth/AuthContext'
import { hasGoogleClientId } from '../config/google'

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
      {hasGoogleClientId ? (
        <GoogleLogin
          onSuccess={async (credentialResponse) => {
            const idToken = credentialResponse.credential
            if (!idToken) return
            await auth.loginWithGoogleIdToken(idToken)
          }}
          onError={() => { /* no-op */ }}
        />
      ) : (
        <div className="error small">
          Google auth is not configured. Set <code>VITE_GOOGLE_CLIENT_ID</code> in <code>src/web/.env.local</code>.
        </div>
      )}
      <div className="muted small">
        Login uses Google ID token -&gt; API exchange -&gt; app JWT
      </div>
    </div>
  )
}
