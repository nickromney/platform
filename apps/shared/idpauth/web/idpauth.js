// @ts-check
/// <reference lib="dom" />

// Shared browser helpers for platform apps using gateway-backed /.auth/me.
(() => {
	/** @typedef {import("../../web/api-types.d.ts").JSONValue} JSONValue */
	/** @typedef {import("../../web/api-types.d.ts").APIErrorMessageOptions} APIErrorMessageOptions */
	/** @typedef {import("../../web/api-types.d.ts").AppShellErrorInput} AppShellErrorInput */
	/** @typedef {import("../../web/api-types.d.ts").PlatformIdpAuth} PlatformIdpAuth */
	/** @typedef {import("../../web/api-types.d.ts").PlatformIdpAuthConfig} PlatformIdpAuthConfig */
	/** @typedef {import("../../web/api-types.d.ts").OIDCProviderMetadata} OIDCProviderMetadata */
	/** @typedef {import("../../web/api-types.d.ts").OIDCRuntimeConfig} OIDCRuntimeConfig */
	/** @typedef {import("../../web/api-types.d.ts").RuntimeConfigBase} RuntimeConfigBase */

	/**
	 * @typedef {object} GatewayClaim
	 * @property {string=} typ
	 * @property {string=} type
	 * @property {string=} val
	 * @property {string=} value
	 */

	/**
	 * @typedef {object} GatewaySession
	 * @property {GatewayClaim[]=} claims
	 * @property {string=} userDetails
	 * @property {string=} user_details
	 * @property {string=} email
	 * @property {string=} preferred_username
	 * @property {string=} name
	 * @property {string=} user_id
	 * @property {string=} userId
	 */

	/**
	 * @typedef {object} ClientPrincipalPayload
	 * @property {GatewaySession=} clientPrincipal
	 */

	/**
	 * @typedef {object} GatewayLogoutOptions
	 * @property {string=} signOutURL
	 * @property {string=} signOutPath
	 * @property {string=} returnParameter
	 */

	/**
	 * @typedef {object} GatewayAuthStateOptions
	 * @property {string=} path
	 * @property {boolean=} ignoreErrors
	 * @property {string | ((error: Error) => string)=} errorMessage
	 */

	const platformWindow =
		/** @type {Window & {PlatformIdpAuthConfig?: PlatformIdpAuthConfig, PlatformIdpAuth?: PlatformIdpAuth}} */ (
			window
		);

	/**
	 * @param {JSONValue} payload
	 * @returns {GatewaySession | null}
	 */
	function normalizeGatewaySession(payload) {
		if (Array.isArray(payload)) {
			return /** @type {GatewaySession | null} */ (payload[0] || null);
		}
		const objectPayload = /** @type {ClientPrincipalPayload | null} */ (
			payload
		);
		if (objectPayload?.clientPrincipal) {
			return objectPayload.clientPrincipal;
		}
		return null;
	}

	/**
	 * @param {GatewaySession} session
	 * @returns {string}
	 */
	function gatewayDisplayName(session) {
		const claims = Array.isArray(session?.claims) ? session.claims : [];
		/**
		 * @param {string} name
		 * @param {string[]} aliases
		 * @returns {string}
		 */
		const claimValue = (name, ...aliases) => {
			const names = [name, ...aliases].map((value) => value.toLowerCase());
			const found = claims.find((claim) => {
				const typ = (claim.typ || claim.type || "").toLowerCase();
				return names.some((claimName) => {
					return typ === claimName || typ.endsWith(`/${claimName}`);
				});
			});
			return found?.val || found?.value || "";
		};
		return (
			claimValue("emailaddress", "email") ||
			claimValue("name") ||
			claimValue("upn", "preferred_username", "unique_name") ||
			claimValue("oid") ||
			session.userDetails ||
			session.user_details ||
			session.email ||
			session.preferred_username ||
			session.name ||
			session.user_id ||
			session.userId ||
			"authenticated user"
		);
	}

	/**
	 * @param {string=} path
	 * @returns {Promise<GatewaySession | null>}
	 */
	async function fetchGatewaySession(path) {
		const response = await fetch(path || "/.auth/me", {
			cache: "no-store",
			headers: { Accept: "application/json" },
		});
		if (!response.ok) {
			throw new Error(`HTTP ${response.status}`);
		}
		const payload = /** @type {JSONValue} */ (await response.json());
		return normalizeGatewaySession(payload);
	}

	/**
	 * @param {string=} returnPath
	 * @param {GatewayLogoutOptions=} options
	 * @returns {string}
	 */
	function gatewayLogoutURL(returnPath, options) {
		const config = gatewayLogoutConfig(options);
		const signOutURL = new URL(
			config.signOutURL || config.signOutPath || "/oauth2/sign_out",
			window.location.origin,
		);
		const returnParameter =
			config.returnParameter ||
			(signOutURL.pathname === "/.auth/logout"
				? "post_logout_redirect_uri"
				: "rd");
		signOutURL.searchParams.set(
			returnParameter,
			returnPath || "/signed-out.html",
		);
		return signOutURL.toString();
	}

	/**
	 * @param {HTMLButtonElement | null | undefined} button
	 * @param {string=} returnPath
	 * @returns {void}
	 */
	function bindGatewayLogout(button, returnPath) {
		if (!button || button.dataset.gatewayLogoutBound === "true") {
			return;
		}
		button.dataset.gatewayLogoutBound = "true";
		button.addEventListener("click", () => {
			window.location.assign(
				button.dataset.signOutUrl ||
					gatewayLogoutURL(returnPath, {
						signOutURL: button.dataset.gatewaySignOutUrl,
						signOutPath: button.dataset.gatewaySignOutPath,
						returnParameter: button.dataset.gatewayReturnParameter,
					}),
			);
		});
	}

	/**
	 * @param {GatewayLogoutOptions=} options
	 * @returns {GatewayLogoutOptions}
	 */
	function gatewayLogoutConfig(options) {
		const runtimeConfig = platformWindow.PlatformIdpAuthConfig || {};
		return {
			signOutURL: stringSetting(
				options?.signOutURL,
				runtimeConfig.gatewaySignOutURL,
				runtimeConfig.gatewayLogoutURL,
				runtimeConfig.signOutURL,
			),
			signOutPath: stringSetting(
				options?.signOutPath,
				runtimeConfig.gatewaySignOutPath,
				runtimeConfig.gatewayLogoutPath,
				runtimeConfig.signOutPath,
			),
			returnParameter: stringSetting(
				options?.returnParameter,
				runtimeConfig.gatewayLogoutReturnParameter,
				runtimeConfig.logoutReturnParameter,
			),
		};
	}

	/**
	 * @param {(string | null | undefined)[]} values
	 * @returns {string}
	 */
	function stringSetting(...values) {
		for (const value of values) {
			if (typeof value === "string" && value.trim()) {
				return value.trim();
			}
		}
		return "";
	}

	/**
	 * @param {Element | null | undefined} authState
	 * @param {HTMLButtonElement | null | undefined} logoutButton
	 * @param {GatewaySession | null | undefined} session
	 * @param {string=} message
	 * @returns {void}
	 */
	function writeGatewayAuthState(authState, logoutButton, session, message) {
		if (authState) {
			authState.textContent = session
				? `Signed in as ${gatewayDisplayName(session)}`
				: message || "Not signed in.";
		}
		if (logoutButton) {
			logoutButton.hidden = !session;
		}
	}

	/**
	 * @param {Element | null | undefined} authState
	 * @param {HTMLButtonElement | null | undefined} logoutButton
	 * @param {GatewayAuthStateOptions=} options
	 * @returns {Promise<GatewaySession | null>}
	 */
	async function initializeGatewayAuthState(authState, logoutButton, options) {
		try {
			const session = await fetchGatewaySession(options?.path);
			writeGatewayAuthState(authState, logoutButton, session);
			return session;
		} catch (error) {
			if (options?.ignoreErrors) {
				writeGatewayAuthState(authState, logoutButton, null);
				return null;
			}
			const normalizedError =
				error instanceof Error ? error : new Error(String(error));
			const message =
				typeof options?.errorMessage === "function"
					? options.errorMessage(normalizedError)
					: options?.errorMessage ||
						`Unable to read gateway session: ${normalizedError.message}`;
			writeGatewayAuthState(authState, logoutButton, null, message);
			return null;
		}
	}

	/**
	 * @param {OIDCRuntimeConfig | null | undefined} config
	 * @returns {string}
	 */
	function oidcDiscoveryURL(config) {
		const authority =
			typeof config?.oidcAuthority === "string"
				? config.oidcAuthority.trim().replace(/\/+$/, "")
				: "";
		if (!authority) {
			throw new Error("OIDC authority is not configured");
		}
		return `${authority}/.well-known/openid-configuration`;
	}

	/**
	 * @param {OIDCRuntimeConfig | null | undefined} config
	 * @returns {Promise<OIDCProviderMetadata>}
	 */
	async function fetchOIDCProviderMetadata(config) {
		const response = await fetch(oidcDiscoveryURL(config), {
			cache: "no-store",
			headers: { Accept: "application/json" },
		});
		if (!response.ok) {
			throw new Error(`OIDC discovery failed with HTTP ${response.status}`);
		}
		const metadata = /** @type {Partial<OIDCProviderMetadata>} */ (
			await response.json()
		);
		if (typeof metadata.token_endpoint !== "string") {
			throw new Error("OIDC discovery metadata did not include token_endpoint");
		}
		if (
			metadata.end_session_endpoint != null &&
			typeof metadata.end_session_endpoint !== "string"
		) {
			throw new Error(
				"OIDC discovery metadata end_session_endpoint must be a string",
			);
		}
		return /** @type {OIDCProviderMetadata} */ (metadata);
	}

	/**
	 * @param {RuntimeConfigBase | null | undefined} config
	 * @returns {string}
	 */
	function primaryAuthMethod(config) {
		return typeof config?.authMethod === "string" ? config.authMethod : "none";
	}

	/**
	 * @param {RuntimeConfigBase | null | undefined} config
	 * @returns {string}
	 */
	function apiAuthMethod(config) {
		return typeof config?.apiAuthMethod === "string"
			? config.apiAuthMethod
			: primaryAuthMethod(config);
	}

	/**
	 * @param {RuntimeConfigBase | null | undefined} config
	 * @returns {boolean}
	 */
	function usesGatewayAuth(config) {
		return (
			primaryAuthMethod(config) === "gateway" ||
			apiAuthMethod(config) === "gateway"
		);
	}

	/**
	 * @param {RuntimeConfigBase | null | undefined} config
	 * @returns {boolean}
	 */
	function apiRequiresOIDCToken(config) {
		return (
			primaryAuthMethod(config) === "oidc" || apiAuthMethod(config) === "oidc"
		);
	}

	/**
	 * @param {RuntimeConfigBase | null | undefined} config
	 * @param {string=} bearerToken
	 * @returns {boolean}
	 */
	function apiActionReady(config, bearerToken) {
		return (
			usesGatewayAuth(config) ||
			!apiRequiresOIDCToken(config) ||
			Boolean((bearerToken || "").trim())
		);
	}

	/**
	 * @param {string} action
	 * @param {string=} clientName
	 * @returns {string}
	 */
	function apiAuthRequiredMessage(action, clientName) {
		const normalizedAction = action.trim() || "using the API";
		const normalizedClientName = clientName?.trim() || "this frontend";
		return `Sign in before ${normalizedAction}. The backend validates JWT/OIDC tokens, so ${normalizedClientName} will not submit unauthenticated API requests.`;
	}

	/** @returns {string} */
	function expiredSessionMessage() {
		return "Session expired. Sign out and sign in again to refresh API access.";
	}

	/**
	 * @param {RuntimeConfigBase | null | undefined} config
	 * @param {AppShellErrorInput} error
	 * @returns {boolean}
	 */
	function gatewaySessionExpired(config, error) {
		return (
			usesGatewayAuth(config) &&
			/invalid or expired access token/i.test(
				error instanceof Error
					? error.message
					: typeof error === "object" && error !== null
						? String(error.message || "")
						: String(error || ""),
			)
		);
	}

	/**
	 * @param {AppShellErrorInput} error
	 * @returns {string}
	 */
	function defaultErrorMessage(error) {
		return error instanceof Error ? error.message : String(error);
	}

	/**
	 * @param {RuntimeConfigBase | null | undefined} config
	 * @param {AppShellErrorInput} error
	 * @param {APIErrorMessageOptions=} options
	 * @returns {string}
	 */
	function apiErrorMessage(config, error, options) {
		if (gatewaySessionExpired(config, error)) {
			return expiredSessionMessage();
		}
		const message = options?.errorMessage
			? options.errorMessage(error)
			: defaultErrorMessage(error);
		const prefix = options?.prefix ?? options?.defaultPrefix ?? "API error";
		return prefix ? `${prefix}: ${message}` : message;
	}

	platformWindow.PlatformIdpAuth = Object.freeze({
		normalizeGatewaySession,
		gatewayDisplayName,
		fetchGatewaySession,
		gatewayLogoutURL,
		bindGatewayLogout,
		writeGatewayAuthState,
		initializeGatewayAuthState,
		oidcDiscoveryURL,
		fetchOIDCProviderMetadata,
		usesGatewayAuth,
		apiRequiresOIDCToken,
		apiActionReady,
		apiAuthRequiredMessage,
		expiredSessionMessage,
		gatewaySessionExpired,
		apiErrorMessage,
	});
})();
