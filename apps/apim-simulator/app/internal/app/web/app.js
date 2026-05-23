// @ts-check
/// <reference path="./api-types.d.ts" />

/** @typedef {import("./api-types.d.ts").ManagementSummary} ManagementSummary */
/** @typedef {import("./api-types.d.ts").TraceListResponse} TraceListResponse */

const { bindGatewayLogout, initializeGatewayAuthState } =
	window.PlatformIdpAuth;
const {
	buttonElement,
	errorMessage,
	fetchJSON,
	initializeThemeSwitcher,
	inputElement,
	parseJSONObjectText,
	renderJSONInto,
	renderStatusInto,
	requireElement,
	renderSummaryListInto,
	selectElement,
	setText,
	textDefault,
	textAreaElement,
	withButtonBusy,
	withSubmitterBusy,
} = window.PlatformAppShell;
const tenantKey = inputElement("tenant-key");
const statusBox = requireElement("status");
const routes = requireElement("routes");
const subscriptions = requireElement("subscriptions");
const traces = requireElement("traces");
const replayResult = requireElement("replay-result");
const metricApis = requireElement("metric-apis");
const metricRoutes = requireElement("metric-routes");
const metricProducts = requireElement("metric-products");
const metricSubscriptions = requireElement("metric-subscriptions");
const connectionForm = requireElement("connection-form");
const replayForm = requireElement("replay-form");
const logoutButton = buttonElement("logout-btn");
const refreshTracesButton = buttonElement("refresh-traces");
const authState = requireElement("auth-state");

initializeThemeSwitcher();
refreshGatewayIdentity();
bindGatewayLogout(logoutButton);

connectionForm.addEventListener("submit", async (event) => {
	event.preventDefault();
	const connect = async () => {
		await refreshSummary();
		await refreshTraces();
	};
	try {
		await withSubmitterBusy(event, "Connecting", connect);
	} catch (error) {
		renderStatusInto(
			statusBox,
			`Connection failed: ${errorMessage(error)}`,
			true,
		);
	}
});

replayForm.addEventListener("submit", async (event) => {
	event.preventDefault();
	const replay = async () => {
		const headers = parseJSONObjectText(textAreaElement("headers").value);
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
		renderJSONInto(replayResult, data);
		await refreshTraces();
	};
	try {
		await withSubmitterBusy(event, "Replaying", replay);
	} catch (error) {
		setText(replayResult, `Replay failed: ${errorMessage(error)}`);
	}
});

refreshTracesButton.addEventListener("click", async () => {
	try {
		await withButtonBusy(refreshTracesButton, "Refreshing", refreshTraces);
	} catch (error) {
		setText(traces, `Trace refresh failed: ${errorMessage(error)}`);
	}
});

async function refreshSummary() {
	/** @type {ManagementSummary} */
	const summary = await apiFetch("/apim/management/summary");
	setText(metricApis, summary.apis.length);
	setText(metricRoutes, summary.routes.length);
	setText(metricProducts, summary.products.length);
	setText(metricSubscriptions, summary.subscriptions.length);
	renderSummaryListInto(routes, summary.routes, (route) => ({
		title: route.name,
		detail: `${textDefault(route.path_prefix, "/")} to ${route.upstream_base_url}`,
	}));
	renderSummaryListInto(subscriptions, summary.subscriptions, (sub) => ({
		title: sub.name,
		detail: `${sub.id} (${textDefault(sub.state, "active")})`,
	}));
	renderStatusInto(statusBox, "Console is connected.", "success");
}

async function refreshTraces() {
	/** @type {TraceListResponse} */
	const payload = await apiFetch("/apim/management/traces");
	renderJSONInto(traces, payload.items);
}

/**
 * @template T
 * @param {string} path
 * @param {RequestInit=} options
 * @returns {Promise<T>}
 */
async function apiFetch(path, options = {}) {
	const headers = new Headers(options.headers || {});
	headers.set("X-Apim-Tenant-Key", tenantKey.value.trim());
	if (options.body) headers.set("Content-Type", "application/json");
	return fetchJSON(path, { ...options, headers });
}

async function refreshGatewayIdentity() {
	await initializeGatewayAuthState(authState, logoutButton, {
		errorMessage: (error) => `Unable to read gateway session: ${error.message}`,
	});
}
