// ======== AUTH.JS ========
const cognitoDomain = "";
const clientId = "2g3lh5n8te1sv4vccl2veku57t";
const redirectUri = "https://d166hi15epg4f7.cloudfront.net";
const logoutUri = "https://d166hi15epg4f7.cloudfront.net";
const tokenStorageKey = "cognito_tokens";
const pkceVerifierKey = "pkce_verifier";

// =============== PKCE helpers ===============
function generateCodeVerifier() {
  const array = new Uint8Array(64);
  window.crypto.getRandomValues(array);
  return Array.from(array, dec => ('0' + dec.toString(16)).slice(-2)).join('');
}

async function generateCodeChallenge(verifier) {
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  const digest = await window.crypto.subtle.digest("SHA-256", data);
  const base64 = btoa(String.fromCharCode(...new Uint8Array(digest)));
  return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// =============== Redirect helpers ===============
async function redirectToLogin() {
  const verifier = generateCodeVerifier();
  localStorage.setItem(pkceVerifierKey, verifier);
  const challenge = await generateCodeChallenge(verifier);

  const loginUrl = `${cognitoDomain}/login` +
    `?client_id=${encodeURIComponent(clientId)}` +
    `&response_type=code` +
    `&scope=${encodeURIComponent("openid email phone")}` +
    `&redirect_uri=${encodeURIComponent(redirectUri)}` +
    `&code_challenge_method=S256` +
    `&code_challenge=${encodeURIComponent(challenge)}`;

  window.location.href = loginUrl;
}

function redirectToLogout() {
  localStorage.removeItem(tokenStorageKey);
  localStorage.removeItem(pkceVerifierKey);

  const logoutUrl = `${cognitoDomain}/logout` +
    `?client_id=${encodeURIComponent(clientId)}` +
    `&logout_uri=${encodeURIComponent(logoutUri)}`;

  window.location.href = logoutUrl;
}

// =============== Token exchange (Authorization Code + PKCE) ===============
async function exchangeCodeForTokens(code) {
  const verifier = localStorage.getItem(pkceVerifierKey);
  if (!verifier) {
    console.error("No PKCE verifier; redirecting to login.");
    redirectToLogin();
    return null;
  }

  const tokenUrl = `${cognitoDomain}/oauth2/token`;
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: clientId,
    code,
    redirect_uri: redirectUri,
    code_verifier: verifier
  });

  const res = await fetch(tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString()
  });

  if (!res.ok) {
    console.error("Token exchange failed:", res.status);
    return null;
  }

  const tokens = await res.json();
  storeTokens(tokens);
  localStorage.removeItem(pkceVerifierKey);

  // Clean URL
  try { window.history.replaceState({}, document.title, window.location.pathname); } catch {}

  return tokens;
}

// =============== Token refresh ===============
async function refreshTokens(refreshToken) {
  const tokenUrl = `${cognitoDomain}/oauth2/token`;
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    client_id: clientId,
    refresh_token: refreshToken
  });

  const res = await fetch(tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString()
  });

  if (!res.ok) {
    console.warn("Refresh failed:", res.status);
    return null;
  }

  const newTokens = await res.json();
  newTokens.refresh_token = refreshToken; // Cognito sometimes omits it on refresh
  storeTokens(newTokens);
  return newTokens;
}

// =============== Storage helpers ===============
function storeTokens(tokens) {
  const now = Math.floor(Date.now() / 1000);
  tokens.expires_at = now + (tokens.expires_in || 600);
  localStorage.setItem(tokenStorageKey, JSON.stringify(tokens));
}

function getStoredTokens() {
  try {
    const raw = localStorage.getItem(tokenStorageKey);
    return raw ? JSON.parse(raw) : null;
  } catch {
    localStorage.removeItem(tokenStorageKey);
    return null;
  }
}

// =============== Token management ===============
async function getAuthToken() {
  const tokens = getStoredTokens();
  const now = Math.floor(Date.now() / 1000);

  // 1. If valid access token -> use it
  if (tokens && tokens.expires_at > now + 10) {
    return tokens.access_token || tokens.id_token;
  }

  // 2. If expired but refresh token available -> refresh
  if (tokens && tokens.refresh_token) {
    const refreshed = await refreshTokens(tokens.refresh_token);
    if (refreshed && refreshed.access_token) {
      return refreshed.access_token;
    }
  }

  // 3. If refresh failed or missing -> full re-login
  alert("Your session has expired. Please sign in again.");
  localStorage.removeItem(tokenStorageKey);
  redirectToLogin();
  return null;
}

// =============== Initialization ===============
(async function initAuth() {
  const params = new URLSearchParams(window.location.search);
  const code = params.get("code");

  if (code) {
    const tokens = await exchangeCodeForTokens(code);
    if (tokens) {
      showApp();
      return;
    } else {
      redirectToLogin();
      return;
    }
  }

  const tokens = getStoredTokens();
  if (!tokens || (!tokens.access_token && !tokens.id_token)) {
    redirectToLogin();
  } else {
    showApp();
  }
})();

// =============== Logout ===============
function signOut() {
  redirectToLogout();
}

// =============== Show UI ===============
function showApp() {
  const el = document.getElementById("auth-section");
  if (el) el.classList.remove("hidden");
}

// =============== Expose globally ===============
window.getAuthToken = getAuthToken;
window.signOut = signOut;
window.redirectToLogin = redirectToLogin;

