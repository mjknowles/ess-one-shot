import crypto from "node:crypto";
import http from "node:http";
import { URL, URLSearchParams } from "node:url";

const config = {
  port: intEnv("PORT", 8080),
  publicBaseUrl: requiredEnv("PUBLIC_BASE_URL").replace(/\/$/, ""),
  cookieSecret: env("COOKIE_SECRET", crypto.randomBytes(32).toString("hex")),
  masPublicBaseUrl: env("MAS_PUBLIC_BASE_URL", "https://account.ess.localhost").replace(/\/$/, ""),
  masInternalBaseUrl: env("MAS_INTERNAL_BASE_URL", "http://ess-matrix-authentication-service:8080").replace(/\/$/, ""),
  masClientId: requiredEnv("MAS_OAUTH_CLIENT_ID"),
  masClientSecret: requiredEnv("MAS_OAUTH_CLIENT_SECRET"),
  masScope: env("MAS_OAUTH_SCOPE", "openid urn:matrix:org.matrix.msc2967.client:api:*"),
  matrixHomeserverInternalUrl: env("MATRIX_HOMESERVER_INTERNAL_URL", "http://ess-synapse-main:8008").replace(/\/$/, ""),
};

const sessions = new Map();
const pendingLogins = new Map();

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url ?? "/", config.publicBaseUrl);

    if (url.pathname === "/healthz") return text(res, 200, "ok\n");
    if (url.pathname === "/login") return startMasLogin(res);
    if (url.pathname === "/callback") return finishMasLogin(req, res, url);
    if (url.pathname === "/logout") return logout(req, res);

    return home(req, res);
  } catch (error) {
    console.error(error);
    return html(res, 500, page("OIDC Example", `<p class="error">${escapeHtml(error.message)}</p>`));
  }
});

server.listen(config.port, () => {
  console.log(`oidc-example listening on :${config.port}`);
});

async function home(req, res) {
  const session = getSession(req);
  const body = session
    ? authenticatedHome(session)
    : `
      <p>This app uses MAS as its OAuth provider. MAS then authenticates allowed users through Google / Cloud Identity and issues the Matrix access token used by Synapse.</p>
      <p><a class="button" href="/login">Start registration with Google</a></p>`;

  return html(res, 200, page("OIDC Example", body));
}

function authenticatedHome(session) {
  return `
    <dl>
      <dt>User ID</dt><dd>${escapeHtml(session.whoami.user_id ?? "unknown")}</dd>
      <dt>Device ID</dt><dd>${escapeHtml(session.whoami.device_id ?? "none")}</dd>
      <dt>MAS scope</dt><dd>${escapeHtml(session.token.scope ?? config.masScope)}</dd>
      <dt>Token TTL</dt><dd>${escapeHtml(String(session.token.expires_in ?? "unknown"))} seconds</dd>
    </dl>
    <section>
      <h2>Matrix API Token</h2>
      <label>
        Synapse access token
        <textarea readonly rows="6">${escapeHtml(session.token.access_token)}</textarea>
      </label>
      <details>
        <summary>Synapse /whoami response</summary>
        <pre>${escapeHtml(JSON.stringify(session.whoami, null, 2))}</pre>
      </details>
    </section>
    <form method="post" action="/bridge-placeholder">
      <h2>Bridge Setup Placeholder</h2>
      <label>
        Messaging account
        <input name="account" placeholder="example account id">
      </label>
      <p>Your production app can use this MAS-issued Matrix token to call Synapse and bridge provisioning APIs on this user's behalf.</p>
      <button type="button" disabled>Configure bridge</button>
    </form>
    <p><a class="button secondary" href="/logout">Sign out</a></p>`;
}

function startMasLogin(res) {
  const state = randomUrlSafe(24);
  const nonce = randomUrlSafe(24);
  const codeVerifier = randomUrlSafe(64);
  const codeChallenge = base64Url(crypto.createHash("sha256").update(codeVerifier).digest());

  pendingLogins.set(state, {
    nonce,
    codeVerifier,
    expiresAt: Date.now() + 10 * 60 * 1000,
  });

  const authUrl = new URL(`${config.masPublicBaseUrl}/oauth2/authorize`);
  authUrl.search = new URLSearchParams({
    client_id: config.masClientId,
    redirect_uri: callbackUrl(),
    response_type: "code",
    scope: config.masScope,
    state,
    nonce,
    code_challenge: codeChallenge,
    code_challenge_method: "S256",
  }).toString();

  return redirect(res, authUrl.toString());
}

async function finishMasLogin(_req, res, url) {
  const error = url.searchParams.get("error");
  if (error) {
    throw new Error(`${error}: ${url.searchParams.get("error_description") ?? "MAS returned an OAuth error"}`);
  }

  const state = requiredParam(url, "state");
  const code = requiredParam(url, "code");
  const login = pendingLogins.get(state);
  pendingLogins.delete(state);

  if (!login || login.expiresAt < Date.now()) {
    throw new Error("Login state is missing or expired");
  }

  const token = await exchangeMasCode(code, login.codeVerifier);
  const whoami = await verifySynapseAccessToken(token.access_token);

  const sessionId = randomUrlSafe(32);
  sessions.set(sessionId, {
    token,
    whoami,
    createdAt: Date.now(),
  });
  setCookie(res, "oidc_example", sign(sessionId), { maxAge: 60 * 60 * 8 });
  return redirect(res, "/");
}

async function exchangeMasCode(code, codeVerifier) {
  const auth = Buffer.from(`${config.masClientId}:${config.masClientSecret}`).toString("base64");
  const response = await fetch(`${config.masInternalBaseUrl}/oauth2/token`, {
    method: "POST",
    headers: {
      authorization: `Basic ${auth}`,
      "content-type": "application/x-www-form-urlencoded",
      accept: "application/json",
    },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: callbackUrl(),
      code_verifier: codeVerifier,
    }),
  });

  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    throw new Error(`MAS token exchange failed with HTTP ${response.status}: ${JSON.stringify(payload)}`);
  }
  if (!payload?.access_token) {
    throw new Error("MAS token response did not include an access token");
  }
  return payload;
}

async function verifySynapseAccessToken(accessToken) {
  const response = await fetch(`${config.matrixHomeserverInternalUrl}/_matrix/client/v3/account/whoami`, {
    headers: {
      authorization: `Bearer ${accessToken}`,
      accept: "application/json",
    },
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    throw new Error(`Synapse /whoami failed with HTTP ${response.status}: ${JSON.stringify(payload)}`);
  }
  return payload;
}

function logout(req, res) {
  const sessionId = readSessionId(req);
  if (sessionId) sessions.delete(sessionId);
  setCookie(res, "oidc_example", "", { maxAge: 0 });
  return redirect(res, "/");
}

function getSession(req) {
  const sessionId = readSessionId(req);
  return sessionId ? sessions.get(sessionId) : undefined;
}

function readSessionId(req) {
  const cookie = parseCookies(req.headers.cookie ?? "").oidc_example;
  if (!cookie) return undefined;
  const sessionId = unsign(cookie);
  return sessionId && sessions.has(sessionId) ? sessionId : undefined;
}

function sign(value) {
  const mac = crypto.createHmac("sha256", config.cookieSecret).update(value).digest("base64url");
  return `${value}.${mac}`;
}

function unsign(value) {
  const idx = value.lastIndexOf(".");
  if (idx < 1) return undefined;
  const data = value.slice(0, idx);
  const mac = value.slice(idx + 1);
  const expected = sign(data).slice(idx + 1);
  return timingSafeEqual(mac, expected) ? data : undefined;
}

function timingSafeEqual(a, b) {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

function parseCookies(header) {
  return Object.fromEntries(
    header
      .split(";")
      .map((part) => part.trim().split("="))
      .filter(([key, value]) => key && value)
      .map(([key, value]) => [key, decodeURIComponent(value)])
  );
}

function setCookie(res, name, value, { maxAge }) {
  res.setHeader(
    "set-cookie",
    `${name}=${encodeURIComponent(value)}; Path=/; HttpOnly; SameSite=Lax; Secure; Max-Age=${maxAge}`
  );
}

function page(title, body) {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)}</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #f5f7fb; color: #18202f; }
    main { width: min(760px, calc(100vw - 32px)); background: #fff; border: 1px solid #d7deea; border-radius: 8px; padding: 28px; box-shadow: 0 10px 30px rgb(20 32 54 / 8%); }
    h1 { margin: 0 0 16px; font-size: 28px; }
    h2 { margin: 24px 0 12px; font-size: 18px; }
    p { line-height: 1.5; }
    a.button, button { display: inline-flex; align-items: center; min-height: 40px; padding: 0 14px; border: 0; border-radius: 6px; background: #1a73e8; color: #fff; text-decoration: none; font: inherit; font-weight: 600; cursor: pointer; }
    button:disabled { background: #94a3b8; cursor: not-allowed; }
    a.secondary { background: #475569; }
    form, section { display: grid; gap: 12px; margin: 18px 0; padding: 16px; border: 1px solid #d7deea; border-radius: 8px; }
    label { display: grid; gap: 6px; font-weight: 700; }
    input, textarea { min-height: 38px; padding: 0 10px; border: 1px solid #b8c2d6; border-radius: 6px; font: inherit; }
    textarea { width: 100%; box-sizing: border-box; padding: 10px; resize: vertical; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
    dl { display: grid; grid-template-columns: 120px 1fr; gap: 8px 16px; }
    dt { font-weight: 700; }
    dd { margin: 0; overflow-wrap: anywhere; }
    pre { overflow: auto; padding: 12px; background: #101828; color: #d1e7ff; border-radius: 6px; }
    .error { color: #b42318; font-weight: 600; }
    @media (prefers-color-scheme: dark) {
      body { background: #111827; color: #eef2ff; }
      main { background: #1f2937; border-color: #334155; }
      form, section { border-color: #334155; }
      input, textarea { background: #111827; color: #eef2ff; border-color: #475569; }
    }
  </style>
</head>
<body><main><h1>${escapeHtml(title)}</h1>${body}</main></body>
</html>`;
}

function html(res, statusCode, body) {
  res.writeHead(statusCode, { "content-type": "text/html; charset=utf-8" });
  res.end(body);
}

function text(res, statusCode, body) {
  res.writeHead(statusCode, { "content-type": "text/plain; charset=utf-8" });
  res.end(body);
}

function redirect(res, location) {
  res.writeHead(302, { location });
  res.end();
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[char]);
}

function requiredParam(url, name) {
  const value = url.searchParams.get(name);
  if (!value) throw new Error(`Missing '${name}' callback parameter`);
  return value;
}

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function env(name, defaultValue) {
  return process.env[name] || defaultValue;
}

function intEnv(name, defaultValue) {
  const value = process.env[name];
  return value ? Number.parseInt(value, 10) : defaultValue;
}

function randomUrlSafe(bytes) {
  return crypto.randomBytes(bytes).toString("base64url");
}

function base64Url(buffer) {
  return Buffer.from(buffer).toString("base64url");
}

function callbackUrl() {
  return `${config.publicBaseUrl}/callback`;
}
