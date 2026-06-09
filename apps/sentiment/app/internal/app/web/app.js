// @ts-check

/** @typedef {import("./api-types.d.ts").RuntimeConfig} RuntimeConfig */
/** @typedef {import("./api-types.d.ts").ApiDiagnostics} ApiDiagnostics */
/** @typedef {import("./api-types.d.ts").CommentListResponse} CommentListResponse */
/** @typedef {import("./api-types.d.ts").HealthResponse} HealthResponse */
/** @typedef {import("./api-types.d.ts").NetworkHop} NetworkHop */
/** @typedef {import("./api-types.d.ts").SentimentComment} SentimentComment */

const {
	apiErrorMessage,
	bindGatewayLogout,
	apiActionReady,
	apiAuthRequiredMessage,
	initializeGatewayAuthState,
	usesGatewayAuth,
} = window.PlatformIdpAuth;
const {
	apiBasePath,
	apiJSONHeaders,
	apiPath,
	apiTimingElement,
	buttonElement,
	buttonSelector,
	decodeAPIMTrace,
	errorMessage,
	fetchJSON,
	fetchJSONWithTiming,
	formatAPIHealthStatus,
	formatTimestamp,
	initializeThemeSwitcher,
	readRuntimeConfig,
	renderElementsInto,
	renderMessageInto,
	renderNetworkPathInto,
	renderStatusInto,
	requireElement,
	requireSelector,
	resolveNetworkHops,
	shouldShowNetworkPath,
	textAreaElement,
	withSubmitterBusy,
} = window.PlatformAppShell;
const statusEl = requireElement("status");
const apiStatusEl = requireElement("api-status");
const diagnosticsEl = requireElement("diagnostics");
const commentsEl = requireElement("comments");
const commentForm = requireElement("comment-form");
const textarea = textAreaElement("comment-text");
const logoutButton = buttonElement("logout-btn");
const analyzeAction = buttonSelector('[data-action="analyze"]');
const positiveSample = requireSelector('[data-sample="positive"]');
const mixedSample = requireSelector('[data-sample="mixed"]');
const negativeSample = requireSelector('[data-sample="negative"]');
const paths = {
	health: "/health",
};

document.addEventListener("DOMContentLoaded", () => {
	initializeThemeSwitcher();
	initializeAuthState().catch((error) => {
		renderStatusInto(
			statusEl,
			apiErrorMessage(runtimeConfig(), error, {
				prefix: "Unable to initialize authentication",
				errorMessage,
			}),
			true,
		);
	});
	checkHealth();
	commentForm.addEventListener("submit", submitComment);
	bindGatewayLogout(logoutButton);
	positiveSample.addEventListener("click", () => {
		textarea.value =
			"I absolutely love this. Great work and fantastic experience.";
	});
	mixedSample.addEventListener("click", () => {
		textarea.value =
			"Some parts are fine, but overall I am disappointed and frustrated.";
	});
	negativeSample.addEventListener("click", () => {
		textarea.value =
			"I am disappointed and frustrated. This was a poor experience.";
	});
});

function runtimeConfig() {
	return /** @type {RuntimeConfig} */ (
		readRuntimeConfig("SENTIMENT_RUNTIME_CONFIG")
	);
}

async function checkHealth() {
	try {
		/** @type {HealthResponse} */
		const data = await getJSON(
			apiPath(runtimeConfig(), paths.health, "/api/v1"),
		);
		renderStatusInto(
			apiStatusEl,
			formatAPIHealthStatus(data, runtimeConfig()),
			"success",
		);
	} catch (error) {
		renderStatusInto(
			apiStatusEl,
			apiErrorMessage(runtimeConfig(), error, {
				prefix: "API unavailable",
				errorMessage,
			}),
			true,
		);
	}
}

function analyzeButton() {
	return analyzeAction;
}

async function initializeAuthState() {
	const authState = requireElement("auth-state");

	if (usesGatewayAuth(runtimeConfig())) {
		const session = await initializeGatewayAuthState(authState, logoutButton);
		if (session) {
			await loadComments();
			return;
		}

		renderStatusInto(statusEl, authRequiredMessage(), true);
		analyzeButton().disabled = true;
		renderMessageInto(commentsEl, "Sign in to load comments.");
		return;
	}

	if (apiReadyForUserAction()) {
		if ((runtimeConfig().apiAuthMethod || "none") === "none") {
			renderStatusInto(
				statusEl,
				"Ready. API authentication is disabled for this environment.",
			);
		}
		await loadComments();
		return;
	}
	renderStatusInto(statusEl, authRequiredMessage(), true);
	analyzeButton().disabled = true;
	renderMessageInto(commentsEl, "Sign in to load comments.");
}

async function loadComments() {
	try {
		const response = await timedFetchJSON(
			apiPath(runtimeConfig(), "/comments?limit=25", "/api/v1"),
		);
		/** @type {CommentListResponse} */
		const data = response.data;
		renderComments(data.items || []);
		renderAPIDiagnostics("Load comments", response.timing);
		renderStatusInto(statusEl, "Ready.", "success");
	} catch (error) {
		renderMessageInto(
			commentsEl,
			apiErrorMessage(runtimeConfig(), error, { errorMessage }),
		);
		throw error;
	}
}

async function submitComment(event) {
	event.preventDefault();
	const text = textarea.value.trim();
	if (!text) {
		renderStatusInto(statusEl, "Text is required.", "warning");
		return;
	}
	if (!apiReadyForUserAction()) {
		renderStatusInto(statusEl, authRequiredMessage(), true);
		return;
	}
	const action = async () => {
		const response = await timedFetchJSON(
			apiPath(runtimeConfig(), "/comments", "/api/v1"),
			{
				method: "POST",
				headers: apiJSONHeaders(runtimeConfig()),
				body: JSON.stringify({ text }),
			},
		);
		/** @type {SentimentComment} */
		const result = response.data;
		renderStatusInto(
			statusEl,
			`Saved. ${result.label} | Latency: ${result.latency_ms}ms`,
			"success",
		);
		textarea.value = "";
		await loadComments();
		renderAPIDiagnostics("Submit comment", response.timing);
	};
	try {
		await withSubmitterBusy(event, "Analyzing", action);
	} catch (error) {
		renderStatusInto(
			statusEl,
			apiErrorMessage(runtimeConfig(), error, {
				errorMessage,
			}),
			true,
		);
	}
}

function apiReadyForUserAction() {
	return apiActionReady(runtimeConfig());
}

function authRequiredMessage() {
	return apiAuthRequiredMessage("using sentiment analysis");
}

/**
 * @template T
 * @param {string} url
 * @returns {Promise<T>}
 */
async function getJSON(url) {
	return fetchJSON(url, { headers: apiJSONHeaders(runtimeConfig()) });
}

/**
 * @template T
 * @param {string} url
 * @param {RequestInit=} options
 * @returns {Promise<{data: T, timing: import("../../../../../shared/web/api-types.d.ts").APITiming}>}
 */
async function timedFetchJSON(url, options = {}) {
	const headers = {
		...apiJSONHeaders(runtimeConfig()),
		...(options.headers || {}),
	};
	return fetchJSONWithTiming(url, { ...options, headers }, decodeAPIMTrace);
}

function renderComments(items) {
	if (items.length === 0) {
		renderMessageInto(commentsEl, "No comments yet.");
		return;
	}
	renderElementsInto(commentsEl, items, commentElement);
}

/**
 * @param {SentimentComment} item
 * @returns {HTMLElement}
 */
function commentElement(item) {
	const article = document.createElement("article");
	article.className = "comment card";

	const label = document.createElement("span");
	label.className = "label";
	label.textContent = item.label;

	const meta = document.createElement("span");
	meta.className = "meta";
	meta.textContent = `${formatTimestamp(item.timestamp)} | Confidence: ${Number(item.confidence).toFixed(2)} | Latency: ${item.latency_ms}ms`;

	const text = document.createElement("p");
	text.textContent = item.text;

	article.append(label, meta, text);
	return article;
}

function renderAPIDiagnostics(action, timing) {
	const networkPath = document.createElement("div");
	renderNetworkPathInto(
		networkPath,
		configuredNetworkHops(),
		shouldShowNetworkPath(runtimeConfig()),
	);
	diagnosticsEl.replaceChildren(
		apiTimingElement(timing, {
			action,
			backendURL: runtimeConfig().backendURL || "same process",
			open: true,
		}),
		networkPath,
	);
}

function configuredNetworkHops() {
	const config = runtimeConfig();
	const backendURL = config.backendURL || "same process";
	const backendRole = String(backendURL).includes("apim")
		? "API gateway forwarding to sentiment-api"
		: "Go API";
	return resolveNetworkHops(config, [
		{
			label: "Browser",
			detail: window.location.origin,
			role: "Vanilla frontend",
		},
		{
			label: "Sentiment frontend",
			detail: `${apiBasePath(config, "/api/v1")}/*`,
			role: "Same-origin API route",
		},
		{ label: "Sentiment API", detail: backendURL, role: backendRole },
	]);
}
