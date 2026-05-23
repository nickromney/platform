import type { RuntimeConfigBase } from "../../../../../shared/web/api-types.d.ts";

export interface RuntimeConfig extends RuntimeConfigBase {
	managementBasePath?: string;
}

export interface ManagementRoute {
	name: string;
	path_prefix?: string;
	host_match?: string;
	upstream_base_url: string;
	upstream_path_prefix?: string;
	product?: string;
}

export interface ManagementAPI {
	id: string;
	name: string;
	path: string;
	type: string;
	products?: string[];
	mcp_properties?: Record<string, string>;
}

export interface ManagementProduct {
	id: string;
	name: string;
	description?: string;
	require_subscription?: boolean;
	groups?: string[];
	tags?: string[];
}

export interface ManagementSubscription {
	id: string;
	name: string;
	state?: string;
}

export interface ManagementSummary {
	apis: ManagementAPI[];
	routes: ManagementRoute[];
	products: ManagementProduct[];
	subscriptions: ManagementSubscription[];
}

export interface TraceRecord {
	trace_id: string;
	method: string;
	path: string;
	route_name: string;
	upstream_url: string;
	status_code: number;
	started_at: string;
	duration_ms: number;
	request_headers?: Record<string, string>;
	response_headers?: Record<string, string>;
	error?: string;
}

export interface TraceListResponse {
	items?: TraceRecord[];
}

declare global {
	interface Window {
		APIM_SIMULATOR_RUNTIME_CONFIG?: RuntimeConfig;
	}
}
