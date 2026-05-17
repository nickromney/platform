const statusEl = document.getElementById("status");
const commentsEl = document.getElementById("comments");
const textarea = document.getElementById("comment-text");

document.addEventListener("DOMContentLoaded", () => {
  initializeTheme();
  initializeAuthState().catch((error) => {
    statusEl.textContent = userFacingAPIError(error, "Unable to initialize authentication");
  });
  document.getElementById("comment-form").addEventListener("submit", submitComment);
  document.getElementById("theme-switcher").addEventListener("click", toggleTheme);
  document.getElementById("login-btn").addEventListener("click", loginWithGateway);
  document.getElementById("logout-btn").addEventListener("click", logoutFromGateway);
  document.querySelector('[data-sample="positive"]').addEventListener("click", () => {
    textarea.value = "I absolutely love this. Great work and fantastic experience.";
  });
  document.querySelector('[data-sample="mixed"]').addEventListener("click", () => {
    textarea.value = "Some parts are fine, but overall I am disappointed and frustrated.";
  });
});

function runtimeConfig() {
  return window.SENTIMENT_RUNTIME_CONFIG || {};
}

async function initializeAuthState() {
  const userInfo = document.getElementById("user-info");
  const authState = document.getElementById("auth-state");
  const loginButton = document.getElementById("login-btn");
  const logoutButton = document.getElementById("logout-btn");

  if (usesGatewayAuth()) {
    userInfo.hidden = false;
    const session = await fetchGatewaySession();
    if (session) {
      authState.textContent = `Signed in as ${gatewayDisplayName(session)}`;
      loginButton.hidden = true;
      logoutButton.hidden = false;
      await loadComments();
      return;
    }

    authState.textContent = "Not signed in.";
    loginButton.hidden = false;
    logoutButton.hidden = true;
    statusEl.textContent = authRequiredMessage();
    document.querySelector('[data-action="analyze"]').disabled = true;
    commentsEl.innerHTML = "<p>Sign in to load comments.</p>";
    return;
  }

  if (apiReadyForUserAction()) {
    if ((runtimeConfig().apiAuthMethod || "none") === "none") {
      statusEl.textContent = "Ready. API authentication is disabled for this environment.";
    }
    await loadComments();
    return;
  }
  statusEl.textContent = authRequiredMessage();
  document.querySelector('[data-action="analyze"]').disabled = true;
  commentsEl.innerHTML = "<p>Sign in to load comments.</p>";
}

async function loadComments() {
  try {
    const data = await fetchJSON("/api/v1/comments?limit=25");
    renderComments(data.items || []);
    statusEl.textContent = "Ready.";
  } catch (error) {
    commentsEl.innerHTML = `<p>${escapeHTML(userFacingAPIError(error))}</p>`;
    throw error;
  }
}

async function submitComment(event) {
  event.preventDefault();
  const text = textarea.value.trim();
  if (!text) {
    statusEl.textContent = "Text is required.";
    return;
  }
  if (!apiReadyForUserAction()) {
    statusEl.textContent = authRequiredMessage();
    return;
  }
  try {
    const result = await fetchJSON("/api/v1/comments", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text }),
    });
    statusEl.textContent = `Saved. ${result.label} | Latency: ${result.latency_ms}ms`;
    textarea.value = "";
    await loadComments();
  } catch (error) {
    statusEl.textContent = userFacingAPIError(error);
  }
}

function apiReadyForUserAction() {
  const config = runtimeConfig();
  const authMethod = config.authMethod || "none";
  const apiAuthMethod = config.apiAuthMethod || authMethod;
  return apiAuthMethod !== "oidc" || authMethod === "gateway";
}

function usesGatewayAuth() {
  const config = runtimeConfig();
  return config.authMethod === "gateway" || config.apiAuthMethod === "gateway";
}

function authRequiredMessage() {
  return "Sign in before using sentiment analysis. The backend validates JWT/OIDC tokens, so this frontend will not submit unauthenticated API requests.";
}

function expiredSessionMessage() {
  return "Session expired. Sign out and sign in again to refresh API access.";
}

function authSessionExpired(error) {
  return usesGatewayAuth() && /invalid or expired access token/i.test(error.message || "");
}

function userFacingAPIError(error, prefix = "") {
  if (authSessionExpired(error)) {
    return expiredSessionMessage();
  }
  return prefix ? `${prefix}: ${error.message}` : `API error: ${error.message}`;
}

async function fetchJSON(url, options) {
  const response = await fetch(url, options);
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.detail || payload.error || `HTTP ${response.status}`);
  }
  return payload;
}

function renderComments(items) {
  if (items.length === 0) {
    commentsEl.innerHTML = "<p>No comments yet.</p>";
    return;
  }
  commentsEl.innerHTML = items.map((item) => `
    <article class="comment">
      <span class="label">${escapeHTML(item.label)}</span>
      <span class="meta">Confidence: ${Number(item.confidence).toFixed(2)} | Latency: ${item.latency_ms}ms</span>
      <p>${escapeHTML(item.text)}</p>
    </article>
  `).join("");
}

function initializeTheme() {
  const savedTheme = localStorage.getItem("theme") || "dark";
  document.documentElement.setAttribute("data-theme", savedTheme);
  updateThemeIcon(savedTheme);
}

function toggleTheme() {
  const currentTheme = document.documentElement.getAttribute("data-theme") || "dark";
  const nextTheme = currentTheme === "dark" ? "light" : "dark";
  document.documentElement.setAttribute("data-theme", nextTheme);
  localStorage.setItem("theme", nextTheme);
  updateThemeIcon(nextTheme);
}

function updateThemeIcon(theme) {
  const icon = document.getElementById("theme-icon");
  if (icon) {
    icon.textContent = theme === "dark" ? "Light" : "Dark";
  }
}

async function fetchGatewaySession() {
  const response = await fetch("/.auth/me", { headers: { Accept: "application/json" } });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }
  return normalizeGatewaySession(await response.json());
}

function normalizeGatewaySession(payload) {
  if (Array.isArray(payload)) {
    return payload[0] || null;
  }
  if (payload && payload.clientPrincipal) {
    return payload.clientPrincipal;
  }
  return null;
}

function gatewayDisplayName(session) {
  const claims = Array.isArray(session.claims) ? session.claims : [];
  const claimValue = (name) => {
    const found = claims.find((claim) => claim.typ === name || claim.type === name);
    return found ? found.val || found.value : "";
  };
  return claimValue("name")
    || claimValue("preferred_username")
    || claimValue("email")
    || session.userDetails
    || session.user_id
    || session.userId
    || "authenticated user";
}

function loginWithGateway() {
  window.location.assign("/.auth/login/sso");
}

function logoutFromGateway() {
  window.location.assign("/.auth/logout?post_logout_redirect_uri=/logged-out.html");
}

function escapeHTML(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[char]);
}
