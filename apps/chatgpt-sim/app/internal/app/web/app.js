// @ts-check

/** @typedef {import("./api-types.d.ts").ApiError} ApiError */
/** @typedef {import("./api-types.d.ts").ChatResponse} ChatResponse */
/** @typedef {import("./api-types.d.ts").ConnectorListResponse} ConnectorListResponse */
/** @typedef {import("./api-types.d.ts").ConnectorSummary} ConnectorSummary */
/** @typedef {import("./api-types.d.ts").GatewaySession} GatewaySession */
/** @typedef {import("./api-types.d.ts").RuntimeConfig} RuntimeConfig */

const { bindGatewayLogout, initializeGatewayAuthState } =
	window.PlatformIdpAuth;
const {
	buttonElement,
	errorMessage,
	fetchJSON,
	initializeThemeSwitcher,
	inputElement,
	postJSON,
	readRuntimeConfig,
	renderElementsInto,
	renderJSONInto,
	renderNetworkPathInto,
	renderOptionsInto,
	renderStatusInto,
	requireElement,
	resolveNetworkHops,
	selectElement,
	setTextDefault,
	textDefault,
	withButtonBusy,
	withSubmitterBusy,
} = window.PlatformAppShell;
const config = /** @type {RuntimeConfig} */ (
	readRuntimeConfig("PCE_CHATGPT_GO_CONFIG")
);
const messages = requireElement("messages");
const statusEl = requireElement("status");
const toolOutput = requireElement("tool-output");
const discoveryOutput = requireElement("discovery-output");
const connectorSelect = selectElement("connector");
const connectorList = requireElement("connector-list");
const discoverButton = buttonElement("discover");
const logoutButton = buttonElement("logout-btn");
const networkPathEl = requireElement("network-path");

setTextDefault(requireElement("mcp-url"), config.mcpUrl, "not configured");
setTextDefault(
	requireElement("model-provider"),
	config.modelProvider,
	"deterministic",
);
setTextDefault(
	requireElement("trace-provider"),
	config.traceProvider,
	"disabled",
);
setTextDefault(
	requireElement("dependencies"),
	config.dependencyFootprint,
	"go-plus-shared-idpauth",
);
requireElement("chat-form").addEventListener("submit", submitChat);
discoverButton.addEventListener("click", () =>
	refreshDiscovery(discoverButton),
);
requireElement("connector-form").addEventListener("submit", addConnector);
bindGatewayLogout(logoutButton);
connectorList.addEventListener("click", deleteConnector);
inputElement("connector-url").value = config.mcpUrl || "";

initialize();

async function initialize() {
	initializeThemeSwitcher();
	renderNetworkPathInto(
		networkPathEl,
		configuredNetworkHops(),
		config.showNetworkPath !== false,
	);
	await initializeAuthState();
	await refreshConnectors();
	await refreshDiscovery();
}

async function initializeAuthState() {
	const authState = requireElement("auth-state");
	await initializeGatewayAuthState(authState, logoutButton, {
		ignoreErrors: true,
	});
}

function configuredNetworkHops() {
	return resolveNetworkHops(config, [
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
	]);
}

async function submitChat(event) {
	event.preventDefault();
	const input = inputElement("message");
	const message = input.value.trim();
	if (!message) return;
	input.value = "";
	appendMessage("user", "You", message);
	renderStatusInto(statusEl, "Calling MCP");
	const action = async () => {
		/** @type {ChatResponse} */
		const result = await postJSON("/api/chat", {
			message,
			tool: selectElement("tool").value,
			connector_id: connectorSelect.value,
		});
		const connector = result.connector || selectedConnectorSummary();
		appendMessage(
			"assistant",
			connectorLabel(connector),
			result.assistant,
			connectorMeta(connector),
		);
		renderJSONInto(toolOutput, {
			connector,
			selected_tool: result.selected_tool,
			model: result.model,
			trace: result.trace,
			tool_arguments: result.tool_arguments,
			tool_result: result.tool_result,
			mcp_steps: result.mcp_steps,
		});
		renderJSONInto(discoveryOutput, result.discovery);
		renderStatusInto(statusEl, `Called ${result.selected_tool}`, "success");
	};
	try {
		await withSubmitterBusy(event, "Sending", action);
	} catch (error) {
		const message = errorMessage(error);
		appendMessage("assistant", "ChatGPT Sim", `Error: ${message}`);
		renderStatusInto(statusEl, `Error: ${message}`, true);
	}
}

/**
 * @param {HTMLButtonElement=} button
 */
async function refreshDiscovery(button) {
	renderStatusInto(statusEl, "Discovering");
	const action = async () => {
		const result = await fetchJSON("/api/discovery");
		renderJSONInto(discoveryOutput, result);
		renderStatusInto(statusEl, "Ready", "success");
	};
	try {
		if (button) {
			await withButtonBusy(button, "Discovering", action);
			return;
		}
		await action();
	} catch (error) {
		const message = errorMessage(error);
		renderJSONInto(discoveryOutput, { error: message });
		renderStatusInto(statusEl, `Discovery failed: ${message}`, true);
	}
}

async function refreshConnectors() {
	/** @type {ConnectorListResponse} */
	const result = await fetchJSON("/api/connectors");
	const items = result.items || [];
	renderOptionsInto(connectorSelect, items, (item) => ({
		value: item.id,
		label: `${item.name} (${item.auth})`,
	}));
	renderElementsInto(
		connectorList,
		items,
		connectorElement,
		emptyConnectorElement(),
	);
}

async function addConnector(event) {
	event.preventDefault();
	renderStatusInto(statusEl, "Adding MCP");
	try {
		/** @type {ConnectorSummary} */
		const result = await postJSON("/api/connectors", {
			name: inputElement("connector-name").value,
			url: inputElement("connector-url").value,
			auth: selectElement("connector-auth").value,
			oauth_client_mode: selectElement("connector-client-mode").value,
			oauth_client_id: inputElement("connector-client-id").value,
			oauth_client_secret: inputElement("connector-client-secret").value,
			oauth_token_endpoint_auth_method: selectElement(
				"connector-token-auth-method",
			).value,
			oauth_requested_scopes: inputElement("connector-requested-scopes").value,
			oauth_base_scopes: inputElement("connector-base-scopes").value,
			oauth_authorization_url: inputElement("connector-auth-url").value,
			oauth_token_url: inputElement("connector-token-url").value,
			oauth_registration_url: inputElement("connector-registration-url").value,
			oauth_authorization_server_base: inputElement(
				"connector-auth-server-base",
			).value,
			oauth_resource: inputElement("connector-resource").value,
			oauth_oidc_configuration_url: inputElement("connector-oidc-config-url")
				.value,
			oauth_oidc_userinfo_endpoint: inputElement("connector-oidc-userinfo")
				.value,
			oauth_oidc_scopes_supported: inputElement("connector-oidc-scopes").value,
		});
		await refreshConnectors();
		connectorSelect.value = result.id;
		renderJSONInto(discoveryOutput, result.discovery || result);
		renderStatusInto(
			statusEl,
			result.status === "ready" ? "MCP added" : "MCP discovery failed",
			result.status === "ready" ? "success" : "warning",
		);
	} catch (error) {
		const apiError = /** @type {ApiError} */ (error);
		if (apiError.status === 409 && apiError.payload?.connector) {
			await refreshConnectors();
			connectorSelect.value = apiError.payload.connector.id;
			renderStatusInto(statusEl, "MCP already exists", "warning");
			return;
		}
		renderStatusInto(statusEl, `Add failed: ${errorMessage(apiError)}`, true);
	}
}

async function deleteConnector(event) {
	const target = /** @type {Element | null} */ (event.target);
	const button = target?.closest("[data-delete-connector]");
	if (!button) return;
	const id = button.getAttribute("data-delete-connector");
	renderStatusInto(statusEl, "Deleting MCP");
	try {
		await fetchJSON(`/api/connectors/${encodeURIComponent(id)}`, {
			method: "DELETE",
		});
		await refreshConnectors();
		await refreshDiscovery();
		renderStatusInto(statusEl, "MCP deleted", "success");
	} catch (error) {
		renderStatusInto(statusEl, `Delete failed: ${errorMessage(error)}`, true);
	}
}

/**
 * @param {ConnectorSummary} item
 * @returns {HTMLElement}
 */
function connectorElement(item) {
	const article = document.createElement("article");
	article.className = "connector";

	const header = document.createElement("div");
	header.className = "connector-header";
	const name = document.createElement("strong");
	name.textContent = item.name;
	header.append(name);
	if (item.id !== "default") {
		const button = document.createElement("button");
		button.type = "button";
		button.className = "danger";
		button.dataset.deleteConnector = item.id;
		button.textContent = "Delete";
		header.append(button);
	}
	article.append(header);

	article.append(
		textSpan(textDefault(item.url, "")),
		textSpan(
			`Status: ${textDefault(item.status, "not reported")} | Auth: ${textDefault(item.auth, "none")}`,
		),
		textSpan(
			item.oauth?.authorization_endpoint
				? `OAuth: ${item.oauth.authorization_endpoint}`
				: "OAuth: not discovered",
		),
	);

	if (item.login_url) {
		const link = document.createElement("a");
		link.className = "login-link";
		link.href = item.login_url;
		link.target = "_blank";
		link.rel = "noopener";
		link.textContent = "Sign in";
		article.append(link);
	} else if (item.oauth?.authorization_endpoint) {
		article.append(
			textSpan("Login: enter an OAuth Client ID, then add this connector."),
		);
	}

	if (item.oauth_advanced) {
		const details = document.createElement("details");
		details.className = "connector-details";
		const summary = document.createElement("summary");
		summary.textContent = "Advanced OAuth";
		const pre = document.createElement("pre");
		renderJSONInto(pre, item.oauth_advanced);
		details.append(summary, pre);
		article.append(details);
	}

	if (item.error) {
		article.append(textSpan(item.error, "error"));
	}

	return article;
}

/**
 * @returns {HTMLElement}
 */
function emptyConnectorElement() {
	const paragraph = document.createElement("p");
	paragraph.textContent = "No MCP connectors configured.";
	return paragraph;
}

/**
 * @param {string} text
 * @param {string=} className
 * @returns {HTMLSpanElement}
 */
function textSpan(text, className) {
	const span = document.createElement("span");
	if (className) {
		span.className = className;
	}
	span.textContent = text;
	return span;
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
