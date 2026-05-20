export type ThemeMode = "light" | "dark" | "system";

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

export interface RuntimeConfig {
	appName?: string;
	environment?: string;
	authMethod?: "none" | "oidc" | "gateway";
	apiAuthMethod?: "none" | "oidc" | "gateway";
	apiBasePath?: string;
	backendURL?: string;
	gatewayURL?: string;
	oidcAuthority?: string;
	oidcClientId?: string;
	oidcRedirect?: string;
	showNetworkPath?: boolean;
	networkHops?: NetworkHop[];
	user?: LoggedInUser;
	theme?: ThemeMode;
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
	networkHops: NetworkHop[];
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

declare global {
	interface Window {
		SUBNETCALC_RUNTIME_CONFIG?: RuntimeConfig;
	}
}
