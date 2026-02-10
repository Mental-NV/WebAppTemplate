import React from 'react'
import ReactDOM from 'react-dom/client'
import { GoogleOAuthProvider } from '@react-oauth/google'
import App from './App'
import './styles.css'
import { AuthProvider } from './auth/AuthContext'

const googleClientId = import.meta.env.VITE_GOOGLE_CLIENT_ID as string | undefined

if (!googleClientId) {
  // eslint-disable-next-line no-console
  console.warn('Missing VITE_GOOGLE_CLIENT_ID. Create src/web/.env.local from .env.example.')
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <GoogleOAuthProvider clientId={googleClientId ?? ''}>
      <AuthProvider>
        <App />
      </AuthProvider>
    </GoogleOAuthProvider>
  </React.StrictMode>,
)
