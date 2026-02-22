const rawGoogleClientId = import.meta.env.VITE_GOOGLE_CLIENT_ID as string | undefined

export const googleClientId = rawGoogleClientId?.trim() ?? ''

export const hasGoogleClientId =
  googleClientId.length > 0 && !googleClientId.includes('REPLACE_ME')
