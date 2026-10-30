import { API_URL } from '../config.js';
import { ApiError } from './errors.js';

// Only the two tokens are stored. The password is sent once to sign in and never kept.
const KEY = 'pmos_session';

async function getSession() {
  const stored = await chrome.storage.local.get(KEY);
  return stored[KEY] || null;
}

const setSession = (session) => chrome.storage.local.set({ [KEY]: session });

async function send(path, { method = 'GET', body, token } = {}) {
  let response;
  try {
    response = await fetch(API_URL + path, {
      method,
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(30000),
    });
  } catch {
    throw new ApiError(0);
  }
  let data = null;
  try {
    data = await response.json();
  } catch {
    /* an empty or non-JSON body */
  }
  if (!response.ok) throw new ApiError(response.status, data);
  return data;
}

export async function hasSession() {
  return Boolean((await getSession())?.access_token);
}

export async function signedInEmail() {
  return (await getSession())?.email || '';
}

export async function signIn(email, password) {
  const data = await send('/auth/login', { method: 'POST', body: { email, password } });
  await setSession({ access_token: data.access_token, refresh_token: data.refresh_token, email: data.user?.email });
  return data.user;
}

export const signOut = () => chrome.storage.local.remove(KEY);

/** An authenticated request. An expired access token is refreshed once; if that fails, the user is signed out. */
export async function api(path, options = {}) {
  const session = await getSession();
  if (!session) throw new ApiError(401);
  try {
    return await send(path, { ...options, token: session.access_token });
  } catch (error) {
    if (error.status !== 401 || !session.refresh_token) throw error;
    const fresh = await send('/auth/refresh', { method: 'POST', body: { refresh_token: session.refresh_token } }).catch(() => null);
    if (!fresh) {
      await signOut();
      throw error;
    }
    await setSession({ ...session, access_token: fresh.access_token });
    return send(path, { ...options, token: fresh.access_token });
  }
}
