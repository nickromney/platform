import type {
	GatewaySession,
	RuntimeConfigBase,
} from "../../../../../shared/web/api-types.d.ts";

export type { GatewaySession };

export interface RuntimeConfig extends RuntimeConfigBase {
	role?: string;
	demoName?: string;
	scenarioCopy?: string;
	llmPrerequisite?: string;
	promptLabel?: string;
	defaultPrompt?: string;
	actionLabel?: string;
	capabilities?: string[];
	runEndpoint?: string;
	metricsEndpoint?: string;
}

export interface DemoStep {
	name?: string;
	status?: string;
	type?: string;
	detail?: string;
}

export interface DemoScore {
	name?: string;
	value?: string | number;
	comment?: string;
}

export interface DemoPayload {
	traceId?: string;
	langfuseStatus?: string;
	llmStatus?: string;
	answer?: string;
	steps?: DemoStep[];
	scores?: DemoScore[];
}

declare global {
	interface Window {
		LANGFUSE_DEMO_CONFIG?: RuntimeConfig;
	}
}
