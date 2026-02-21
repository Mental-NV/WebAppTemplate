export type AuthUser = {
  subject: string
  email: string | null
  name: string | null
}

export type ExchangeResponse = {
  accessToken: string
  expiresAtUtc: string
  user: {
    subject: string
    email: string | null
    name: string | null
    pictureUrl: string | null
  }
}

async function http<T>(input: RequestInfo, init?: RequestInit): Promise<T> {
  const res = await fetch(input, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(init?.headers ?? {})
    }
  })

  if (!res.ok) {
    const txt = await res.text()
    throw new Error(`HTTP ${res.status}: ${txt}`)
  }

  return (await res.json()) as T
}

export async function exchangeGoogleIdToken(idToken: string): Promise<ExchangeResponse> {
  return await http<ExchangeResponse>(`/api/v1/auth/google`, {
    method: 'POST',
    body: JSON.stringify({ idToken })
  })
}

export async function e2eLogin(): Promise<ExchangeResponse> {
  return await http<ExchangeResponse>(`/api/v1/e2e/auth/login`, {
    method: 'POST',
    body: JSON.stringify({})
  })
}

export async function me(accessToken: string): Promise<AuthUser> {
  const res = await fetch(`/api/v1/auth/me`, {
    headers: {
      'Authorization': `Bearer ${accessToken}`
    }
  })

  if (!res.ok) {
    const txt = await res.text()
    throw new Error(`HTTP ${res.status}: ${txt}`)
  }

  return await res.json() as AuthUser
}
