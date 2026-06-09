// @ts-check

/** @typedef {import("./api-types.d.ts").RuntimeConfig} RuntimeConfig */
/** @typedef {import("./api-types.d.ts").ApiDiagnostics} ApiDiagnostics */
/** @typedef {import("./api-types.d.ts").CloudflareCheckResult} CloudflareCheckResult */
/** @typedef {import("./api-types.d.ts").HealthResponse} HealthResponse */
/** @typedef {import("./api-types.d.ts").KeyValueTableRow} KeyValueTableRow */
/** @typedef {import("./api-types.d.ts").NetworkHop} NetworkHop */
/** @typedef {import("./api-types.d.ts").PrivateCheckResult} PrivateCheckResult */
/** @typedef {import("./api-types.d.ts").ProviderRangeResult} ProviderRangeResult */
/** @typedef {import("./api-types.d.ts").SubnetInfoResult} SubnetInfoResult */
/** @typedef {import("./api-types.d.ts").TimedResponse<CloudflareCheckResult>} CloudflareTimedResponse */
/** @typedef {import("./api-types.d.ts").TimedResponse<PrivateCheckResult>} PrivateTimedResponse */
/** @typedef {import("./api-types.d.ts").TimedResponse<ProviderRangeResult>} ProviderRangeTimedResponse */
/** @typedef {import("./api-types.d.ts").TimedResponse<SubnetInfoResult>} SubnetTimedResponse */
/** @typedef {import("./api-types.d.ts").TimedResponse<ValidationResult>} ValidationTimedResponse */
/** @typedef {import("./api-types.d.ts").UserInfoResponse} UserInfoResponse */
/** @typedef {import("./api-types.d.ts").ValidationResult} ValidationResult */

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
const {
	apiErrorMessage,
	gatewayLogoutURL,
	apiActionReady,
	apiAuthRequiredMessage,
	apiRequiresOIDCToken,
	fetchOIDCProviderMetadata,
	initializeGatewayAuthState,
	usesGatewayAuth,
} = window.PlatformIdpAuth;
const {
	apiJSONHeaders,
	apiTimingElement,
	buttonElement,
	decodeAPIMTrace,
	errorMessage,
	fetchJSON,
	fetchJSONWithTiming,
	formatAPIHealthStatus,
	initializeThemeSwitcher,
	inputElement,
	keyValueArticleElement,
	parseJSONObjectText,
	readRuntimeConfig,
	renderElementsInto,
	renderMessageInto,
	renderNetworkPathInto,
	renderStatusInto,
	requireElement,
	requireSelectorAll,
	resolveNetworkHops,
	selectElement,
	setText,
	shouldShowNetworkPath,
	withSubmitterBusy,
} = window.PlatformAppShell;
const authPanel = requireElement("auth-panel");
const authState = requireElement("auth-state");
const apiStatus = requireElement("api-status");
const lookupForm = requireElement("lookup-form");
const providerForm = requireElement("provider-form");
const identityForm = requireElement("identity-form");
const resultsPanel = requireElement("results");
const resultsContent = requireElement("results-content");
const logoutButton = buttonElement("logout-btn");
const tokenInput = inputElement("token-input");
const whoamiButton = buttonElement("whoami-btn");

document.addEventListener("DOMContentLoaded", () => {
	initializeThemeSwitcher();
	initializeAuth()
		.catch((error) => {
			renderStatusInto(
				authState,
				`Sign-in failed: ${errorMessage(error)}`,
				true,
			);
		})
		.finally(checkHealth);
	lookupForm.addEventListener("submit", lookup);
	providerForm.addEventListener("submit", providerRangeCheck);
	identityForm.addEventListener("submit", whoami);
	logoutButton.addEventListener("click", () => {
		logoutFromOidc().catch((error) => {
			renderStatusInto(
				authState,
				`Sign-out failed: ${errorMessage(error)}`,
				true,
			);
		});
	});
	requireSelectorAll("[data-example]").forEach((button) => {
		const exampleButton = /** @type {HTMLElement} */ (button);
		button.addEventListener("click", () => {
			inputElement("ip-address").value = exampleButton.dataset.example || "";
		});
	});
});

function runtimeConfig() {
	return /** @type {RuntimeConfig} */ (
		readRuntimeConfig("SUBNETCALC_RUNTIME_CONFIG")
	);
}

async function initializeAuth() {
	const config = runtimeConfig();
	refreshAuthControls();
	if (usesGatewayAuth(config)) {
		await refreshGatewayIdentity();
		return;
	}
	if (!apiRequiresOIDCToken(config)) {
		renderStatusInto(
			authState,
			"API authentication is disabled for this environment.",
		);
		return;
	}

	if (new URLSearchParams(window.location.search).has("code")) {
		await completeOidcLogin(config);
	}
	const token = storedOidcToken();
	if (token) {
		tokenInput.value = token;
		await refreshIdentity();
	} else {
		renderStatusInto(
			authState,
			"Sign in before using the API. Backend API calls require a valid JWT.",
			true,
		);
	}
}

async function checkHealth() {
	try {
		/** @type {HealthResponse} */
		const data = await getJSON(paths.health);
		renderStatusInto(
			apiStatus,
			formatAPIHealthStatus(data, runtimeConfig()),
			"success",
		);
	} catch (error) {
		renderStatusInto(
			apiStatus,
			apiErrorMessage(runtimeConfig(), error, {
				prefix: "API unavailable",
				errorMessage,
			}),
			true,
		);
	}
}

/**
 * @param {SubmitEvent} event
 */
async function lookup(event) {
	event.preventDefault();
	await withSubmitterBusy(event, "Loading", async () => {
		const address = inputElement("ip-address").value.trim();
		const mode = selectElement("cloud-mode").value;
		const content = prepareResults();

		if (!apiReadyForUserAction()) {
			renderMessageInto(content, authRequiredMessage(), "error");
			focusResults();
			return;
		}

		setText(content, "Loading...");

		try {
			const started = performance.now();
			/** @type {ValidationTimedResponse} */
			const validation = await timedPostJSON(paths.validate, { address });
			/** @type {PrivateTimedResponse | null} */
			let privateCheck = null;
			if (validation.data.is_ipv4) {
				privateCheck = await timedPostJSON(paths.private, { address });
			}
			/** @type {CloudflareTimedResponse} */
			const cloudflare = await timedPostJSON(paths.cloudflare, { address });
			/** @type {SubnetTimedResponse | null} */
			let subnet = null;
			if (validation.data.type === "network" && validation.data.is_ipv4) {
				subnet = await timedPostJSON(paths.subnet, { network: address, mode });
			}
			const totalMs = Math.round(performance.now() - started);
			renderElementsInto(
				content,
				[
					...resultElements(validation, privateCheck, cloudflare, subnet),
					performanceElement(totalMs),
				],
				(element) => element,
			);
		} catch (error) {
			renderMessageInto(
				content,
				apiErrorMessage(runtimeConfig(), error, {
					defaultPrefix: "Error",
					errorMessage,
				}),
				"error",
			);
		}
		focusResults();
	});
}

/**
 * @param {SubmitEvent} event
 */
async function whoami(event) {
	event.preventDefault();
	await withSubmitterBusy(event, "Validating", refreshIdentity);
}

/**
 * @param {SubmitEvent} event
 */
async function providerRangeCheck(event) {
	event.preventDefault();
	await withSubmitterBusy(event, "Loading", async () => {
		const address = inputElement("provider-address").value.trim();
		const provider = selectElement("provider-name").value;
		const content = prepareResults();

		if (!apiReadyForUserAction()) {
			renderMessageInto(content, authRequiredMessage(), "error");
			focusResults();
			return;
		}

		setText(content, "Loading...");
		try {
			const started = performance.now();
			/** @type {ProviderRangeTimedResponse} */
			const providerRange = await timedPostJSON(paths.providerRange, {
				provider,
				address,
			});
			const totalMs = Math.round(performance.now() - started);
			renderElementsInto(
				content,
				[providerRangeElement(providerRange), performanceElement(totalMs)],
				(element) => element,
			);
		} catch (error) {
			renderMessageInto(
				content,
				apiErrorMessage(runtimeConfig(), error, {
					defaultPrefix: "Error",
					errorMessage,
				}),
				"error",
			);
		}
		focusResults();
	});
}

function prepareResults() {
	resultsPanel.hidden = false;
	return resultsContent;
}

function focusResults() {
	resultsPanel.focus();
}

async function refreshIdentity() {
	if (usesGatewayAuth(runtimeConfig())) {
		await refreshGatewayIdentity();
		return;
	}
	const token = inputElement("token-input").value.trim();
	try {
		/** @type {UserInfoResponse} */
		const user = await getJSON(
			paths.whoami,
			token ? { Authorization: `Bearer ${token}` } : {},
		);
		renderStatusInto(
			authState,
			`Signed in as ${user.preferred_username || user.email || user.sub}`,
		);
	} catch (error) {
		renderStatusInto(authState, `Not signed in: ${errorMessage(error)}`, true);
	}
}

/**
 * @template T
 * @param {string} path
 * @param {Record<string, string>=} headers
 * @returns {Promise<T>}
 */
async function getJSON(path, headers = {}) {
	return fetchJSON(path, { headers: apiJSONHeaders(runtimeConfig(), headers) });
}

function apiAuthHeaders() {
	if (usesGatewayAuth(runtimeConfig())) {
		return {};
	}
	const input = inputElement("token-input");
	const token = input.value.trim();
	return token ? { Authorization: `Bearer ${token}` } : {};
}

function refreshAuthControls() {
	const gateway = usesGatewayAuth(runtimeConfig());
	const showOidc = apiRequiresOIDCToken(runtimeConfig()) && !gateway;
	const showAuthPanel = showOidc || gateway;
	authPanel.hidden = !showOidc;
	authState.hidden = !showAuthPanel;
	logoutButton.hidden = !showOidc && !gateway;
	tokenInput.hidden = gateway;
	whoamiButton.hidden = gateway;
}

function apiReadyForUserAction() {
	return apiActionReady(runtimeConfig(), inputElement("token-input").value);
}

function authRequiredMessage() {
	return apiAuthRequiredMessage("running API calls", "the calculator");
}

async function completeOidcLogin(config) {
	const params = new URLSearchParams(window.location.search);
	const stateRecord = parseJSONObjectText(sessionStorage.getItem(oidcStateKey));
	const state = typeof stateRecord.state === "string" ? stateRecord.state : "";
	const verifier =
		typeof stateRecord.verifier === "string" ? stateRecord.verifier : "";
	if (!params.get("code") || params.get("state") !== state || !verifier) {
		throw new Error("OIDC callback state did not match");
	}

	const body = new URLSearchParams({
		grant_type: "authorization_code",
		client_id: config.oidcClientId,
		redirect_uri: oidcRedirect(config),
		code: params.get("code"),
		code_verifier: verifier,
	});
	const providerMetadata = await fetchOIDCProviderMetadata(config);
	const response = await fetch(providerMetadata.token_endpoint, {
		method: "POST",
		headers: { "Content-Type": "application/x-www-form-urlencoded" },
		body,
	});
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
	window.history.replaceState(
		{},
		document.title,
		typeof stateRecord.returnUrl === "string" ? stateRecord.returnUrl : "/",
	);
}

async function logoutFromOidc() {
	if (usesGatewayAuth(runtimeConfig())) {
		window.location.assign(gatewayLogoutURL());
		return;
	}
	const config = runtimeConfig();
	const token = parseJSONObjectText(localStorage.getItem(oidcStorageKey));
	localStorage.removeItem(oidcStorageKey);
	tokenInput.value = "";
	renderStatusInto(authState, "Not signed in.", true);
	const idToken = typeof token.idToken === "string" ? token.idToken : "";
	if (config.oidcAuthority && idToken) {
		const providerMetadata = await fetchOIDCProviderMetadata(config);
		if (!providerMetadata.end_session_endpoint) {
			return;
		}
		const params = new URLSearchParams({
			id_token_hint: idToken,
			post_logout_redirect_uri: new URL("/", window.location.origin).toString(),
		});
		window.location.assign(
			`${providerMetadata.end_session_endpoint}?${params}`,
		);
	}
}

async function refreshGatewayIdentity() {
	await initializeGatewayAuthState(authState, logoutButton, {
		errorMessage: (error) =>
			`Unable to read gateway session: ${errorMessage(error)}`,
	});
}

function storedOidcToken() {
	const token = parseJSONObjectText(localStorage.getItem(oidcStorageKey));
	const accessToken =
		typeof token.accessToken === "string" ? token.accessToken : "";
	const expiresAt = typeof token.expiresAt === "number" ? token.expiresAt : 0;
	if (!accessToken || (expiresAt && expiresAt <= Date.now() + 30000)) {
		localStorage.removeItem(oidcStorageKey);
		return "";
	}
	return accessToken;
}

function oidcRedirect(config) {
	return config.oidcRedirect || new URL("/", window.location.origin).toString();
}

/**
 * @template T
 * @param {string} path
 * @param {Record<string, string>} body
 * @returns {Promise<T>}
 */
async function timedPostJSON(path, body) {
	return /** @type {T} */ (
		await fetchJSONWithTiming(
			path,
			{
				method: "POST",
				headers: apiJSONHeaders(runtimeConfig(), apiAuthHeaders()),
				body: JSON.stringify(body),
			},
			decodeAPIMTrace,
		)
	);
}

function configuredNetworkHops() {
	const config = runtimeConfig();
	const backendURL = config.backendURL || "same process";
	const backendRole =
		config.apiAuthMethod === "oidc"
			? "Go backend with server-side token validation"
			: "Go backend";
	return resolveNetworkHops(config, [
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
	]);
}

function resultElements(validation, privateCheck, cloudflare, subnet) {
	/** @type {KeyValueTableRow[]} */
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
		resultArticleElement("Validation", validationRows, validation.timing),
	];

	if (privateCheck) {
		sections.push(
			resultArticleElement(
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
		resultArticleElement(
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
		/** @type {KeyValueTableRow[]} */
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
			resultArticleElement("Subnet Information", subnetRows, subnet.timing),
		);
	}

	return sections;
}

function providerRangeElement(providerRange) {
	const matched = providerRange.data.matched_ranges || [];
	/** @type {KeyValueTableRow[]} */
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
	return resultArticleElement(
		"Provider Range Check",
		rows,
		providerRange.timing,
	);
}

/**
 * @param {string} title
 * @param {KeyValueTableRow[]} rows
 * @param {import("../../../../../shared/web/api-types.d.ts").APITiming} timing
 * @returns {HTMLElement}
 */
function resultArticleElement(title, rows, timing) {
	return keyValueArticleElement(title, rows, apiTimingElement(timing));
}

/**
 * @param {number} totalMs
 * @returns {HTMLElement}
 */
function performanceElement(totalMs) {
	const networkPath = document.createElement("div");
	renderNetworkPathInto(
		networkPath,
		configuredNetworkHops(),
		shouldShowNetworkPath(runtimeConfig()),
	);
	const article = keyValueArticleElement(
		"Performance Timing",
		[["Total Response Time", `${totalMs}ms (${(totalMs / 1000).toFixed(3)}s)`]],
		networkPath,
	);
	article.classList.add("performance-timing");
	return article;
}
