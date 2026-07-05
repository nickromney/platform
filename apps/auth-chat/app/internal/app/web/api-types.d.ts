import type {
	AppShellStatusTone,
	GatewaySession,
	NetworkHop,
	RuntimeConfigBase,
} from "../../../../../shared/web/api-types.d.ts";

export type { AppShellStatusTone, GatewaySession, NetworkHop };

export type APIPrimitive = string | number | boolean | null;
export type APIValue = APIPrimitive | APIRecord | APIValue[];

export interface APIRecord {
	[key: string]: APIValue | APIRecord | undefined;
}

export interface RuntimeConfig extends RuntimeConfigBase {
	authEndpoint: string;
	authValidateEndpoint: string;
	chatEndpoint: string;
	sessionEndpoint: string;
	model: string;
	modelProvider: string;
	llmUrl: string;
	apiAuthMode: string;
	publicBaseUrl: string;
}

export interface AuthEvidence {
	status: string;
	source: string;
	user?: APIRecord;
	session?: GatewaySession | null;
	token?: APIRecord;
	endpoints?: APIRecord;
	oidc?: APIRecord;
}

export interface ChatResponse {
	assistant: string;
	model?: APIRecord;
	auth?: AuthEvidence;
	usage?: APIRecord;
	duration_ms?: number;
}

export interface ApiError extends Error {
	status?: number;
	payload?: APIRecord;
}

declare global {
	interface Window {
		AUTH_CHAT_CONFIG?: RuntimeConfig;
	}
}
