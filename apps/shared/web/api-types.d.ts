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
	[key: string]: unknown;
}

export interface APIMTrace {
	route?: string;
	upstream_url?: string;
	elapsed_ms?: number;
	status?: number;
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
