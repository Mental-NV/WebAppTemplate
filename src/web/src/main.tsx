import React from 'react'
import ReactDOM from 'react-dom/client'
import { GoogleOAuthProvider } from '@react-oauth/google'
import App from './App'
import './styles.css'
import { AuthProvider } from './auth/AuthContext'
import { googleClientId, hasGoogleClientId } from './config/google'

if (!hasGoogleClientId) {
  // eslint-disable-next-line no-console
  console.warn('Missing/invalid VITE_GOOGLE_CLIENT_ID. Create src/web/.env.local from .env.example and set a real Google OAuth Web client ID.')
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    {hasGoogleClientId ? (
      <GoogleOAuthProvider clientId={googleClientId}>
        <AuthProvider>
          <App />
        </AuthProvider>
      </GoogleOAuthProvider>
    ) : (
      <AuthProvider>
        <App />
      </AuthProvider>
    )}
  </React.StrictMode>,
)
