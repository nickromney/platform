import type { OIDCRuntimeConfig } from "../../../../../shared/web/api-types.d.ts";

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

export interface RuntimeConfig extends OIDCRuntimeConfig {}

declare global {
	interface Window {
		SUBNETCALC_RUNTIME_CONFIG?: RuntimeConfig;
	}
}
