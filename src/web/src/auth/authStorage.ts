const key = 'access_token';

export function getAccessToken(): string | null {
  return localStorage.getItem(key);
}

export function setAccessToken(token: string) {
  localStorage.setItem(key, token);
}

export function clearAccessToken() {
  localStorage.removeItem(key);
}
