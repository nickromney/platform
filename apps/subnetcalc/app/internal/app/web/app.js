// @ts-check

/** @typedef {import("./api-types.d.ts").RuntimeConfig} RuntimeConfig */
/** @typedef {import("./api-types.d.ts").ApiDiagnostics} ApiDiagnostics */
/** @typedef {import("./api-types.d.ts").NetworkHop} NetworkHop */

const paths = {
	health: "/api/v1/health",
	validate: "/api/v1/ipv4/validate",
	private: "/api/v1/ipv4/check-private",
	cloudflare: "/api/v1/ipv4/check-cloudflare",
	providerRange: "/api/v1/provider-ranges/check",
	subnet: "/api/v1/ipv4/subnet-info",
	whoami: "/api/whoami",
};
const oidcStorageKey = "subnetcalc.oidc";
const oidcStateKey = "subnetcalc.oidc.state";
const themeOptions = ["system", "light", "dark"];

document.addEventListener("DOMContentLoaded", () => {
	initializeTheme();
	initializeAuth()
		.catch((error) => {
			document.getElementById("auth-state").textContent =
				`Sign-in failed: ${error.message}`;
		})
		.finally(checkHealth);
	document.getElementById("lookup-form").addEventListener("submit", lookup);
	document
		.getElementById("provider-form")
		.addEventListener("submit", providerRangeCheck);
	document.getElementById("identity-form").addEventListener("submit", whoami);
	document
		.getElementById("theme-switcher")
		.addEventListener("click", toggleTheme);
	document.getElementById("login-btn").addEventListener("click", loginWithOidc);
	document
		.getElementById("logout-btn")
		.addEventListener("click", logoutFromOidc);
	document.querySelectorAll("[data-example]").forEach((button) => {
		const exampleButton = /** @type {HTMLElement} */ (button);
		button.addEventListener("click", () => {
			inputElement("ip-address").value = exampleButton.dataset.example || "";
		});
	});
});

function runtimeConfig() {
	return window.SUBNETCALC_RUNTIME_CONFIG || {};
}

function requireElement(id) {
	const element = document.getElementById(id);
	if (!element) {
		throw new Error(`Missing required element #${id}`);
	}
	return element;
}

function inputElement(id) {
	return /** @type {HTMLInputElement} */ (requireElement(id));
}

function selectElement(id) {
	return /** @type {HTMLSelectElement} */ (requireElement(id));
}

async function initializeAuth() {
	const config = runtimeConfig();
	refreshAuthControls();
	if (usesGatewayAuth()) {
		await refreshGatewayIdentity();
		return;
	}
	if (!apiRequiresOidcToken()) {
		document.getElementById("auth-state").textContent =
			"API authentication is disabled for this environment.";
		return;
	}

	if (new URLSearchParams(window.location.search).has("code")) {
		await completeOidcLogin(config);
	}
	const token = storedOidcToken();
	if (token) {
		inputElement("token-input").value = token;
		await refreshIdentity();
	} else {
		document.getElementById("auth-state").textContent =
			"Sign in before using the API. Backend API calls require a valid JWT.";
	}
}

async function checkHealth() {
	const status = document.getElementById("api-status");
	try {
		const data = await getJSON(paths.health);
		const authState = data.server_side_token_validation
			? "OIDC/JWT validated by backend"
			: "No auth mode";
		const backendRoute = runtimeConfig().backendURL || "same process";
		status.textContent = `API Status: ${data.status} | Backend: ${data.service} | Backend URI: ${backendRoute} | Version: ${data.version} | Auth: ${authState}`;
	} catch (error) {
		status.textContent = authSessionExpired(error)
			? expiredSessionMessage()
			: `API unavailable: ${error.message}`;
		status.classList.add("error");
	}
}

async function lookup(event) {
	event.preventDefault();
	const address = inputElement("ip-address").value.trim();
	const mode = selectElement("cloud-mode").value;
	const content = prepareResults();

	if (!apiReadyForUserAction()) {
		content.innerHTML = `<p class="error">${escapeHTML(authRequiredMessage())}</p>`;
		focusResults();
		return;
	}

	content.textContent = "Loading...";

	try {
		const started = performance.now();
		const validation = await timedPostJSON(paths.validate, { address });
		const privateCheck = validation.data.is_ipv4
			? await timedPostJSON(paths.private, { address })
			: null;
		const cloudflare = await timedPostJSON(paths.cloudflare, { address });
		const subnet =
			validation.data.type === "network" && validation.data.is_ipv4
				? await timedPostJSON(paths.subnet, { network: address, mode })
				: null;
		const totalMs = Math.round(performance.now() - started);
		content.innerHTML = renderResults(
			validation,
			privateCheck,
			cloudflare,
			subnet,
		);
		content.insertAdjacentHTML("beforeend", renderPerformance(totalMs));
	} catch (error) {
		content.innerHTML = `<p class="error">${escapeHTML(userFacingAPIError(error))}</p>`;
	}
	focusResults();
}

async function whoami(event) {
	event.preventDefault();
	await refreshIdentity();
}

async function providerRangeCheck(event) {
	event.preventDefault();
	const address = inputElement("provider-address").value.trim();
	const provider = selectElement("provider-name").value;
	const content = prepareResults();

	if (!apiReadyForUserAction()) {
		content.innerHTML = `<p class="error">${escapeHTML(authRequiredMessage())}</p>`;
		focusResults();
		return;
	}

	content.textContent = "Loading...";
	try {
		const started = performance.now();
		const providerRange = await timedPostJSON(paths.providerRange, {
			provider,
			address,
		});
		const totalMs = Math.round(performance.now() - started);
		content.innerHTML = renderProviderRange(providerRange);
		content.insertAdjacentHTML("beforeend", renderPerformance(totalMs));
	} catch (error) {
		content.innerHTML = `<p class="error">${escapeHTML(userFacingAPIError(error))}</p>`;
	}
	focusResults();
}

function prepareResults() {
	const results = document.getElementById("results");
	results.hidden = false;
	return document.getElementById("results-content");
}

function focusResults() {
	document.getElementById("results").focus();
}

async function refreshIdentity() {
	if (usesGatewayAuth()) {
		await refreshGatewayIdentity();
		return;
	}
	const token = inputElement("token-input").value.trim();
	const authState = document.getElementById("auth-state");
	try {
		const user = await getJSON(
			paths.whoami,
			token ? { Authorization: `Bearer ${token}` } : {},
		);
		authState.textContent = `Signed in as ${user.preferred_username || user.email || user.sub}`;
	} catch (error) {
		authState.textContent = `Not signed in: ${error.message}`;
	}
}

async function getJSON(path, headers = {}) {
	const response = await fetch(path, { headers });
	return parseJSONResponse(response);
}

function apiRequestHeaders() {
	return {
		"Content-Type": "application/json",
		...apiTraceHeaders(),
		...apiAuthHeaders(),
	};
}

function apiAuthHeaders() {
	if (usesGatewayAuth()) {
		return {};
	}
	const input = inputElement("token-input");
	const token = input.value.trim();
	return token ? { Authorization: `Bearer ${token}` } : {};
}

function refreshAuthControls() {
	const gateway = usesGatewayAuth();
	const showOidc = apiRequiresOidcToken() && !gateway;
	const showAuthPanel = showOidc || gateway;
	document.getElementById("auth-panel").hidden = !showOidc;
	document.getElementById("auth-state").hidden = !showAuthPanel;
	const tokenInput = document.getElementById("token-input");
	const whoamiButton = document.getElementById("whoami-btn");
	document.getElementById("login-btn").hidden = !showOidc && !gateway;
	document.getElementById("logout-btn").hidden = !showOidc && !gateway;
	tokenInput.hidden = gateway;
	whoamiButton.hidden = gateway;
}

function apiRequiresOidcToken() {
	const config = runtimeConfig();
	return config.authMethod === "oidc" || config.apiAuthMethod === "oidc";
}

function usesGatewayAuth() {
	const config = runtimeConfig();
	return config.authMethod === "gateway" || config.apiAuthMethod === "gateway";
}

function apiReadyForUserAction() {
	return (
		usesGatewayAuth() ||
		!apiRequiresOidcToken() ||
		Boolean(inputElement("token-input").value.trim())
	);
}

function authRequiredMessage() {
	return "Sign in before running API calls. The backend validates JWT/OIDC tokens, so the calculator will not submit unauthenticated API requests.";
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

function userFacingAPIError(error) {
	return authSessionExpired(error)
		? expiredSessionMessage()
		: `Error: ${error.message}`;
}

function apiTraceHeaders() {
	return shouldShowNetworkPath() ? { "x-apim-trace": "true" } : {};
}

async function loginWithOidc() {
	if (usesGatewayAuth()) {
		window.location.assign("/.auth/login/sso");
		return;
	}
	const config = requireOidcConfig();
	const state = randomBase64Url(32);
	const verifier = randomBase64Url(64);
	const challenge = await sha256Base64Url(verifier);
	sessionStorage.setItem(
		oidcStateKey,
		JSON.stringify({
			state,
			verifier,
			returnUrl:
				`${window.location.pathname}${window.location.search}${window.location.hash}` ||
				"/",
		}),
	);

	const params = new URLSearchParams({
		client_id: config.oidcClientId,
		redirect_uri: oidcRedirect(config),
		response_type: "code",
		scope: "openid profile email",
		state,
		code_challenge: challenge,
		code_challenge_method: "S256",
	});
	window.location.assign(
		`${config.oidcAuthority}/protocol/openid-connect/auth?${params}`,
	);
}

async function completeOidcLogin(config) {
	const params = new URLSearchParams(window.location.search);
	const stateRecord = JSON.parse(sessionStorage.getItem(oidcStateKey) || "{}");
	if (
		!params.get("code") ||
		params.get("state") !== stateRecord.state ||
		!stateRecord.verifier
	) {
		throw new Error("OIDC callback state did not match");
	}

	const body = new URLSearchParams({
		grant_type: "authorization_code",
		client_id: config.oidcClientId,
		redirect_uri: oidcRedirect(config),
		code: params.get("code"),
		code_verifier: stateRecord.verifier,
	});
	const response = await fetch(
		`${config.oidcAuthority}/protocol/openid-connect/token`,
		{
			method: "POST",
			headers: { "Content-Type": "application/x-www-form-urlencoded" },
			body,
		},
	);
	const tokenSet = await response.json().catch(() => ({}));
	if (!response.ok || !tokenSet.access_token) {
		throw new Error(
			tokenSet.error_description ||
				tokenSet.error ||
				`OIDC token exchange failed with HTTP ${response.status}`,
		);
	}
	localStorage.setItem(
		oidcStorageKey,
		JSON.stringify({
			accessToken: tokenSet.access_token,
			idToken: tokenSet.id_token || "",
			expiresAt: Date.now() + Number(tokenSet.expires_in || 0) * 1000,
		}),
	);
	sessionStorage.removeItem(oidcStateKey);
	window.history.replaceState({}, document.title, stateRecord.returnUrl || "/");
}

function logoutFromOidc() {
	if (usesGatewayAuth()) {
		window.location.assign(gatewayLogoutURL());
		return;
	}
	const config = runtimeConfig();
	const token = JSON.parse(localStorage.getItem(oidcStorageKey) || "{}");
	localStorage.removeItem(oidcStorageKey);
	inputElement("token-input").value = "";
	document.getElementById("auth-state").textContent = "Not signed in.";
	if (config.oidcAuthority && token.idToken) {
		const params = new URLSearchParams({
			id_token_hint: token.idToken,
			post_logout_redirect_uri: new URL("/", window.location.origin).toString(),
		});
		window.location.assign(
			`${config.oidcAuthority}/protocol/openid-connect/logout?${params}`,
		);
	}
}

function gatewayLogoutURL() {
	const oauthSignOut = new URL("/oauth2/sign_out", window.location.origin);
	oauthSignOut.searchParams.set("rd", "/signed-out.html");
	return oauthSignOut.toString();
}

async function refreshGatewayIdentity() {
	const authState = document.getElementById("auth-state");
	try {
		const response = await fetch("/.auth/me", {
			headers: { Accept: "application/json" },
		});
		if (!response.ok) {
			throw new Error(`HTTP ${response.status}`);
		}
		const session = normalizeGatewaySession(await response.json());
		if (session) {
			authState.textContent = `Signed in as ${gatewayDisplayName(session)}`;
			document.getElementById("login-btn").hidden = true;
			document.getElementById("logout-btn").hidden = false;
			return;
		}
		authState.textContent = "Not signed in.";
		document.getElementById("login-btn").hidden = false;
		document.getElementById("logout-btn").hidden = true;
	} catch (error) {
		authState.textContent = `Unable to read gateway session: ${error.message}`;
		document.getElementById("login-btn").hidden = false;
		document.getElementById("logout-btn").hidden = true;
	}
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

function storedOidcToken() {
	const token = JSON.parse(localStorage.getItem(oidcStorageKey) || "{}");
	if (
		!token.accessToken ||
		(token.expiresAt && token.expiresAt <= Date.now() + 30000)
	) {
		localStorage.removeItem(oidcStorageKey);
		return "";
	}
	return token.accessToken;
}

function requireOidcConfig() {
	const config = runtimeConfig();
	if (!config.oidcAuthority || !config.oidcClientId) {
		throw new Error("OIDC configuration missing");
	}
	return config;
}

function oidcRedirect(config) {
	return config.oidcRedirect || new URL("/", window.location.origin).toString();
}

function randomBase64Url(byteCount) {
	const bytes = new Uint8Array(byteCount);
	crypto.getRandomValues(bytes);
	return base64Url(bytes);
}

async function sha256Base64Url(value) {
	const bytes = new TextEncoder().encode(value);
	return base64Url(
		new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
	);
}

function base64Url(bytes) {
	let binary = "";
	bytes.forEach((byte) => {
		binary += String.fromCharCode(byte);
	});
	return btoa(binary)
		.replace(/\+/g, "-")
		.replace(/\//g, "_")
		.replace(/=+$/, "");
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

async function timedPostJSON(path, body) {
	const started = performance.now();
	const requestUtc = new Date().toISOString();
	const response = await fetch(path, {
		method: "POST",
		headers: apiRequestHeaders(),
		body: JSON.stringify(body),
	});
	const data = await parseJSONResponse(response);
	const responseUtc = new Date().toISOString();
	return {
		data,
		timing: {
			durationMs: Math.round(performance.now() - started),
			requestUtc,
			responseUtc,
			traceId: response.headers.get("x-apim-trace-id") || "",
			correlationId: response.headers.get("x-correlation-id") || "",
			apimTrace: decodeAPIMTrace(response.headers.get("x-apim-trace") || ""),
		},
	};
}

function shouldShowNetworkPath() {
	const config = runtimeConfig();
	return config.showNetworkPath !== false;
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
	const backendRole =
		config.apiAuthMethod === "oidc"
			? "Go backend with server-side token validation"
			: "Go backend";
	return [
		{
			label: "Browser",
			detail: window.location.origin,
			role: "Vanilla frontend",
		},
		{
			label: "Subnet frontend",
			detail: "/api reverse proxy",
			role: "Static UI and same-origin API proxy",
		},
		{ label: "Subnet API", detail: backendURL, role: backendRole },
	];
}

function isNetworkHop(value) {
	return (
		value && typeof value.label === "string" && typeof value.detail === "string"
	);
}

function decodeAPIMTrace(value) {
	if (!value) return null;
	try {
		return JSON.parse(atob(value));
	} catch {
		return null;
	}
}

async function parseJSONResponse(response) {
	const data = await response.json().catch(() => ({}));
	if (!response.ok) {
		throw new Error(data.detail || data.error || `HTTP ${response.status}`);
	}
	return data;
}

function renderResults(validation, privateCheck, cloudflare, subnet) {
	const validationRows = [
		["Valid", validation.data.valid ? "Yes" : "No"],
		["Address", validation.data.address],
		[
			"Type",
			validation.data.type === "network" ? "Network (CIDR)" : "Host Address",
		],
		["IP Version", validation.data.is_ipv4 ? "IPv4" : "IPv6"],
	];

	const sections = [
		renderArticle("Validation", validationRows, validation.timing),
	];

	if (privateCheck) {
		sections.push(
			renderArticle(
				"Private Address Check",
				[
					[
						"RFC1918",
						privateCheck.data.is_rfc1918
							? `Yes (${privateCheck.data.matched_rfc1918_range})`
							: "No",
					],
					[
						"RFC6598 Shared",
						privateCheck.data.is_rfc6598
							? `Yes (${privateCheck.data.matched_rfc6598_range})`
							: "No",
					],
				],
				privateCheck.timing,
			),
		);
	}

	sections.push(
		renderArticle(
			"Cloudflare Check",
			[
				[
					"Cloudflare",
					cloudflare.data.is_cloudflare
						? `Yes (${(cloudflare.data.matched_ranges || []).join(", ")})`
						: "No",
				],
			],
			cloudflare.timing,
		),
	);

	if (subnet) {
		const subnetRows = [
			["Mode", subnet.data.mode],
			["Network Address", subnet.data.network_address],
			["Netmask", subnet.data.netmask],
			["Wildcard Mask", subnet.data.wildcard_mask],
			["Prefix Length", `/${subnet.data.prefix_length}`],
			["Total Addresses", subnet.data.total_addresses.toLocaleString()],
			["Usable Addresses", subnet.data.usable_addresses.toLocaleString()],
			["First Usable IP", subnet.data.first_usable_ip],
			["Last Usable IP", subnet.data.last_usable_ip],
		];
		if (subnet.data.broadcast_address)
			subnetRows.splice(2, 0, [
				"Broadcast Address",
				subnet.data.broadcast_address,
			]);
		if (subnet.data.note) subnetRows.push(["Note", subnet.data.note]);
		sections.push(
			renderArticle("Subnet Information", subnetRows, subnet.timing),
		);
	}

	return sections.join("");
}

function renderProviderRange(providerRange) {
	const matched = providerRange.data.matched_ranges || [];
	const rows = [
		["Provider", providerRange.data.provider],
		["Address", providerRange.data.address],
		["Provider Range", providerRange.data.is_provider_range ? "Yes" : "No"],
		["IP Version", `IPv${providerRange.data.ip_version}`],
		["Range Source", providerRange.data.range_source],
	];
	if (providerRange.data.range_source_url)
		rows.push(["Range Source URL", providerRange.data.range_source_url]);
	if (providerRange.data.range_source_note)
		rows.push(["Range Source Note", providerRange.data.range_source_note]);
	if (matched.length) rows.push(["Matched Ranges", matched.join(", ")]);
	return renderArticle("Provider Range Check", rows, providerRange.timing);
}

function renderArticle(title, rows, timing) {
	return `<article><h3>${escapeHTML(title)}</h3>${renderTable(rows)}${renderTiming(timing)}</article>`;
}

function renderTable(rows) {
	return `<table><tbody>${rows.map(([key, value]) => `<tr><th>${escapeHTML(key)}</th><td>${escapeHTML(String(value || ""))}</td></tr>`).join("")}</tbody></table>`;
}

function renderTiming(timing) {
	const rows = [
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
	return `<details><summary>API Call Timing</summary>${renderTable(rows)}</details>`;
}

function renderPerformance(totalMs) {
	const networkPath = shouldShowNetworkPath() ? renderNetworkPath() : "";
	return `<article class="performance-timing"><h3>Performance Timing</h3>${renderTable(
		[["Total Response Time", `${totalMs}ms (${(totalMs / 1000).toFixed(3)}s)`]],
	)}${networkPath}</article>`;
}

function renderNetworkPath() {
	const hops = configuredNetworkHops();
	return `<details>
    <summary>Network Path (${hops.length} hops)</summary>
    <div class="network-path">
      ${hops
				.map((hop, index) => {
					const arrow =
						index > 0
							? `<div class="hop-arrow">&darr;${String(hop.detail).includes("mTLS") ? " mTLS" : ""}</div>`
							: "";
					const role = hop.role
						? `<br><em>${escapeHTML(String(hop.role))}</em>`
						: "";
					return `${arrow}<div class="hop"><strong>${escapeHTML(hop.label)}</strong><br><small>${escapeHTML(hop.detail)}</small>${role}</div>`;
				})
				.join("")}
    </div>
  </details>`;
}

function escapeHTML(value) {
	return value.replace(
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
