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

export interface SentimentComment {
	id: string;
	timestamp: string;
	text: string;
	label: "positive" | "negative" | "neutral";
	confidence: number;
	latency_ms: number;
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
		SENTIMENT_RUNTIME_CONFIG?: RuntimeConfig;
	}
}
