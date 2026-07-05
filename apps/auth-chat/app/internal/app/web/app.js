// @ts-check
/// <reference lib="dom" />

/** @typedef {import("../../../../../shared/web/api-types.d.ts").AppShellErrorInput} AppShellErrorInput */
/** @typedef {import("./api-types.d.ts").ApiError} ApiError */
/** @typedef {import("./api-types.d.ts").AuthEvidence} AuthEvidence */
/** @typedef {import("./api-types.d.ts").ChatResponse} ChatResponse */
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
	renderJSONInto,
	renderNetworkPathInto,
	renderStatusInto,
	requireElement,
	resolveNetworkHops,
	setTextDefault,
	withButtonBusy,
	withSubmitterBusy,
} = window.PlatformAppShell;

const config = /** @type {RuntimeConfig} */ (
	/** @type {unknown} */ (readRuntimeConfig("AUTH_CHAT_CONFIG"))
);
const messages = requireElement("messages");
const statusEl = requireElement("conversation-status");
const authBadge = requireElement("auth-badge");
const authUser = requireElement("auth-user");
const authToken = requireElement("auth-token");
const modelInput = inputElement("model");
const modelRoute = requireElement("model-route");
const modelStatus = requireElement("model-status");
const modelLatency = requireElement("model-latency");
const lastResponse = requireElement("last-response");
const networkPathEl = requireElement("network-path");
const logoutButton = buttonElement("logout-btn");
const validateAuthButton = buttonElement("validate-auth");

requireElement("chat-form").addEventListener("submit", submitChat);
validateAuthButton.addEventListener("click", () =>
	validateAuth(validateAuthButton),
);
bindGatewayLogout(logoutButton);

initialize();

async function initialize() {
	initializeThemeSwitcher();
	modelInput.value = config.model || modelInput.value;
	setTextDefault(modelRoute, config.llmUrl, "not configured");
	renderNetworkPathInto(
		networkPathEl,
		configuredNetworkHops(),
		config.showNetworkPath !== false,
	);
	await initializeAuthState();
	await refreshAuthEvidence();
	appendMessage(
		"assistant",
		"Auth Chat",
		"Ready. /auth is available and /chat will use the configured model route.",
	);
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
			role: "Single page app",
		},
		{
			label: "Keycloak SSO",
			detail:
				config.apiAuthMode === "gateway"
					? "oauth2-proxy headers"
					: config.apiAuthMode,
			role: "/auth",
		},
		{
			label: "Auth Chat",
			detail: config.chatEndpoint,
			role: "/chat",
		},
		{
			label: "Model Endpoint",
			detail: config.llmUrl,
			role: config.model,
		},
	]);
}

async function refreshAuthEvidence() {
	try {
		/** @type {AuthEvidence} */
		const evidence = await fetchJSON(config.authEndpoint);
		renderAuthEvidence(evidence);
		renderJSONInto(lastResponse, { auth: evidence });
	} catch (error) {
		authBadge.textContent = "Error";
		authBadge.className = "error";
		authUser.textContent = "Unavailable";
		authToken.textContent = errorMessage(
			/** @type {AppShellErrorInput} */ (error),
		);
	}
}

/**
 * @param {HTMLButtonElement} button
 */
async function validateAuth(button) {
	const action = async () => {
		/** @type {{valid?: boolean, evidence?: AuthEvidence}} */
		const result = await postJSON(config.authValidateEndpoint, {});
		if (result.evidence) {
			renderAuthEvidence(result.evidence);
		}
		renderJSONInto(lastResponse, result);
		renderStatusInto(
			statusEl,
			result.valid ? "Auth valid" : "Auth invalid",
			result.valid ? "success" : true,
		);
	};
	try {
		await withButtonBusy(button, "Validating", action);
	} catch (error) {
		renderStatusInto(
			statusEl,
			`Auth error: ${errorMessage(/** @type {AppShellErrorInput} */ (error))}`,
			true,
		);
	}
}

/**
 * @param {AuthEvidence} evidence
 */
function renderAuthEvidence(evidence) {
	authBadge.textContent =
		evidence.status === "authenticated" ? "Signed in" : evidence.status;
	authBadge.className = evidence.status === "authenticated" ? "ok" : "";
	const user = evidence.user || {};
	authUser.textContent = String(
		user.email || user.preferred_username || user.sub || "anonymous",
	);
	const token = evidence.token || {};
	authToken.textContent = token.present
		? `${token.source || "token"} (${token.redacted || "redacted"})`
		: "not present";
}

/**
 * @param {SubmitEvent} event
 */
async function submitChat(event) {
	event.preventDefault();
	const input = inputElement("message");
	const message = input.value.trim();
	if (!message) return;
	input.value = "";
	appendMessage("user", "You", message);
	renderStatusInto(statusEl, "Calling /chat");
	const action = async () => {
		/** @type {ChatResponse} */
		const result = await postJSON(config.chatEndpoint, {
			message,
			model: modelInput.value.trim() || config.model,
		});
		appendMessage("assistant", modelLabel(result), result.assistant);
		if (result.auth) {
			renderAuthEvidence(result.auth);
		}
		if (result.model) {
			modelStatus.textContent = String(result.model.status || "ok");
			modelLatency.textContent =
				result.model.latency_ms === undefined
					? "-"
					: `${String(result.model.latency_ms)} ms`;
			if (result.model.route) {
				modelRoute.textContent = String(result.model.route);
			}
		}
		renderJSONInto(lastResponse, result);
		renderStatusInto(statusEl, "Ready", "success");
	};
	try {
		await withSubmitterBusy(event, "Sending", action);
	} catch (error) {
		const message = errorMessage(/** @type {AppShellErrorInput} */ (error));
		appendMessage("assistant", "Auth Chat", `Error: ${message}`);
		renderStatusInto(statusEl, `Error: ${message}`, true);
	}
}

/**
 * @param {"assistant" | "user"} role
 * @param {string} author
 * @param {string} content
 */
function appendMessage(role, author, content) {
	const item = document.createElement("li");
	item.className = `message ${role}`;
	const label = document.createElement("strong");
	label.textContent = author;
	const text = document.createElement("p");
	text.textContent = content;
	item.append(label, text);
	messages.append(item);
	messages.scrollTop = messages.scrollHeight;
}

/**
 * @param {ChatResponse} result
 */
function modelLabel(result) {
	const model = result.model || {};
	return String(model.model || config.model || "Model");
}
