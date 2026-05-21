// @ts-check

const tenantKey = inputElement("tenant-key");
const statusBox = document.getElementById("status");
const routes = document.getElementById("routes");
const subscriptions = document.getElementById("subscriptions");
const traces = document.getElementById("traces");
const replayResult = document.getElementById("replay-result");
const themeOptions = ["system", "light", "dark"];
const themeSwitcher = document.getElementById("theme-switcher");
const logoutButton = document.getElementById("logout-btn");

applyTheme(readThemeCookie());
refreshGatewayIdentity();
themeSwitcher.addEventListener("click", () => {
	const theme = document.documentElement.getAttribute("data-theme") || "system";
	const nextTheme =
		themeOptions[(themeOptions.indexOf(theme) + 1) % themeOptions.length];
	writeThemeCookie(nextTheme);
	applyTheme(nextTheme);
});
logoutButton.addEventListener("click", () => {
	window.location.assign(gatewayLogoutURL());
});

document
	.getElementById("connection-form")
	.addEventListener("submit", async (event) => {
		event.preventDefault();
		await refreshSummary();
		await refreshTraces();
	});

document
	.getElementById("replay-form")
	.addEventListener("submit", async (event) => {
		event.preventDefault();
		const headers = JSON.parse(textAreaElement("headers").value || "{}");
		const payload = {
			method: selectElement("method").value,
			path: inputElement("path").value,
			headers,
			body_text: textAreaElement("body").value || undefined,
		};
		const data = await apiFetch("/apim/management/replay", {
			method: "POST",
			body: JSON.stringify(payload),
		});
		replayResult.textContent = JSON.stringify(data, null, 2);
		await refreshTraces();
	});

document
	.getElementById("refresh-traces")
	.addEventListener("click", refreshTraces);

async function refreshSummary() {
	const summary = await apiFetch("/apim/management/summary");
	document.getElementById("metric-apis").textContent = String(
		summary.apis.length,
	);
	document.getElementById("metric-routes").textContent = String(
		summary.routes.length,
	);
	document.getElementById("metric-products").textContent = String(
		summary.products.length,
	);
	document.getElementById("metric-subscriptions").textContent = String(
		summary.subscriptions.length,
	);
	routes.innerHTML = summary.routes
		.map(
			(route) =>
				`<li><strong>${escapeHTML(route.name)}</strong><span>${escapeHTML(route.path_prefix || "/")} to ${escapeHTML(route.upstream_base_url)}</span></li>`,
		)
		.join("");
	subscriptions.innerHTML = summary.subscriptions
		.map(
			(sub) =>
				`<li><strong>${escapeHTML(sub.name)}</strong><span>${escapeHTML(sub.id)} (${escapeHTML(sub.state || "active")})</span></li>`,
		)
		.join("");
	statusBox.textContent = "Console is connected.";
}

async function refreshTraces() {
	const payload = await apiFetch("/apim/management/traces");
	traces.textContent = JSON.stringify(payload.items, null, 2);
}

async function apiFetch(path, options = {}) {
	const headers = new Headers(options.headers || {});
	headers.set("X-Apim-Tenant-Key", tenantKey.value.trim());
	if (options.body) headers.set("Content-Type", "application/json");
	const response = await fetch(path, { ...options, headers });
	if (!response.ok) throw new Error(await response.text());
	return response.json();
}

function escapeHTML(value) {
	return String(value || "").replace(
		/[&<>"']/g,
		(char) =>
			({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
				char
			],
	);
}

function inputElement(id) {
	return /** @type {HTMLInputElement} */ (document.getElementById(id));
}

function selectElement(id) {
	return /** @type {HTMLSelectElement} */ (document.getElementById(id));
}

function textAreaElement(id) {
	return /** @type {HTMLTextAreaElement} */ (document.getElementById(id));
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
			logoutButton.hidden = false;
			return;
		}
		authState.textContent = "Not signed in.";
		logoutButton.hidden = true;
	} catch (error) {
		authState.textContent = `Unable to read gateway session: ${error.message}`;
		logoutButton.hidden = true;
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

function gatewayLogoutURL() {
	const oauthSignOut = new URL("/oauth2/sign_out", window.location.origin);
	oauthSignOut.searchParams.set("rd", "/signed-out.html");
	return oauthSignOut.toString();
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

function themeCookieDomain() {
	return window.location.hostname.endsWith("127.0.0.1.sslip.io")
		? "; Domain=.127.0.0.1.sslip.io"
		: "";
}

function writeThemeCookie(theme) {
	const safeTheme = themeOptions.includes(theme) ? theme : "system";
	const secure = window.location.protocol === "https:" ? "; Secure" : "";
	// biome-ignore lint/suspicious/noDocumentCookie: Keep parity with the other static Go apps and support older local browsers.
	document.cookie = `pce-theme=${encodeURIComponent(safeTheme)}; Path=/; Max-Age=31536000; SameSite=Lax${themeCookieDomain()}${secure}`;
}

function applyTheme(theme) {
	const nextTheme =
		themeOptions[(themeOptions.indexOf(theme) + 1) % themeOptions.length];
	document.documentElement.setAttribute("data-theme", theme);
	themeSwitcher.dataset.themeChoice = theme;
	themeSwitcher.setAttribute(
		"aria-label",
		`Theme: ${theme}. Switch to ${nextTheme} theme.`,
	);
	themeSwitcher.title = `Theme: ${theme}. Switch to ${nextTheme} theme.`;
}
