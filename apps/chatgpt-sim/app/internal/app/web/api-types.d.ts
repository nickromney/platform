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
	traceProvider?: string;
	dependencyFootprint?: string;
}

export type APIPrimitive = string | number | boolean | null;
export type APIValue = APIPrimitive | APIRecord | APIValue[];

export interface APIRecord {
	[key: string]: APIValue | undefined;
}

export interface ConnectorOAuthMetadata extends APIRecord {
	authorization_endpoint?: string;
	token_endpoint?: string;
	registration_endpoint?: string;
	issuer?: string;
	scopes_supported?: string[];
}

export interface ConnectorDiscovery extends APIRecord {
	metadata_url?: string;
	protected_resource?: APIRecord;
	oauth_authorization_server?: ConnectorOAuthMetadata;
	oidc_configuration?: APIRecord;
}

export interface MCPContentItem extends APIRecord {
	type: string;
	text?: string;
}

export interface MCPToolResult extends APIRecord {
	content?: MCPContentItem[];
	structuredContent?: APIRecord;
	isError?: boolean;
}

export interface ConnectorSummary extends APIRecord {
	id: string;
	name: string;
	url?: string;
	auth?: string;
	status?: string;
	login_url?: string;
	error?: string;
	oauth?: ConnectorOAuthMetadata;
	oauth_advanced?: APIRecord;
	discovery?: ConnectorDiscovery;
}

export interface ModelRouteMetadata {
	provider: string;
	model?: string;
	route?: string;
	status?: string;
	source?: string;
	error?: string;
}

export interface TraceMetadata {
	provider: string;
	status: string;
	traceId: string;
	error?: string;
}

export interface MCPStep {
	method: string;
	status: string | number;
	route?: string;
	response?: APIRecord;
	error?: string;
}

export interface ChatResponse {
	assistant: string;
	selected_tool: string;
	model?: ModelRouteMetadata;
	trace?: TraceMetadata;
	connector?: ConnectorSummary;
	tool_arguments?: APIRecord;
	tool_result?: MCPToolResult;
	mcp_steps?: MCPStep[];
	discovery?: ConnectorDiscovery;
}

export interface ConnectorListResponse {
	items?: ConnectorSummary[];
}

export interface ApiError extends Error {
	status?: number;
	payload?: APIRecord & {
		connector?: ConnectorSummary;
	};
}

declare global {
	interface Window {
		PCE_CHATGPT_GO_CONFIG?: RuntimeConfig;
	}
}
