export type ThemeMode = "light" | "dark" | "system";

export type AuthMethod = "none" | "oidc" | "gateway";

export interface LoggedInUser {
	subject: string;
	username?: string;
	email?: string;
	displayName?: string;
	groups?: string[];
}

export interface NetworkHop {
	label: string;
	detail: string;
	role?: string;
	url?: string;
}

export interface APIMTrace {
	route?: string;
	upstream_url?: string;
	elapsed_ms?: number;
	status?: number;
}

export type JSONPrimitive = string | number | boolean | null;
export type JSONValue = JSONPrimitive | JSONObject | JSONValue[];

export interface JSONObject {
	[key: string]: JSONValue | undefined;
}

export type KeyValueTableRow = [
	string,
	string | number | boolean | null | undefined,
];

export type AppShellTextValue = string | number | boolean | null | undefined;

export type AppShellJSONValue = JSONValue | object | undefined;

export type AppShellErrorInput =
	| Error
	| AppShellTextValue
	| { message?: AppShellTextValue };

export type AppShellStatusTone = "success" | "warning" | "error" | "";

export interface APITiming {
	url?: string;
	durationMs: number;
	requestUtc: string;
	responseUtc: string;
	traceId: string;
	correlationId: string;
	apimTrace?: APIMTrace | null;
}

export interface APITimingRenderOptions {
	action?: string;
	apiURL?: string;
	backendURL?: string;
	open?: boolean;
	summary?: string;
}

export interface APIHealthStatus {
	status: string;
	service: string;
	version: string;
	server_side_token_validation?: boolean;
}

export interface RuntimeConfigBase {
	appName?: string;
	environment?: string;
	authMethod?: AuthMethod;
	apiAuthMethod?: AuthMethod;
	apiBasePath?: string;
	backendURL?: string;
	gatewayURL?: string;
	showNetworkPath?: boolean;
	networkHops?: NetworkHop[];
	user?: LoggedInUser;
	theme?: ThemeMode;
}

export interface OIDCRuntimeConfig extends RuntimeConfigBase {
	oidcAuthority?: string;
	oidcClientId?: string;
	oidcRedirect?: string;
}

export interface OIDCProviderMetadata extends JSONObject {
	issuer?: string;
	authorization_endpoint?: string;
	token_endpoint: string;
	end_session_endpoint?: string;
}

export interface GatewayClaim {
	typ?: string;
	type?: string;
	val?: string;
	value?: string;
}

export interface GatewaySession {
	claims?: GatewayClaim[];
	userDetails?: string;
	user_details?: string;
	email?: string;
	preferred_username?: string;
	name?: string;
	user_id?: string;
	userId?: string;
	[key: string]: JSONValue | GatewayClaim[] | undefined;
}

export interface GatewayLogoutOptions {
	signOutURL?: string;
	signOutPath?: string;
	returnParameter?: string;
}

export interface GatewayAuthStateOptions {
	path?: string;
	ignoreErrors?: boolean;
	errorMessage?: string | ((error: Error) => string);
}

export interface APIErrorMessageOptions {
	defaultPrefix?: string;
	prefix?: string;
	errorMessage?: (error: AppShellErrorInput) => string;
}

export interface PlatformIdpAuthConfig extends GatewayLogoutOptions {
	gatewaySignOutURL?: string;
	gatewaySignOutPath?: string;
	gatewayLogoutURL?: string;
	gatewayLogoutPath?: string;
	gatewayLogoutReturnParameter?: string;
	logoutReturnParameter?: string;
}

export interface PlatformIdpAuth {
	normalizeGatewaySession(payload: JSONValue): GatewaySession | null;
	gatewayDisplayName(session: GatewaySession): string;
	fetchGatewaySession(path?: string): Promise<GatewaySession | null>;
	gatewayLogoutURL(returnPath?: string, options?: GatewayLogoutOptions): string;
	bindGatewayLogout(
		button: HTMLButtonElement | null | undefined,
		returnPath?: string,
	): void;
	writeGatewayAuthState(
		authState: Element | null | undefined,
		logoutButton: HTMLButtonElement | null | undefined,
		session: GatewaySession | null | undefined,
		message?: string,
	): void;
	initializeGatewayAuthState(
		authState: Element | null | undefined,
		logoutButton: HTMLButtonElement | null | undefined,
		options?: GatewayAuthStateOptions,
	): Promise<GatewaySession | null>;
	oidcDiscoveryURL(config?: OIDCRuntimeConfig | null): string;
	fetchOIDCProviderMetadata(
		config?: OIDCRuntimeConfig | null,
	): Promise<OIDCProviderMetadata>;
	usesGatewayAuth(config?: RuntimeConfigBase | null): boolean;
	apiRequiresOIDCToken(config?: RuntimeConfigBase | null): boolean;
	apiActionReady(
		config?: RuntimeConfigBase | null,
		bearerToken?: string,
	): boolean;
	apiAuthRequiredMessage(action: string, clientName?: string): string;
	expiredSessionMessage(): string;
	gatewaySessionExpired(
		config: RuntimeConfigBase | null | undefined,
		error: AppShellErrorInput,
	): boolean;
	apiErrorMessage(
		config: RuntimeConfigBase | null | undefined,
		error: AppShellErrorInput,
		options?: APIErrorMessageOptions,
	): string;
}

export interface PlatformAppShell {
	initializeThemeSwitcher(): void;
	initializeTheme(): void;
	bindThemeSwitcher(button: HTMLButtonElement | null | undefined): void;
	toggleTheme(): void;
	applyTheme(theme: ThemeMode): void;
	readThemeCookie(): ThemeMode | "";
	writeThemeCookie(theme: ThemeMode): void;
	themePreference(): ThemeMode;
	ensureThemeSwitcherIcons(switcher: HTMLButtonElement): void;
	initializeSignedOutRedirect(delayMs?: number): void;
	initializeAuthStateRegion(): void;
	optionalElement(id: string): HTMLElement | null;
	requireElement(id: string): HTMLElement;
	requireSelector(selector: string, root?: ParentNode): Element;
	requireSelectorAll(selector: string, root?: ParentNode): Element[];
	buttonElement(id: string): HTMLButtonElement;
	buttonSelector(selector: string, root?: ParentNode): HTMLButtonElement;
	formElement(id: string): HTMLFormElement;
	inputElement(id: string): HTMLInputElement;
	selectElement(id: string): HTMLSelectElement;
	textAreaElement(id: string): HTMLTextAreaElement;
	resolveNetworkHops(
		config: RuntimeConfigBase | null | undefined,
		fallback: NetworkHop[],
	): NetworkHop[];
	renderNetworkPath(hops: NetworkHop[]): string;
	networkPathElement(hops: NetworkHop[]): HTMLDetailsElement;
	renderNetworkPathInto(
		container: Element,
		hops: NetworkHop[],
		enabled?: boolean,
	): void;
	renderKeyValueTable(rows: KeyValueTableRow[]): string;
	keyValueTableElement(rows: KeyValueTableRow[]): HTMLTableElement;
	renderKeyValueTableInto(container: Element, rows: KeyValueTableRow[]): void;
	keyValueArticleElement(
		title: AppShellTextValue,
		rows: KeyValueTableRow[],
		...children: Element[]
	): HTMLElement;
	renderAPITiming(timing: APITiming, options?: APITimingRenderOptions): string;
	apiTimingElement(
		timing: APITiming,
		options?: APITimingRenderOptions,
	): HTMLDetailsElement;
	shouldShowNetworkPath(config?: RuntimeConfigBase | null): boolean;
	apiTraceHeaders(config?: RuntimeConfigBase | null): Record<string, string>;
	apiJSONHeaders(
		config?: RuntimeConfigBase | null,
		extraHeaders?: Record<string, string>,
	): Record<string, string>;
	apiBasePath(config?: RuntimeConfigBase | null, fallback?: string): string;
	apiPath(
		config: RuntimeConfigBase | null | undefined,
		path: string,
		fallbackBasePath?: string,
	): string;
	formatAPIHealthStatus(
		health: APIHealthStatus,
		config?: RuntimeConfigBase | null,
	): string;
	formatTimestamp(value: AppShellTextValue): string;
	decodeAPIMTrace(value: string): APIMTrace | null;
	parseJSONObjectText(
		text: string | null | undefined,
		fallback?: JSONObject,
	): JSONObject;
	readRuntimeConfig(name: string): JSONObject;
	parseJSONResponse<T = JSONValue>(response: Response): Promise<T>;
	fetchJSON<T = JSONValue>(
		input: RequestInfo | URL,
		init?: RequestInit,
	): Promise<T>;
	fetchText(input: RequestInfo | URL, init?: RequestInit): Promise<string>;
	postJSON<T = JSONValue>(
		input: RequestInfo | URL,
		body: JSONValue | object,
		init?: RequestInit,
	): Promise<T>;
	fetchJSONWithTiming<T = JSONValue>(
		input: RequestInfo | URL,
		init?: RequestInit,
		decodeAPIMTrace?: (value: string) => APIMTrace | null,
	): Promise<{ data: T; timing: APITiming }>;
	buildAPITiming(
		started: number,
		requestUtc: string,
		response: Response,
		decodeAPIMTrace?: (value: string) => APIMTrace | null,
	): APITiming;
	errorMessage(error: AppShellErrorInput): string;
	prettyJSON(value: AppShellJSONValue): string;
	renderJSONInto(node: Element, value: AppShellJSONValue): void;
	setText(node: Element, value: AppShellTextValue): void;
	textDefault(value: AppShellTextValue, fallback: AppShellTextValue): string;
	setTextDefault(
		node: Element,
		value: AppShellTextValue,
		fallback: AppShellTextValue,
	): void;
	renderMessageInto(
		node: Element,
		value: AppShellTextValue,
		className?: string,
	): void;
	renderStatusInto(
		node: Element,
		value: AppShellTextValue,
		tone?: AppShellStatusTone | boolean,
	): void;
	renderOptionsInto<T>(
		select: HTMLSelectElement,
		items: T[],
		optionFor: (item: T) => {
			value: AppShellTextValue;
			label: AppShellTextValue;
		},
	): void;
	renderElementsInto<T>(
		node: Element,
		items: T[],
		elementFor: (item: T) => Element,
		emptyElement?: Element,
	): void;
	renderSummaryListInto<T>(
		node: Element,
		items: T[],
		rowFor: (item: T) => {
			title: AppShellTextValue;
			detail: AppShellTextValue;
		},
	): void;
	renderListInto<T>(
		node: Element,
		items: T[],
		format: (item: T) => string,
	): void;
	withButtonBusy<T>(
		button: HTMLButtonElement,
		busyLabel: string,
		action: () => Promise<T>,
	): Promise<T>;
	withSubmitterBusy<T>(
		event: SubmitEvent,
		busyLabel: string,
		action: () => Promise<T>,
	): Promise<T>;
	escapeHTML(value: AppShellTextValue): string;
	escapeAttr(value: AppShellTextValue): string;
}

declare global {
	interface Window {
		PlatformAppShell: PlatformAppShell;
		PlatformIdpAuthConfig?: PlatformIdpAuthConfig;
		PlatformIdpAuth: PlatformIdpAuth;
	}
}

export interface ApiDiagnostics {
	traceId?: string;
	correlationId?: string;
	requestStartedAt: string;
	responseEndedAt: string;
	durationMs: number;
	requestURL: string;
	reachedURL?: string;
	gatewayURL?: string;
	backendURL?: string;
	status: number;
	networkHops?: NetworkHop[];
	serverTiming?: string;
	apimTrace?: APIMTrace | null;
}

export interface LogoutResult {
	signedOut: boolean;
	redirectURL?: string;
}

export interface CookieClearResult {
	cleared: string[];
}
