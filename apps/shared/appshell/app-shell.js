// @ts-check
/// <reference lib="dom" />

// Shared app shell helpers for the dependency-free platform browser apps.
(() => {
	/** @typedef {"system" | "light" | "dark"} ThemeMode */
	/**
	 * @typedef {object} APIMTrace
	 * @property {string=} route
	 * @property {string=} upstream_url
	 * @property {number=} elapsed_ms
	 * @property {number=} status
	 */
	/**
	 * @typedef {object} NetworkHop
	 * @property {string} label
	 * @property {string} detail
	 * @property {string=} role
	 * @property {string=} url
	 */
	/**
	 * @typedef {object} RuntimeConfigBase
	 * @property {string=} apiBasePath
	 * @property {string=} backendURL
	 * @property {boolean=} showNetworkPath
	 * @property {NetworkHop[]=} networkHops
	 */
	/** @typedef {import("../web/api-types.d.ts").JSONValue} JSONValue */
	/** @typedef {import("../web/api-types.d.ts").JSONObject} JSONObject */
	/** @typedef {import("../web/api-types.d.ts").APIHealthStatus} APIHealthStatus */
	/** @typedef {import("../web/api-types.d.ts").APITiming} APITiming */
	/** @typedef {import("../web/api-types.d.ts").APITimingRenderOptions} APITimingRenderOptions */
	/** @typedef {import("../web/api-types.d.ts").AppShellTextValue} AppShellTextValue */
	/** @typedef {import("../web/api-types.d.ts").AppShellJSONValue} AppShellJSONValue */
	/** @typedef {import("../web/api-types.d.ts").AppShellErrorInput} AppShellErrorInput */
	/** @typedef {import("../web/api-types.d.ts").AppShellStatusTone} AppShellStatusTone */
	/** @typedef {import("../web/api-types.d.ts").PlatformAppShell} PlatformAppShell */
	/** @typedef {{label?: AppShellTextValue, detail?: AppShellTextValue}} NetworkHopCandidate */
	/** @typedef {{route?: AppShellTextValue, upstream_url?: AppShellTextValue, elapsed_ms?: AppShellTextValue, status?: AppShellTextValue}} APIMTraceCandidate */

	/** @type {ThemeMode[]} */
	const themeOptions = ["system", "light", "dark"];
	let themeMediaBound = false;

	/**
	 * @param {ThemeMode | string | null | undefined} theme
	 * @returns {ThemeMode}
	 */
	function safeTheme(theme) {
		return theme === "light" || theme === "dark" || theme === "system"
			? theme
			: "system";
	}

	/** @returns {ThemeMode} */
	function readThemeCookie() {
		const prefix = "pce-theme=";
		const cookieValue = document.cookie
			.split(";")
			.map((value) => value.trim())
			.find((value) => value.startsWith(prefix));
		const theme = cookieValue
			? decodeURIComponent(cookieValue.slice(prefix.length))
			: "";
		return safeTheme(theme);
	}

	function themeCookieDomain() {
		return window.location.hostname.endsWith("127.0.0.1.sslip.io")
			? "; Domain=.127.0.0.1.sslip.io"
			: "";
	}

	/** @param {ThemeMode | string | null | undefined} theme */
	function writeThemeCookie(theme) {
		const maxAge = 60 * 60 * 24 * 365;
		const secure = window.location.protocol === "https:" ? "; Secure" : "";
		// biome-ignore lint/suspicious/noDocumentCookie: Static Go apps share a local browser preference across platform subdomains.
		document.cookie = `pce-theme=${encodeURIComponent(safeTheme(theme))}; Path=/; Max-Age=${maxAge}; SameSite=Lax${themeCookieDomain()}${secure}`;
	}

	/** @returns {ThemeMode} */
	function themePreference() {
		return safeTheme(
			document.documentElement.getAttribute("data-theme") || "system",
		);
	}

	/** @param {ThemeMode | string | null | undefined} theme */
	function applyTheme(theme) {
		const selected = safeTheme(theme);
		const dark = resolvedThemeIsDark(selected);
		const nextTheme =
			themeOptions[(themeOptions.indexOf(selected) + 1) % themeOptions.length];
		const switcher = optionalElement("theme-switcher");

		document.documentElement.setAttribute("data-theme", selected);
		document.documentElement.classList.toggle("dark", dark);
		document.documentElement.style.colorScheme = dark ? "dark" : "light";
		if (switcher instanceof HTMLButtonElement) {
			ensureThemeSwitcherIcons(switcher);
			switcher.dataset.themeChoice = selected;
			switcher.setAttribute(
				"aria-label",
				`Theme: ${selected}. Switch to ${nextTheme} theme.`,
			);
			switcher.title = `Theme: ${selected}. Switch to ${nextTheme} theme.`;
		}
	}

	/**
	 * @param {ThemeMode} theme
	 * @returns {boolean}
	 */
	function resolvedThemeIsDark(theme) {
		if (theme === "dark") {
			return true;
		}
		if (theme === "light") {
			return false;
		}
		return Boolean(
			window.matchMedia &&
				window.matchMedia("(prefers-color-scheme: dark)").matches,
		);
	}

	/** @param {HTMLButtonElement} switcher */
	function ensureThemeSwitcherIcons(switcher) {
		if (!switcher.querySelector("[data-theme-icon]")) {
			switcher.prepend(
				themeIconElement("system"),
				themeIconElement("light"),
				themeIconElement("dark"),
			);
		}
	}

	/**
	 * @param {ThemeMode} theme
	 * @returns {SVGSVGElement}
	 */
	function themeIconElement(theme) {
		const svg = /** @type {SVGSVGElement} */ (
			svgElement("svg", {
				"data-theme-icon": theme,
				"aria-hidden": "true",
				viewBox: "0 0 24 24",
			})
		);
		for (const spec of themeIconShapeSpecs(theme)) {
			const { tag, attrs } = spec;
			svg.append(svgElement(tag, attrs));
		}
		return svg;
	}

	/**
	 * @param {ThemeMode} theme
	 * @returns {{tag: "circle" | "path" | "rect", attrs: Record<string, string>}[]}
	 */
	function themeIconShapeSpecs(theme) {
		if (theme === "system") {
			return [
				{
					tag: "rect",
					attrs: { x: "3", y: "4", width: "18", height: "12", rx: "2" },
				},
				{ tag: "path", attrs: { d: "M8 20h8" } },
				{ tag: "path", attrs: { d: "M12 16v4" } },
			];
		}
		if (theme === "light") {
			return [
				{ tag: "circle", attrs: { cx: "12", cy: "12", r: "4" } },
				{ tag: "path", attrs: { d: "M12 2v2" } },
				{ tag: "path", attrs: { d: "M12 20v2" } },
				{ tag: "path", attrs: { d: "m4.93 4.93 1.41 1.41" } },
				{ tag: "path", attrs: { d: "m17.66 17.66 1.41 1.41" } },
				{ tag: "path", attrs: { d: "M2 12h2" } },
				{ tag: "path", attrs: { d: "M20 12h2" } },
				{ tag: "path", attrs: { d: "m6.34 17.66-1.41 1.41" } },
				{ tag: "path", attrs: { d: "m19.07 4.93-1.41 1.41" } },
			];
		}
		return [
			{
				tag: "path",
				attrs: { d: "M20 14.5A8 8 0 0 1 9.5 4 8.5 8.5 0 1 0 20 14.5z" },
			},
		];
	}

	/**
	 * @param {"circle" | "path" | "rect" | "svg"} tag
	 * @param {Record<string, string>} attrs
	 * @returns {SVGElement}
	 */
	function svgElement(tag, attrs) {
		const element = document.createElementNS("http://www.w3.org/2000/svg", tag);
		for (const [name, value] of Object.entries(attrs)) {
			element.setAttribute(name, value);
		}
		return element;
	}

	/** @returns {void} */
	function toggleTheme() {
		const currentTheme = themePreference();
		const nextTheme =
			themeOptions[
				(themeOptions.indexOf(currentTheme) + 1) % themeOptions.length
			];
		writeThemeCookie(nextTheme);
		applyTheme(nextTheme);
	}

	/** @returns {void} */
	function initializeTheme() {
		applyTheme(readThemeCookie());
		const media = window.matchMedia
			? window.matchMedia("(prefers-color-scheme: dark)")
			: null;
		if (
			!themeMediaBound &&
			media &&
			typeof media.addEventListener === "function"
		) {
			themeMediaBound = true;
			media.addEventListener("change", () => {
				if (themePreference() === "system") {
					applyTheme("system");
				}
			});
		}
	}

	/** @returns {void} */
	function bindThemeSwitcher() {
		const switcher = optionalElement("theme-switcher");
		if (
			switcher instanceof HTMLButtonElement &&
			switcher.dataset.themeBound !== "true"
		) {
			switcher.dataset.themeBound = "true";
			switcher.addEventListener("click", toggleTheme);
		}
	}

	/** @returns {void} */
	function initializeAuthStateRegion() {
		const authState = optionalElement("auth-state");
		if (!authState) {
			return;
		}
		authState.setAttribute("role", "status");
		authState.setAttribute("aria-live", "polite");
		authState.setAttribute("aria-atomic", "true");
	}

	/** @returns {void} */
	function initializeThemeSwitcher() {
		initializeTheme();
		enhanceVendoredClasses();
		bindThemeSwitcher();
		initializeAuthStateRegion();
	}

	function enhanceVendoredClasses() {
		addClasses(document.body, "bg-background", "text-foreground", "antialiased");
		document
			.querySelectorAll("body > header")
			.forEach((element) =>
				addClasses(
					element,
					"mx-auto",
					"flex",
					"max-w-6xl",
					"items-start",
					"justify-between",
					"gap-4",
					"px-6",
					"py-8",
				),
			);
		document
			.querySelectorAll("body > main")
			.forEach((element) =>
				addClasses(element, "mx-auto", "grid", "max-w-6xl", "gap-4", "px-6", "pb-10"),
			);
		document.querySelectorAll(".app-panel").forEach((element) => {
			addClasses(element, "card", "p-6");
		});
		document
			.querySelectorAll("form, .runner, .settings-form, #lookup-form, #provider-form, #auth-panel")
			.forEach((element) => addClasses(element, "grid", "gap-4"));
		document.querySelectorAll(".form-row, #identity-form").forEach((element) => {
			addClasses(element, "grid", "gap-3", "md:grid-cols-3", "items-end");
		});
		document.querySelectorAll(".field").forEach((element) => {
			addClasses(element, "field");
		});
		document
			.querySelectorAll(
				".examples, .samples, .comment-actions, .panel-actions, .composer-actions, .header-actions",
			)
			.forEach((element) =>
				addClasses(element, "flex", "flex-wrap", "items-center", "gap-2"),
			);
		document
			.querySelectorAll("#results-content, #comments, .connector-list, .messages")
			.forEach((element) => addClasses(element, "grid", "gap-3"));
		document
			.querySelectorAll(".metrics, .grid, .columns, .result-head, .workspace, .app-workspace")
			.forEach((element) => addClasses(element, "grid", "gap-4"));
		document.querySelectorAll("input").forEach((element) => {
			addClasses(element, "input", "w-full");
		});
		document.querySelectorAll("textarea").forEach((element) => {
			addClasses(element, "textarea", "w-full", "min-h-24");
		});
		document.querySelectorAll("select").forEach((element) => {
			addClasses(element, "select", "w-full");
		});
		document.querySelectorAll("label").forEach((element) => {
			addClasses(element, "label");
		});
		document.querySelectorAll("button").forEach((button) => {
			if (button.classList.contains("theme-toggle")) {
				addClasses(button, "btn-icon-outline");
				return;
			}
			if (button.classList.contains("sign-in-link")) {
				addClasses(button, "btn");
				return;
			}
			if (button.hasAttribute("data-example") || button.hasAttribute("data-sample")) {
				addClasses(button, "btn-secondary");
				return;
			}
			addClasses(button, "btn");
		});
		document.querySelectorAll("a.sign-in-link").forEach((element) => {
			addClasses(element, "btn");
		});
	}

	/**
	 * @param {Element} element
	 * @param {...string} classes
	 * @returns {void}
	 */
	function addClasses(element, ...classes) {
		element.classList.add(...classes.filter(Boolean));
	}

	/**
	 * @param {number=} delayMillis
	 * @returns {void}
	 */
	function initializeSignedOutRedirect(delayMillis) {
		initializeThemeSwitcher();
		const loginLink = optionalElement("login-link");
		if (!(loginLink instanceof HTMLAnchorElement)) {
			return;
		}
		window.setTimeout(() => {
			window.location.assign(loginLink.href);
		}, delayMillis ?? 5000);
	}

	/**
	 * @param {string} id
	 * @returns {HTMLElement | null}
	 */
	function optionalElement(id) {
		return document.getElementById(id);
	}

	/**
	 * @param {string} id
	 * @returns {HTMLElement}
	 */
	function requireElement(id) {
		const element = optionalElement(id);
		if (!element) {
			throw new Error(`Missing required element #${id}`);
		}
		return element;
	}

	/**
	 * @param {string} selector
	 * @param {ParentNode=} root
	 * @returns {Element}
	 */
	function requireSelector(selector, root) {
		const element = (root || document).querySelector(selector);
		if (!element) {
			throw new Error(`Missing required selector ${selector}`);
		}
		return element;
	}

	/**
	 * @param {string} selector
	 * @param {ParentNode=} root
	 * @returns {Element[]}
	 */
	function requireSelectorAll(selector, root) {
		const elements = Array.from((root || document).querySelectorAll(selector));
		if (elements.length === 0) {
			throw new Error(`Missing required selector ${selector}`);
		}
		return elements;
	}

	/**
	 * @param {string} id
	 * @returns {HTMLButtonElement}
	 */
	function buttonElement(id) {
		const element = requireElement(id);
		if (!(element instanceof HTMLButtonElement)) {
			throw new Error(`Required element #${id} is not a button`);
		}
		return element;
	}

	/**
	 * @param {string} selector
	 * @param {ParentNode=} root
	 * @returns {HTMLButtonElement}
	 */
	function buttonSelector(selector, root) {
		const element = requireSelector(selector, root);
		if (!(element instanceof HTMLButtonElement)) {
			throw new Error(`Required selector ${selector} is not a button`);
		}
		return element;
	}

	/**
	 * @param {string} id
	 * @returns {HTMLFormElement}
	 */
	function formElement(id) {
		const element = requireElement(id);
		if (!(element instanceof HTMLFormElement)) {
			throw new Error(`Required element #${id} is not a form`);
		}
		return element;
	}

	/**
	 * @param {string} id
	 * @returns {HTMLInputElement}
	 */
	function inputElement(id) {
		const element = requireElement(id);
		if (!(element instanceof HTMLInputElement)) {
			throw new Error(`Required element #${id} is not an input`);
		}
		return element;
	}

	/**
	 * @param {string} id
	 * @returns {HTMLSelectElement}
	 */
	function selectElement(id) {
		const element = requireElement(id);
		if (!(element instanceof HTMLSelectElement)) {
			throw new Error(`Required element #${id} is not a select`);
		}
		return element;
	}

	/**
	 * @param {string} id
	 * @returns {HTMLTextAreaElement}
	 */
	function textAreaElement(id) {
		const element = requireElement(id);
		if (!(element instanceof HTMLTextAreaElement)) {
			throw new Error(`Required element #${id} is not a textarea`);
		}
		return element;
	}

	/**
	 * @param {JSONValue | object | undefined} value
	 * @returns {value is NetworkHop}
	 */
	function isNetworkHop(value) {
		return (
			typeof value === "object" &&
			value !== null &&
			typeof (/** @type {NetworkHopCandidate} */ (value).label) === "string" &&
			typeof (/** @type {NetworkHopCandidate} */ (value).detail) === "string"
		);
	}

	/**
	 * @param {RuntimeConfigBase | null | undefined} config
	 * @param {NetworkHop[]} fallback
	 * @returns {NetworkHop[]}
	 */
	function resolveNetworkHops(config, fallback) {
		const configured = config?.networkHops;
		return Array.isArray(configured) && configured.every(isNetworkHop)
			? configured
			: fallback;
	}

	/**
	 * @param {NetworkHop[]} hops
	 * @returns {string}
	 */
	function renderNetworkPath(hops) {
		const template = document.createElement("template");
		template.content.append(networkPathElement(hops));
		return template.innerHTML;
	}

	/**
	 * @param {NetworkHop[]} hops
	 * @returns {HTMLDetailsElement}
	 */
	function networkPathElement(hops) {
		const details = document.createElement("details");
		const summary = document.createElement("summary");
		summary.textContent = `Network Path (${hops.length} hops)`;
		const path = document.createElement("div");
		path.className = "network-path";

		hops.forEach((hop, index) => {
			if (index > 0) {
				const arrow = document.createElement("div");
				arrow.className = "hop-arrow";
				arrow.textContent = `↓${String(hop.detail).includes("mTLS") ? " mTLS" : ""}`;
				path.append(arrow);
			}

			const hopElement = document.createElement("div");
			hopElement.className = "hop card";
			const label = document.createElement("strong");
			label.textContent = hop.label;
			const detail = document.createElement("small");
			detail.textContent = hop.detail;
			hopElement.append(label, document.createElement("br"), detail);
			if (hop.role) {
				const role = document.createElement("em");
				role.textContent = String(hop.role);
				hopElement.append(document.createElement("br"), role);
			}
			path.append(hopElement);
		});

		details.append(summary, path);
		return details;
	}

	/**
	 * @param {Element} container
	 * @param {NetworkHop[]} hops
	 * @param {boolean=} enabled
	 * @returns {void}
	 */
	function renderNetworkPathInto(container, hops, enabled) {
		if (enabled === false) {
			container.replaceChildren();
			return;
		}
		container.replaceChildren(networkPathElement(hops));
	}

	/**
	 * @param {Array<[string, string | number | boolean | null | undefined]>} rows
	 * @returns {string}
	 */
	function renderKeyValueTable(rows) {
		return `<table class="table"><tbody>${rows.map(([key, value]) => `<tr><th scope="row">${escapeHTML(key)}</th><td>${escapeHTML(String(value ?? ""))}</td></tr>`).join("")}</tbody></table>`;
	}

	/**
	 * @param {Array<[string, string | number | boolean | null | undefined]>} rows
	 * @returns {HTMLTableElement}
	 */
	function keyValueTableElement(rows) {
		const table = document.createElement("table");
		table.className = "table";
		const tbody = document.createElement("tbody");
		for (const [key, value] of rows) {
			const tr = document.createElement("tr");
			const th = document.createElement("th");
			const td = document.createElement("td");
			th.scope = "row";
			th.textContent = key;
			td.textContent = String(value ?? "");
			tr.append(th, td);
			tbody.append(tr);
		}
		table.append(tbody);
		return table;
	}

	/**
	 * @param {Element} container
	 * @param {Array<[string, string | number | boolean | null | undefined]>} rows
	 * @returns {void}
	 */
	function renderKeyValueTableInto(container, rows) {
		container.replaceChildren(keyValueTableElement(rows));
	}

	/**
	 * @param {AppShellTextValue} title
	 * @param {Array<[string, string | number | boolean | null | undefined]>} rows
	 * @param {...Element} children
	 * @returns {HTMLElement}
	 */
	function keyValueArticleElement(title, rows, ...children) {
		const article = document.createElement("article");
		article.className = "card";
		const heading = document.createElement("h3");
		heading.className = "card-title";
		heading.textContent = title == null ? "" : String(title);
		article.append(heading, keyValueTableElement(rows), ...children);
		return article;
	}

	/**
	 * @param {APITiming} timing
	 * @param {APITimingRenderOptions=} options
	 * @returns {Array<[string, string | number | boolean | null | undefined]>}
	 */
	function apiTimingRows(timing, options = {}) {
		/** @type {Array<[string, string | number | boolean | null | undefined]>} */
		const rows = [];
		if (options.action) rows.push(["Action", options.action]);
		if (options.apiURL || timing.url)
			rows.push(["API URL", options.apiURL || timing.url]);
		if (options.backendURL) rows.push(["Backend URL", options.backendURL]);
		rows.push(
			["Duration", `${timing.durationMs}ms`],
			["Request (UTC)", timing.requestUtc],
			["Response (UTC)", timing.responseUtc],
		);
		if (timing.correlationId)
			rows.push(["Correlation ID", timing.correlationId]);
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
		return rows;
	}

	/**
	 * @param {APITiming} timing
	 * @param {APITimingRenderOptions=} options
	 * @returns {string}
	 */
	function renderAPITiming(timing, options = {}) {
		const rows = apiTimingRows(timing, options);
		const open = options.open ? " open" : "";
		return `<details${open}><summary>${escapeHTML(options.summary || "API Call Timing")}</summary>${renderKeyValueTable(rows)}</details>`;
	}

	/**
	 * @param {APITiming} timing
	 * @param {APITimingRenderOptions=} options
	 * @returns {HTMLDetailsElement}
	 */
	function apiTimingElement(timing, options = {}) {
		const rows = apiTimingRows(timing, options);
		const details = document.createElement("details");
		details.open = Boolean(options.open);
		const summary = document.createElement("summary");
		summary.textContent = options.summary || "API Call Timing";
		details.append(summary, keyValueTableElement(rows));
		return details;
	}

	/**
	 * @param {RuntimeConfigBase | null | undefined} config
	 * @returns {boolean}
	 */
	function shouldShowNetworkPath(config) {
		return config?.showNetworkPath !== false;
	}

	/**
	 * @param {RuntimeConfigBase | null | undefined} config
	 * @returns {Record<string, string>}
	 */
	function apiTraceHeaders(config) {
		return shouldShowNetworkPath(config) ? { "x-apim-trace": "true" } : {};
	}

	/**
	 * @param {RuntimeConfigBase | null | undefined} config
	 * @param {Record<string, string>=} extraHeaders
	 * @returns {Record<string, string>}
	 */
	function apiJSONHeaders(config, extraHeaders) {
		return {
			"Content-Type": "application/json",
			...apiTraceHeaders(config),
			...(extraHeaders || {}),
		};
	}

	/**
	 * @param {RuntimeConfigBase | null | undefined} config
	 * @param {string=} fallback
	 * @returns {string}
	 */
	function apiBasePath(config, fallback) {
		const base = config?.apiBasePath || fallback || "/api/v1";
		return `/${String(base).replace(/^\/+|\/+$/g, "")}`;
	}

	/**
	 * @param {RuntimeConfigBase | null | undefined} config
	 * @param {string} path
	 * @param {string=} fallbackBasePath
	 * @returns {string}
	 */
	function apiPath(config, path, fallbackBasePath) {
		return `${apiBasePath(config, fallbackBasePath)}${path.startsWith("/") ? path : `/${path}`}`;
	}

	/**
	 * @param {APIHealthStatus} health
	 * @param {RuntimeConfigBase | null | undefined=} config
	 * @returns {string}
	 */
	function formatAPIHealthStatus(health, config) {
		const authState = health.server_side_token_validation
			? "OIDC/JWT validated by backend"
			: "No auth mode";
		const backendRoute = config?.backendURL || "same process";
		return `API Status: ${health.status} | Backend: ${health.service} | Backend URI: ${backendRoute} | Version: ${health.version} | Auth: ${authState}`;
	}

	/**
	 * @param {AppShellTextValue} value
	 * @returns {string}
	 */
	function formatTimestamp(value) {
		const date = new Date(value == null ? "" : String(value));
		if (Number.isNaN(date.getTime())) {
			return value ? String(value) : "Timestamp unavailable";
		}
		return date.toLocaleString(undefined, {
			year: "numeric",
			month: "short",
			day: "2-digit",
			hour: "2-digit",
			minute: "2-digit",
			second: "2-digit",
			timeZoneName: "short",
		});
	}

	/**
	 * @param {string} value
	 * @returns {APIMTrace | null}
	 */
	function decodeAPIMTrace(value) {
		if (!value) {
			return null;
		}
		try {
			const parsed = JSON.parse(atob(value));
			if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
				return null;
			}
			const trace = /** @type {APIMTraceCandidate} */ (parsed);
			return {
				route: typeof trace.route === "string" ? trace.route : undefined,
				upstream_url:
					typeof trace.upstream_url === "string"
						? trace.upstream_url
						: undefined,
				elapsed_ms:
					typeof trace.elapsed_ms === "number" ? trace.elapsed_ms : undefined,
				status: typeof trace.status === "number" ? trace.status : undefined,
			};
		} catch {
			return null;
		}
	}

	/**
	 * @param {AppShellTextValue} value
	 * @returns {string}
	 */
	function escapeHTML(value) {
		return String(value).replace(
			/[&<>"']/g,
			(char) =>
				/** @type {Record<string, string>} */ ({
					"&": "&amp;",
					"<": "&lt;",
					">": "&gt;",
					'"': "&quot;",
					"'": "&#39;",
				})[char],
		);
	}

	/**
	 * @param {AppShellTextValue} value
	 * @returns {string}
	 */
	function escapeAttr(value) {
		return escapeHTML(value).replace(/`/g, "&#96;");
	}

	/**
	 * @param {JSONValue | object | null | undefined} value
	 * @returns {value is JSONObject}
	 */
	function isJSONObject(value) {
		return typeof value === "object" && value !== null && !Array.isArray(value);
	}

	/**
	 * @param {string | null | undefined} text
	 * @param {JSONObject=} fallback
	 * @returns {JSONObject}
	 */
	function parseJSONObjectText(text, fallback = {}) {
		if (!text) {
			return fallback;
		}
		try {
			const parsed = /** @type {JSONValue} */ (JSON.parse(text));
			return isJSONObject(parsed) ? parsed : fallback;
		} catch {
			return fallback;
		}
	}

	/**
	 * @param {string} name
	 * @returns {JSONObject}
	 */
	function readRuntimeConfig(name) {
		const runtimeWindow =
			/** @type {Window & Record<string, JSONValue | object | undefined>} */ (
				Object(window)
			);
		const value = runtimeWindow[name];
		return isJSONObject(value) ? value : {};
	}

	/**
	 * @template T
	 * @param {Response} response
	 * @returns {Promise<T>}
	 */
	async function parseJSONResponse(response) {
		const data = /** @type {JSONValue} */ (
			await response.json().catch(() => ({}))
		);
		if (!response.ok) {
			const errorPayload = isJSONObject(data) ? data : {};
			const error =
				/** @type {Error & {status?: number, payload?: JSONValue}} */ (
					new Error(
						typeof errorPayload.detail === "string"
							? errorPayload.detail
							: typeof errorPayload.error === "string"
								? errorPayload.error
								: `HTTP ${response.status}`,
					)
				);
			error.status = response.status;
			error.payload = data;
			throw error;
		}
		return /** @type {T} */ (data);
	}

	/**
	 * @template T
	 * @param {RequestInfo | URL} input
	 * @param {RequestInit=} init
	 * @returns {Promise<T>}
	 */
	async function fetchJSON(input, init) {
		return parseJSONResponse(await fetch(input, init));
	}

	/**
	 * @param {RequestInfo | URL} input
	 * @param {RequestInit=} init
	 * @returns {Promise<string>}
	 */
	async function fetchText(input, init) {
		const response = await fetch(input, init);
		const text = await response.text();
		if (!response.ok) {
			throw new Error(text || `HTTP ${response.status}`);
		}
		return text;
	}

	/**
	 * @template T
	 * @param {RequestInfo | URL} input
	 * @param {JSONValue | object} body
	 * @param {RequestInit=} init
	 * @returns {Promise<T>}
	 */
	async function postJSON(input, body, init) {
		const headers = new Headers(init?.headers || {});
		headers.set("Content-Type", "application/json");
		return fetchJSON(input, {
			...init,
			method: init?.method || "POST",
			headers,
			body: JSON.stringify(body),
		});
	}

	/**
	 * @template T
	 * @param {RequestInfo | URL} input
	 * @param {RequestInit=} init
	 * @param {(value: string) => APIMTrace | null=} decodeAPIMTrace
	 * @returns {Promise<{data: T, timing: {url: string, durationMs: number, requestUtc: string, responseUtc: string, traceId: string, correlationId: string, apimTrace: APIMTrace | null}}>}
	 */
	async function fetchJSONWithTiming(input, init, decodeAPIMTrace) {
		const started = performance.now();
		const requestUtc = new Date().toISOString();
		const response = await fetch(input, init);
		const data = /** @type {T} */ (await parseJSONResponse(response));
		return {
			data,
			timing: {
				url: String(input),
				...buildAPITiming(started, requestUtc, response, decodeAPIMTrace),
			},
		};
	}

	/**
	 * @param {number} started
	 * @param {string} requestUtc
	 * @param {Response} response
	 * @param {(value: string) => APIMTrace | null=} decodeAPIMTrace
	 * @returns {{durationMs: number, requestUtc: string, responseUtc: string, traceId: string, correlationId: string, apimTrace: APIMTrace | null}}
	 */
	function buildAPITiming(started, requestUtc, response, decodeAPIMTrace) {
		return {
			durationMs: Math.round(performance.now() - started),
			requestUtc,
			responseUtc: new Date().toISOString(),
			traceId: response.headers.get("x-apim-trace-id") || "",
			correlationId: response.headers.get("x-correlation-id") || "",
			apimTrace: decodeAPIMTrace
				? decodeAPIMTrace(response.headers.get("x-apim-trace") || "")
				: null,
		};
	}

	/**
	 * @param {AppShellErrorInput} error
	 * @returns {string}
	 */
	function errorMessage(error) {
		if (error instanceof Error) {
			return error.message;
		}
		if (
			typeof error === "object" &&
			error !== null &&
			typeof error.message !== "undefined"
		) {
			return String(error.message);
		}
		return String(error);
	}

	/**
	 * @param {AppShellJSONValue} value
	 * @returns {string}
	 */
	function prettyJSON(value) {
		return JSON.stringify(value, null, 2);
	}

	/**
	 * @param {Element} node
	 * @param {AppShellJSONValue} value
	 * @returns {void}
	 */
	function renderJSONInto(node, value) {
		node.textContent = prettyJSON(value);
	}

	/**
	 * @param {Element} node
	 * @param {AppShellTextValue} value
	 * @returns {void}
	 */
	function setText(node, value) {
		node.textContent = value == null ? "" : String(value);
	}

	/**
	 * @param {AppShellTextValue} value
	 * @param {AppShellTextValue} fallback
	 * @returns {string}
	 */
	function textDefault(value, fallback) {
		const text =
			value === null || value === undefined || value === "" ? fallback : value;
		return text == null ? "" : String(text);
	}

	/**
	 * @param {Element} node
	 * @param {AppShellTextValue} value
	 * @param {AppShellTextValue} fallback
	 * @returns {void}
	 */
	function setTextDefault(node, value, fallback) {
		setText(node, textDefault(value, fallback));
	}

	/**
	 * @param {Element} node
	 * @param {AppShellTextValue} value
	 * @param {AppShellStatusTone | boolean=} tone
	 * @returns {void}
	 */
	function renderStatusInto(node, value, tone) {
		ensureStatusRegion(node);
		setText(node, value);
		const normalizedTone = normalizeStatusTone(tone);
		node.classList.toggle("success", normalizedTone === "success");
		node.classList.toggle("warning", normalizedTone === "warning");
		node.classList.toggle("error", normalizedTone === "error");
	}

	/**
	 * @param {Element} node
	 * @returns {void}
	 */
	function ensureStatusRegion(node) {
		node.setAttribute("role", "status");
		node.setAttribute("aria-live", "polite");
		node.setAttribute("aria-atomic", "true");
	}

	/**
	 * @param {AppShellStatusTone | boolean | null | undefined} tone
	 * @returns {AppShellStatusTone}
	 */
	function normalizeStatusTone(tone) {
		return tone === true ? "error" : tone || "";
	}

	/**
	 * @param {Element} node
	 * @param {AppShellTextValue} value
	 * @param {string=} className
	 * @returns {void}
	 */
	function renderMessageInto(node, value, className) {
		const paragraph = document.createElement("p");
		if (className) {
			paragraph.className = className;
		}
		paragraph.textContent = value == null ? "" : String(value);
		node.replaceChildren(paragraph);
	}

	/**
	 * @template T
	 * @param {HTMLSelectElement} select
	 * @param {T[]} items
	 * @param {(item: T) => {value: AppShellTextValue, label: AppShellTextValue}} optionFor
	 * @returns {void}
	 */
	function renderOptionsInto(select, items, optionFor) {
		const options = items.map((item) => {
			const { value, label } = optionFor(item);
			const option = document.createElement("option");
			option.value = value == null ? "" : String(value);
			option.textContent = label == null ? "" : String(label);
			return option;
		});
		select.replaceChildren(...options);
	}

	/**
	 * @template T
	 * @param {Element} node
	 * @param {T[]} items
	 * @param {(item: T) => Element} elementFor
	 * @param {Element=} emptyElement
	 * @returns {void}
	 */
	function renderElementsInto(node, items, elementFor, emptyElement) {
		const elements = items.map(elementFor);
		node.replaceChildren(
			...(elements.length > 0 ? elements : emptyElement ? [emptyElement] : []),
		);
	}

	/**
	 * @template T
	 * @param {Element} node
	 * @param {T[]} items
	 * @param {(item: T) => {title: AppShellTextValue, detail: AppShellTextValue}} rowFor
	 * @returns {void}
	 */
	function renderSummaryListInto(node, items, rowFor) {
		const rows = items.map((item) => {
			const { title, detail } = rowFor(item);
			const li = document.createElement("li");
			const strong = document.createElement("strong");
			const span = document.createElement("span");
			strong.textContent = title == null ? "" : String(title);
			span.textContent = detail == null ? "" : String(detail);
			li.append(strong, span);
			return li;
		});
		node.replaceChildren(...rows);
	}

	/**
	 * @template T
	 * @param {Element} node
	 * @param {T[]} items
	 * @param {(item: T) => string} format
	 * @returns {void}
	 */
	function renderListInto(node, items, format) {
		node.textContent = "";
		for (const item of items) {
			const li = document.createElement("li");
			li.textContent = format(item);
			node.append(li);
		}
	}

	/**
	 * @template T
	 * @param {HTMLButtonElement} button
	 * @param {string} busyLabel
	 * @param {() => Promise<T>} action
	 * @returns {Promise<T>}
	 */
	async function withButtonBusy(button, busyLabel, action) {
		const previousLabel = button.textContent || "";
		const previousDisabled = button.disabled;
		button.disabled = true;
		button.setAttribute("aria-busy", "true");
		button.textContent = busyLabel;
		try {
			return await action();
		} finally {
			button.disabled = previousDisabled;
			button.removeAttribute("aria-busy");
			button.textContent = previousLabel;
		}
	}

	/**
	 * @template T
	 * @param {SubmitEvent} event
	 * @param {string} busyLabel
	 * @param {() => Promise<T>} action
	 * @returns {Promise<T>}
	 */
	async function withSubmitterBusy(event, busyLabel, action) {
		const submitter = event.submitter;
		if (submitter instanceof HTMLButtonElement) {
			return withButtonBusy(submitter, busyLabel, action);
		}
		return action();
	}

	const platformWindow =
		/** @type {Window & {PlatformAppShell?: PlatformAppShell}} */ (window);
	platformWindow.PlatformAppShell = Object.freeze({
		applyTheme,
		apiBasePath,
		apiJSONHeaders,
		apiPath,
		apiTraceHeaders,
		bindThemeSwitcher,
		buildAPITiming,
		buttonElement,
		buttonSelector,
		decodeAPIMTrace,
		errorMessage,
		escapeAttr,
		escapeHTML,
		fetchJSON,
		fetchJSONWithTiming,
		fetchText,
		formatAPIHealthStatus,
		formatTimestamp,
		formElement,
		ensureThemeSwitcherIcons,
		initializeAuthStateRegion,
		initializeSignedOutRedirect,
		initializeTheme,
		initializeThemeSwitcher,
		inputElement,
		apiTimingElement,
		keyValueArticleElement,
		keyValueTableElement,
		parseJSONResponse,
		parseJSONObjectText,
		postJSON,
		prettyJSON,
		optionalElement,
		readRuntimeConfig,
		readThemeCookie,
		renderAPITiming,
		renderElementsInto,
		renderKeyValueTable,
		renderKeyValueTableInto,
		renderJSONInto,
		renderNetworkPath,
		renderNetworkPathInto,
		requireElement,
		requireSelector,
		requireSelectorAll,
		renderListInto,
		renderMessageInto,
		networkPathElement,
		renderOptionsInto,
		renderSummaryListInto,
		renderStatusInto,
		resolveNetworkHops,
		selectElement,
		setText,
		setTextDefault,
		shouldShowNetworkPath,
		textAreaElement,
		textDefault,
		themePreference,
		toggleTheme,
		withButtonBusy,
		withSubmitterBusy,
		writeThemeCookie,
	});
})();
