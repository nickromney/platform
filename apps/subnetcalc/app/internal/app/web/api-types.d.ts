import type {
	APITiming,
	OIDCRuntimeConfig,
} from "../../../../../shared/web/api-types.d.ts";

export type {
	APIMTrace,
	ApiDiagnostics,
	CookieClearResult,
	GatewaySession,
	KeyValueTableRow,
	LoggedInUser,
	LogoutResult,
	NetworkHop,
	ThemeMode,
} from "../../../../../shared/web/api-types.d.ts";

export interface RuntimeConfig extends OIDCRuntimeConfig {}

export interface HealthResponse {
	status: string;
	service: string;
	version: string;
	server_side_token_validation?: boolean;
}

export interface UserInfoResponse {
	sub?: string;
	email?: string;
	preferred_username?: string;
}

export interface ValidationResult {
	valid: boolean;
	address: string;
	type: "network" | "host";
	is_ipv4: boolean;
}

export interface PrivateCheckResult {
	is_rfc1918: boolean;
	matched_rfc1918_range?: string;
	is_rfc6598: boolean;
	matched_rfc6598_range?: string;
}

export interface CloudflareCheckResult {
	is_cloudflare: boolean;
	matched_ranges?: string[];
}

export interface SubnetInfoResult {
	mode: string;
	network_address: string;
	netmask: string;
	wildcard_mask: string;
	prefix_length: number;
	total_addresses: number;
	usable_addresses: number;
	first_usable_ip: string;
	last_usable_ip: string;
	broadcast_address?: string;
	note?: string;
}

export interface ProviderRangeResult {
	provider: string;
	address: string;
	is_provider_range: boolean;
	ip_version: number;
	range_source: string;
	range_source_url?: string;
	range_source_note?: string;
	matched_ranges?: string[];
}

export interface TimedResponse<T> {
	data: T;
	timing: APITiming;
}

declare global {
	interface Window {
		SUBNETCALC_RUNTIME_CONFIG?: RuntimeConfig;
	}
}
