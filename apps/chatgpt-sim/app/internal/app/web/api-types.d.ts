import type {
	ApiDiagnostics,
	GatewaySession,
	NetworkHop,
	RuntimeConfigBase,
} from "../../../../../shared/web/api-types.d.ts";

export type { ApiDiagnostics, GatewaySession, NetworkHop };

export interface RuntimeConfig extends RuntimeConfigBase {
	mcpUrl?: string;
	modelProvider?: string;
	dependencies?: string;
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

declare global {
	interface Window {
		PCE_CHATGPT_GO_CONFIG?: RuntimeConfig;
	}
}
