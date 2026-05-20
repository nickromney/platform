export interface RuntimeConfig {
	mcpUrl?: string;
	modelProvider?: string;
	dependencies?: string;
	showNetworkPath?: boolean;
	networkHops?: NetworkHop[];
}

export interface NetworkHop {
	label: string;
	detail: string;
	role?: string;
}

export interface GatewaySession {
	claims?: Array<{
		typ?: string;
		type?: string;
		val?: string;
		value?: string;
	}>;
	userDetails?: string;
	user_details?: string;
	email?: string;
	preferred_username?: string;
	name?: string;
	[key: string]: unknown;
}

export interface ConnectorOAuthMetadata {
	authorization_endpoint?: string;
	token_endpoint?: string;
	registration_endpoint?: string;
	issuer?: string;
	scopes_supported?: string[];
}

export interface ConnectorSummary {
	id: string;
	name: string;
	url?: string;
	auth?: string;
	status?: string;
	login_url?: string;
	error?: string;
	oauth?: ConnectorOAuthMetadata;
	oauth_advanced?: Record<string, unknown>;
	discovery?: unknown;
}

export interface ChatResponse {
	assistant: string;
	selected_tool: string;
	model?: Record<string, unknown>;
	connector?: ConnectorSummary;
	tool_arguments?: Record<string, unknown>;
	tool_result?: unknown;
	mcp_steps?: unknown[];
	discovery?: unknown;
}

export interface ConnectorListResponse {
	items?: ConnectorSummary[];
}

export interface ApiError extends Error {
	status?: number;
	payload?: {
		connector?: ConnectorSummary;
		[key: string]: unknown;
	};
}

export interface ApiDiagnostics {
	traceId?: string;
	correlationId?: string;
	requestStartedAt: string;
	responseEndedAt: string;
	durationMs: number;
	requestURL: string;
	status: number;
}

declare global {
	interface Window {
		PCE_CHATGPT_GO_CONFIG?: RuntimeConfig;
	}
}
