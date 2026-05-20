// @ts-check

/** @typedef {import("./api-types.d.ts").RuntimeConfig} RuntimeConfig */
/** @typedef {import("./api-types.d.ts").ApiDiagnostics} ApiDiagnostics */
/** @typedef {import("./api-types.d.ts").NetworkHop} NetworkHop */
/** @typedef {import("./api-types.d.ts").SentimentComment} SentimentComment */

const statusEl = requireElement("status");
const diagnosticsEl = requireElement("diagnostics");
const commentsEl = requireElement("comments");
const textarea = textAreaElement("comment-text");
const themeOptions = ["system", "light", "dark"];

document.addEventListener("DOMContentLoaded", () => {
	initializeTheme();
	initializeAuthState().catch((error) => {
		statusEl.textContent = userFacingAPIError(
			error,
			"Unable to initialize authentication",
		);
	});
	document
		.getElementById("comment-form")
		.addEventListener("submit", submitComment);
	document
		.getElementById("theme-switcher")
		.addEventListener("click", toggleTheme);
	document
		.getElementById("login-btn")
		.addEventListener("click", loginWithGateway);
	document
		.getElementById("logout-btn")
		.addEventListener("click", logoutFromGateway);
	document
		.querySelector('[data-sample="positive"]')
		.addEventListener("click", () => {
			textarea.value =
				"I absolutely love this. Great work and fantastic experience.";
		});
	document
		.querySelector('[data-sample="mixed"]')
		.addEventListener("click", () => {
			textarea.value =
				"Some parts are fine, but overall I am disappointed and frustrated.";
		});
});

function runtimeConfig() {
	return window.SENTIMENT_RUNTIME_CONFIG || {};
}

function requireElement(id) {
	const element = document.getElementById(id);
	if (!element) {
		throw new Error(`Missing required element #${id}`);
	}
	return element;
}

function textAreaElement(id) {
	return /** @type {HTMLTextAreaElement} */ (requireElement(id));
}

function analyzeButton() {
	const button = document.querySelector('[data-action="analyze"]');
	if (!button) {
		throw new Error("Missing analyze button");
	}
	return /** @type {HTMLButtonElement} */ (button);
}

async function initializeAuthState() {
	const authState = document.getElementById("auth-state");
	const loginButton = document.getElementById("login-btn");
	const logoutButton = document.getElementById("logout-btn");

	if (usesGatewayAuth()) {
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
		analyzeButton().disabled = true;
		commentsEl.innerHTML = "<p>Sign in to load comments.</p>";
		return;
	}

	if (apiReadyForUserAction()) {
		if ((runtimeConfig().apiAuthMethod || "none") === "none") {
			statusEl.textContent =
				"Ready. API authentication is disabled for this environment.";
		}
		await loadComments();
		return;
	}
	statusEl.textContent = authRequiredMessage();
	analyzeButton().disabled = true;
	commentsEl.innerHTML = "<p>Sign in to load comments.</p>";
}

async function loadComments() {
	try {
		const response = await timedFetchJSON(apiURL("/comments?limit=25"));
		renderComments(response.data.items || []);
		renderAPIDiagnostics("Load comments", response.timing);
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
		const response = await timedFetchJSON(apiURL("/comments"), {
			method: "POST",
			headers: apiRequestHeaders(),
			body: JSON.stringify({ text }),
		});
		const result = response.data;
		statusEl.textContent = `Saved. ${result.label} | Latency: ${result.latency_ms}ms`;
		textarea.value = "";
		await loadComments();
		renderAPIDiagnostics("Submit comment", response.timing);
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
	return (
		usesGatewayAuth() &&
		/invalid or expired access token/i.test(error.message || "")
	);
}

function userFacingAPIError(error, prefix = "") {
	if (authSessionExpired(error)) {
		return expiredSessionMessage();
	}
	return prefix ? `${prefix}: ${error.message}` : `API error: ${error.message}`;
}

function apiBasePath() {
	const base = runtimeConfig().apiBasePath || "/api/v1";
	return `/${String(base).replace(/^\/+|\/+$/g, "")}`;
}

function apiURL(path) {
	return `${apiBasePath()}${path.startsWith("/") ? path : `/${path}`}`;
}

function apiRequestHeaders() {
	return {
		"Content-Type": "application/json",
		...(shouldShowNetworkPath() ? { "x-apim-trace": "true" } : {}),
	};
}

async function timedFetchJSON(url, options = {}) {
	const started = performance.now();
	const requestUtc = new Date().toISOString();
	const headers = {
		...apiRequestHeaders(),
		...(options.headers || {}),
	};
	const response = await fetch(url, { ...options, headers });
	const data = await response.json().catch(() => ({}));
	const responseUtc = new Date().toISOString();
	if (!response.ok) {
		throw new Error(data.detail || data.error || `HTTP ${response.status}`);
	}
	return {
		data,
		timing: {
			url,
			durationMs: Math.round(performance.now() - started),
			requestUtc,
			responseUtc,
			traceId: response.headers.get("x-apim-trace-id") || "",
			correlationId: response.headers.get("x-correlation-id") || "",
			apimTrace: decodeAPIMTrace(response.headers.get("x-apim-trace") || ""),
		},
	};
}

function renderComments(items) {
	if (items.length === 0) {
		commentsEl.innerHTML = "<p>No comments yet.</p>";
		return;
	}
	commentsEl.innerHTML = items
		.map(
			(item) => `
    <article class="comment">
      <span class="label">${escapeHTML(item.label)}</span>
      <span class="meta">Confidence: ${Number(item.confidence).toFixed(2)} | Latency: ${item.latency_ms}ms</span>
      <p>${escapeHTML(item.text)}</p>
    </article>
  `,
		)
		.join("");
}

function renderAPIDiagnostics(action, timing) {
	const rows = [
		["Action", action],
		["API URL", timing.url],
		["Backend URL", runtimeConfig().backendURL || "same process"],
		["Duration", `${timing.durationMs}ms`],
		["Request (UTC)", timing.requestUtc],
		["Response (UTC)", timing.responseUtc],
	];
	if (timing.correlationId) rows.push(["Correlation ID", timing.correlationId]);
	if (timing.traceId) rows.push(["APIM Trace ID", timing.traceId]);
	if (timing.apimTrace) {
		if (timing.apimTrace.route)
			rows.push(["APIM Route", timing.apimTrace.route]);
		if (timing.apimTrace.upstream_url)
			rows.push(["APIM Upstream", timing.apimTrace.upstream_url]);
		if (timing.apimTrace.elapsed_ms !== undefined)
			rows.push(["APIM Upstream Time", `${timing.apimTrace.elapsed_ms}ms`]);
		if (timing.apimTrace.status !== undefined)
			rows.push(["APIM Status", timing.apimTrace.status]);
	}
	const networkPath = shouldShowNetworkPath() ? renderNetworkPath() : "";
	diagnosticsEl.innerHTML = `<details open><summary>API Call Timing</summary>${renderTable(rows)}</details>${networkPath}`;
}

function renderTable(rows) {
	return `<table><tbody>${rows.map(([key, value]) => `<tr><th>${escapeHTML(key)}</th><td>${escapeHTML(String(value || ""))}</td></tr>`).join("")}</tbody></table>`;
}

function shouldShowNetworkPath() {
	return runtimeConfig().showNetworkPath !== false;
}

function configuredNetworkHops() {
	const config = runtimeConfig();
	if (
		Array.isArray(config.networkHops) &&
		config.networkHops.every(isNetworkHop)
	) {
		return config.networkHops;
	}
	const backendURL = config.backendURL || "same process";
	const backendRole = String(backendURL).includes("apim")
		? "API gateway forwarding to sentiment-api"
		: "Go API";
	return [
		{
			label: "Browser",
			detail: window.location.origin,
			role: "Vanilla frontend",
		},
		{
			label: "Sentiment frontend",
			detail: `${apiBasePath()}/*`,
			role: "Same-origin API route",
		},
		{ label: "Sentiment API", detail: backendURL, role: backendRole },
	];
}

function isNetworkHop(value) {
	return (
		value && typeof value.label === "string" && typeof value.detail === "string"
	);
}

function renderNetworkPath() {
	const hops = configuredNetworkHops();
	return `<details>
    <summary>Network Path (${hops.length} hops)</summary>
    <div class="network-path">
      ${hops
				.map((hop, index) => {
					const arrow = index > 0 ? `<div class="hop-arrow">&darr;</div>` : "";
					const role = hop.role
						? `<br><em>${escapeHTML(String(hop.role))}</em>`
						: "";
					return `${arrow}<div class="hop"><strong>${escapeHTML(hop.label)}</strong><br><small>${escapeHTML(hop.detail)}</small>${role}</div>`;
				})
				.join("")}
    </div>
  </details>`;
}

function decodeAPIMTrace(value) {
	if (!value) return null;
	try {
		return JSON.parse(atob(value));
	} catch {
		return null;
	}
}

function initializeTheme() {
	applyTheme(readThemeCookie());
	window
		.matchMedia("(prefers-color-scheme: dark)")
		.addEventListener("change", () => {
			if (themePreference() === "system") {
				applyTheme("system");
			}
		});
}

function toggleTheme() {
	const currentTheme = themePreference();
	const nextTheme =
		themeOptions[
			(themeOptions.indexOf(currentTheme) + 1) % themeOptions.length
		];
	writeThemeCookie(nextTheme);
	applyTheme(nextTheme);
}

function readThemeCookie() {
	const prefix = "pce-theme=";
	const cookieValue = document.cookie
		.split(";")
		.map((value) => value.trim())
		.find((value) => value.startsWith(prefix));
	const theme = cookieValue
		? decodeURIComponent(cookieValue.slice(prefix.length))
		: "";
	return themeOptions.includes(theme) ? theme : "system";
}

function writeThemeCookie(theme) {
	const safeTheme = themeOptions.includes(theme) ? theme : "system";
	const maxAge = 60 * 60 * 24 * 365;
	const secure = window.location.protocol === "https:" ? "; Secure" : "";
	const domain = themeCookieDomain();
	// biome-ignore lint/suspicious/noDocumentCookie: This shared preference must span dev, uat, and admin subdomains.
	document.cookie = `pce-theme=${encodeURIComponent(safeTheme)}; Path=/; Max-Age=${maxAge}; SameSite=Lax${domain}${secure}`;
}

function themeCookieDomain() {
	return window.location.hostname.endsWith("127.0.0.1.sslip.io")
		? "; Domain=.127.0.0.1.sslip.io"
		: "";
}

function themePreference() {
	const theme = document.documentElement.getAttribute("data-theme") || "system";
	return themeOptions.includes(theme) ? theme : "system";
}

function applyTheme(theme) {
	document.documentElement.setAttribute("data-theme", theme);
	updateThemeIcon(theme);
}

function updateThemeIcon(theme) {
	const switcher = document.getElementById("theme-switcher");
	if (switcher instanceof HTMLButtonElement) {
		const nextTheme =
			themeOptions[(themeOptions.indexOf(theme) + 1) % themeOptions.length];
		switcher.dataset.themeChoice = theme;
		switcher.setAttribute(
			"aria-label",
			`Theme: ${theme}. Switch to ${nextTheme} theme.`,
		);
		switcher.title = `Theme: ${theme}. Switch to ${nextTheme} theme.`;
	}
}

async function fetchGatewaySession() {
	const response = await fetch("/.auth/me", {
		headers: { Accept: "application/json" },
	});
	if (!response.ok) {
		throw new Error(`HTTP ${response.status}`);
	}
	return normalizeGatewaySession(await response.json());
}

function normalizeGatewaySession(payload) {
	if (Array.isArray(payload)) {
		return payload[0] || null;
	}
	if (payload?.clientPrincipal) {
		return payload.clientPrincipal;
	}
	return null;
}

function gatewayDisplayName(session) {
	const claims = Array.isArray(session.claims) ? session.claims : [];
	const claimValue = (name) => {
		const found = claims.find(
			(claim) => claim.typ === name || claim.type === name,
		);
		return found ? found.val || found.value : "";
	};
	return (
		claimValue("name") ||
		claimValue("preferred_username") ||
		claimValue("email") ||
		session.userDetails ||
		session.user_id ||
		session.userId ||
		"authenticated user"
	);
}

function loginWithGateway() {
	window.location.assign("/.auth/login/sso");
}

function logoutFromGateway() {
	window.location.assign("/oauth2/sign_out?rd=/signed-out.html");
}

function escapeHTML(value) {
	return String(value).replace(
		/[&<>"']/g,
		(char) =>
			({
				"&": "&amp;",
				"<": "&lt;",
				">": "&gt;",
				'"': "&quot;",
				"'": "&#39;",
			})[char],
	);
}
