// @ts-check

/** @typedef {import("./api-types.d.ts").ApiError} ApiError */
/** @typedef {import("./api-types.d.ts").ChatResponse} ChatResponse */
/** @typedef {import("./api-types.d.ts").ConnectorListResponse} ConnectorListResponse */
/** @typedef {import("./api-types.d.ts").ConnectorSummary} ConnectorSummary */
/** @typedef {import("./api-types.d.ts").GatewaySession} GatewaySession */
/** @typedef {import("./api-types.d.ts").RuntimeConfig} RuntimeConfig */

const config = window.PCE_CHATGPT_GO_CONFIG || {};
const messages = requireElement("messages");
const statusEl = requireElement("status");
const toolOutput = requireElement("tool-output");
const discoveryOutput = requireElement("discovery-output");
const connectorSelect = selectElement("connector");
const connectorList = requireElement("connector-list");
const themeOptions = ["system", "light", "dark"];

requireElement("mcp-url").textContent = config.mcpUrl || "unknown";
requireElement("model-provider").textContent =
	config.modelProvider || "deterministic";
requireElement("dependencies").textContent =
	config.dependencies || "go-stdlib-only";
requireElement("chat-form").addEventListener("submit", submitChat);
requireElement("discover").addEventListener("click", refreshDiscovery);
requireElement("connector-form").addEventListener("submit", addConnector);
requireElement("theme-switcher").addEventListener("click", toggleTheme);
requireElement("logout-btn").addEventListener("click", logoutFromGateway);
connectorList.addEventListener("click", deleteConnector);
inputElement("connector-url").value = config.mcpUrl || "";

initialize();

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

async function initialize() {
	initializeTheme();
	renderNetworkPath();
	await initializeAuthState();
	await refreshConnectors();
	await refreshDiscovery();
}

async function initializeAuthState() {
	const authState = requireElement("auth-state");
	const logoutButton = /** @type {HTMLButtonElement} */ (
		requireElement("logout-btn")
	);
	try {
		const session = await fetchGatewaySession();
		if (session) {
			authState.textContent = `Signed in as ${gatewayDisplayName(session)}`;
			logoutButton.hidden = false;
			return;
		}
	} catch {
		// Direct local runs do not expose the gateway session endpoint.
	}
	authState.textContent = "Not signed in.";
	logoutButton.hidden = true;
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
	const switcher = requireElement("theme-switcher");
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
		return /** @type {GatewaySession | null} */ (payload[0] || null);
	}
	if (payload?.clientPrincipal) {
		return /** @type {GatewaySession | null} */ (payload.clientPrincipal);
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
		session.user_details ||
		session.email ||
		session.preferred_username ||
		session.name ||
		"authenticated user"
	);
}

function logoutFromGateway() {
	window.location.assign("/oauth2/sign_out?rd=/signed-out.html");
}

function renderNetworkPath() {
	const container = requireElement("network-path");
	if (config.showNetworkPath === false) {
		container.replaceChildren();
		return;
	}
	const hops = configuredNetworkHops();
	container.innerHTML = `<details>
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

function configuredNetworkHops() {
	if (
		Array.isArray(config.networkHops) &&
		config.networkHops.every(isNetworkHop)
	) {
		return config.networkHops;
	}
	return [
		{
			label: "Browser",
			detail: window.location.origin,
			role: "User agent",
		},
		{
			label: "OAuth2 Proxy",
			detail: "/oauth2 and forwarded identity headers",
			role: "Gateway authentication",
		},
		{
			label: "ChatGPT Sim",
			detail: config.mcpUrl || "/api/chat",
			role: "Go shell and same-origin API",
		},
		{
			label: "MCP Server",
			detail: config.mcpUrl || "configured MCP endpoint",
			role: "Tool discovery and calls",
		},
		{
			label: "Model Gateway",
			detail: config.modelProvider || "deterministic",
			role: "Assistant response",
		},
	];
}

function isNetworkHop(value) {
	return (
		value && typeof value.label === "string" && typeof value.detail === "string"
	);
}

async function submitChat(event) {
	event.preventDefault();
	const input = inputElement("message");
	const message = input.value.trim();
	if (!message) return;
	input.value = "";
	appendMessage("user", "You", message);
	statusEl.textContent = "Calling MCP";
	try {
		const result = /** @type {ChatResponse} */ (
			await postJSON("/api/chat", {
				message,
				tool: selectElement("tool").value,
				connector_id: connectorSelect.value,
			})
		);
		const connector = result.connector || selectedConnectorSummary();
		appendMessage(
			"assistant",
			connectorLabel(connector),
			result.assistant,
			connectorMeta(connector),
		);
		toolOutput.textContent = JSON.stringify(
			{
				connector,
				selected_tool: result.selected_tool,
				model: result.model,
				tool_arguments: result.tool_arguments,
				tool_result: result.tool_result,
				mcp_steps: result.mcp_steps,
			},
			null,
			2,
		);
		discoveryOutput.textContent = JSON.stringify(result.discovery, null, 2);
		statusEl.textContent = `Called ${result.selected_tool}`;
	} catch (error) {
		appendMessage("assistant", "ChatGPT Sim", `Error: ${error.message}`);
		statusEl.textContent = `Error: ${error.message}`;
	}
}

async function refreshDiscovery() {
	statusEl.textContent = "Discovering";
	try {
		const result = await fetchJSON("/api/discovery");
		discoveryOutput.textContent = JSON.stringify(result, null, 2);
		statusEl.textContent = "Ready";
	} catch (error) {
		discoveryOutput.textContent = JSON.stringify(
			{ error: error.message },
			null,
			2,
		);
		statusEl.textContent = `Discovery failed: ${error.message}`;
	}
}

async function refreshConnectors() {
	const result = /** @type {ConnectorListResponse} */ (
		await fetchJSON("/api/connectors")
	);
	const items = result.items || [];
	connectorSelect.innerHTML = items
		.map(
			(item) =>
				`<option value="${escapeAttr(item.id)}">${escapeHTML(item.name)} (${escapeHTML(item.auth)})</option>`,
		)
		.join("");
	connectorList.innerHTML =
		items.map(renderConnector).join("") ||
		"<p>No MCP connectors configured.</p>";
}

async function addConnector(event) {
	event.preventDefault();
	statusEl.textContent = "Adding MCP";
	try {
		const result = /** @type {ConnectorSummary} */ (
			await postJSON("/api/connectors", {
				name: inputElement("connector-name").value,
				url: inputElement("connector-url").value,
				auth: selectElement("connector-auth").value,
				oauth_client_mode: selectElement("connector-client-mode").value,
				oauth_client_id: inputElement("connector-client-id").value,
				oauth_client_secret: inputElement("connector-client-secret").value,
				oauth_token_endpoint_auth_method: selectElement(
					"connector-token-auth-method",
				).value,
				oauth_requested_scopes: inputElement("connector-requested-scopes")
					.value,
				oauth_base_scopes: inputElement("connector-base-scopes").value,
				oauth_authorization_url: inputElement("connector-auth-url").value,
				oauth_token_url: inputElement("connector-token-url").value,
				oauth_registration_url: inputElement("connector-registration-url")
					.value,
				oauth_authorization_server_base: inputElement(
					"connector-auth-server-base",
				).value,
				oauth_resource: inputElement("connector-resource").value,
				oauth_oidc_configuration_url: inputElement("connector-oidc-config-url")
					.value,
				oauth_oidc_userinfo_endpoint: inputElement("connector-oidc-userinfo")
					.value,
				oauth_oidc_scopes_supported: inputElement("connector-oidc-scopes")
					.value,
			})
		);
		await refreshConnectors();
		connectorSelect.value = result.id;
		discoveryOutput.textContent = JSON.stringify(
			result.discovery || result,
			null,
			2,
		);
		statusEl.textContent =
			result.status === "ready" ? "MCP added" : "MCP discovery failed";
	} catch (error) {
		const apiError = /** @type {ApiError} */ (error);
		if (apiError.status === 409 && apiError.payload?.connector) {
			await refreshConnectors();
			connectorSelect.value = apiError.payload.connector.id;
			statusEl.textContent = "MCP already exists";
			return;
		}
		statusEl.textContent = `Add failed: ${apiError.message}`;
	}
}

async function deleteConnector(event) {
	const target = /** @type {Element | null} */ (event.target);
	const button = target?.closest("[data-delete-connector]");
	if (!button) return;
	const id = button.getAttribute("data-delete-connector");
	statusEl.textContent = "Deleting MCP";
	try {
		await requestJSON(`/api/connectors/${encodeURIComponent(id)}`, {
			method: "DELETE",
		});
		await refreshConnectors();
		await refreshDiscovery();
		statusEl.textContent = "MCP deleted";
	} catch (error) {
		statusEl.textContent = `Delete failed: ${error.message}`;
	}
}

function renderConnector(item) {
	const oauth = item.oauth?.authorization_endpoint
		? `<span>OAuth: ${escapeHTML(item.oauth.authorization_endpoint)}</span>`
		: "<span>OAuth: not discovered</span>";
	const login = item.login_url
		? `<a class="login-link" href="${escapeAttr(item.login_url)}" target="_blank" rel="noopener">Sign in</a>`
		: item.oauth?.authorization_endpoint
			? `<span>Login: enter an OAuth Client ID, then add this connector.</span>`
			: "";
	const error = item.error
		? `<span class="error">${escapeHTML(item.error)}</span>`
		: "";
	const advanced = item.oauth_advanced
		? `<details class="connector-details"><summary>Advanced OAuth</summary><pre>${escapeHTML(JSON.stringify(item.oauth_advanced, null, 2))}</pre></details>`
		: "";
	const actions =
		item.id === "default"
			? ""
			: `<button type="button" class="danger" data-delete-connector="${escapeAttr(item.id)}">Delete</button>`;
	return `
    <article class="connector">
      <div class="connector-header">
        <strong>${escapeHTML(item.name)}</strong>
        ${actions}
      </div>
      <span>${escapeHTML(item.url)}</span>
      <span>Status: ${escapeHTML(item.status)} | Auth: ${escapeHTML(item.auth)}</span>
      ${oauth}
      ${login}
      ${advanced}
      ${error}
    </article>
  `;
}

function appendMessage(kind, label, text, meta) {
	const item = document.createElement("li");
	item.className = kind;
	const article = document.createElement("article");
	article.className = `message ${kind}`;
	const strong = document.createElement("strong");
	strong.textContent = label;
	article.append(strong);
	if (meta) {
		const metaEl = document.createElement("span");
		metaEl.className = "message-meta";
		metaEl.textContent = meta;
		article.append(metaEl);
	}
	const body = document.createElement("div");
	body.textContent = text;
	article.append(body);
	item.append(article);
	messages.append(item);
	messages.scrollTop = messages.scrollHeight;
}

function selectedConnectorSummary() {
	const option = connectorSelect.selectedOptions?.[0];
	return {
		id: connectorSelect.value,
		name: option ? option.textContent : connectorSelect.value,
	};
}

function connectorLabel(connector) {
	const name = connector?.name ? connector.name : "selected MCP";
	return `ChatGPT Sim via ${name}`;
}

function connectorMeta(connector) {
	if (!connector) return "";
	const parts = [];
	if (connector.id) parts.push(`id=${connector.id}`);
	if (connector.auth) parts.push(`auth=${connector.auth}`);
	if (connector.url) parts.push(connector.url);
	return parts.join(" | ");
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

function escapeAttr(value) {
	return escapeHTML(value).replace(/`/g, "&#96;");
}

async function postJSON(url, body) {
	return requestJSON(url, {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify(body),
	});
}

async function requestJSON(url, options = {}) {
	const response = await fetch(url, options);
	if (response.status === 204) return {};
	const payload = await response.json().catch(() => ({}));
	if (!response.ok) {
		const error = /** @type {ApiError} */ (
			new Error(payload.error || `HTTP ${response.status}`)
		);
		error.status = response.status;
		error.payload = payload;
		throw error;
	}
	return payload;
}

async function fetchJSON(url) {
	return requestJSON(url);
}
