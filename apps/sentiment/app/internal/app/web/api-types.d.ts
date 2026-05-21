import type { RuntimeConfigBase } from "../../../../../shared/web/api-types.d.ts";

export type {
	APIMTrace,
	ApiDiagnostics,
	CookieClearResult,
	GatewaySession,
	LoggedInUser,
	LogoutResult,
	NetworkHop,
	ThemeMode,
} from "../../../../../shared/web/api-types.d.ts";

export interface RuntimeConfig extends RuntimeConfigBase {}

export interface SentimentComment {
	id: string;
	timestamp: string;
	text: string;
	label: "positive" | "negative" | "neutral";
	confidence: number;
	latency_ms: number;
}

declare global {
	interface Window {
		SENTIMENT_RUNTIME_CONFIG?: RuntimeConfig;
	}
}
