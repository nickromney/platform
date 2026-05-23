// @ts-check
/// <reference lib="dom" />

/** @typedef {import("./api-types.d.ts").DemoPayload} DemoPayload */
/** @typedef {import("./api-types.d.ts").RuntimeConfig} RuntimeConfig */

const { bindGatewayLogout, initializeGatewayAuthState } =
	window.PlatformIdpAuth;
const {
	buttonElement,
	errorMessage,
	fetchText,
	formElement,
	initializeThemeSwitcher,
	postJSON,
	readRuntimeConfig,
	renderListInto,
	renderStatusInto,
	requireElement,
	setText,
	setTextDefault,
	textDefault,
	textAreaElement,
	withButtonBusy,
	withSubmitterBusy,
} = window.PlatformAppShell;
const cfg = /** @type {RuntimeConfig} */ (
	readRuntimeConfig("LANGFUSE_DEMO_CONFIG")
);
const form = formElement("run-form");
const promptField = textAreaElement("prompt");
const title = requireElement("app-title");
const traceID = requireElement("trace-id");
const runStatus = requireElement("run-status");
const langfuseStatus = requireElement("langfuse-status");
const llmStatus = requireElement("llm-status");
const answer = requireElement("answer");
const stepList = requireElement("step-list");
const scoreList = requireElement("score-list");
const button = buttonElement("run-button");
const promptLabel = requireElement("prompt-label");
const scenarioCopy = requireElement("scenario-copy");
const prereqNote = requireElement("prereq-note");
const capabilityList = requireElement("capability-list");
const logoutButton = buttonElement("logout-btn");
const authState = requireElement("auth-state");
const metricsOutput = requireElement("metrics-output");
const refreshMetricsButton = buttonElement("refresh-metrics");

document.body.dataset.role = cfg.role || "trace-chat";
initializeThemeSwitcher();

if (cfg.demoName) {
	title.textContent = cfg.demoName;
	document.title = cfg.demoName;
}
setTextDefault(scenarioCopy, cfg.scenarioCopy, "");
setTextDefault(prereqNote, cfg.llmPrerequisite, "");
setTextDefault(promptLabel, cfg.promptLabel, "Prompt");
if (cfg.defaultPrompt) {
	promptField.value = cfg.defaultPrompt;
}
if (cfg.actionLabel) {
	button.textContent = cfg.actionLabel;
}
renderCapabilities(Array.isArray(cfg.capabilities) ? cfg.capabilities : []);

bindGatewayLogout(logoutButton);

initializeAuthState();
refreshMetrics();

refreshMetricsButton.addEventListener("click", async () => {
	await withButtonBusy(refreshMetricsButton, "Refreshing", refreshMetrics);
});

form.addEventListener("submit", submitRun);

/**
 * @param {SubmitEvent} event
 */
async function submitRun(event) {
	event.preventDefault();
	renderStatusInto(runStatus, "Running...");
	setText(langfuseStatus, "running");
	setText(llmStatus, "running");
	try {
		await withSubmitterBusy(event, "Running...", async () => {
			/** @type {DemoPayload} */
			const payload = await postJSON(cfg.runEndpoint || "/api/run", {
				prompt: promptField.value,
			});
			render(payload);
			refreshMetrics();
		});
	} catch (error) {
		setText(
			answer,
			errorMessage(error instanceof Error ? error : String(error)),
		);
		renderStatusInto(runStatus, "Run failed.", true);
		setText(langfuseStatus, "error");
		setText(llmStatus, "error");
	}
}

async function initializeAuthState() {
	await initializeGatewayAuthState(authState, logoutButton, {
		path: "/.auth/me",
		ignoreErrors: true,
	});
}

/**
 * @param {DemoPayload} payload
 */
function render(payload) {
	setTextDefault(traceID, payload.traceId, "missing");
	setTextDefault(langfuseStatus, payload.langfuseStatus, "not reported");
	setTextDefault(llmStatus, payload.llmStatus, "not reported");
	setTextDefault(answer, payload.answer, "No answer returned.");
	renderStatusInto(
		runStatus,
		runStatusMessage(payload),
		runHasError(payload) ? "error" : "success",
	);
	renderListInto(
		stepList,
		payload.steps || [],
		(step) =>
			`${step.name}: ${step.status} (${step.type}) ${textDefault(step.detail, "")}`,
	);
	renderListInto(
		scoreList,
		payload.scores || [],
		(score) =>
			`${score.name}: ${score.value} ${textDefault(score.comment, "")}`,
	);
}

/**
 * @param {DemoPayload} payload
 */
function runHasError(payload) {
	return payload.langfuseStatus === "error" || payload.llmStatus === "error";
}

/**
 * @param {DemoPayload} payload
 */
function runStatusMessage(payload) {
	const trace = textDefault(payload.traceId, "no trace id");
	const langfuse = textDefault(payload.langfuseStatus, "not reported");
	const llm = textDefault(payload.llmStatus, "not reported");
	return `Run complete. Trace: ${trace}. Langfuse: ${langfuse}. LLM: ${llm}.`;
}

async function refreshMetrics() {
	try {
		setText(
			metricsOutput,
			await fetchText(cfg.metricsEndpoint || "/metrics", {
				cache: "no-store",
			}),
		);
	} catch (error) {
		setText(
			metricsOutput,
			errorMessage(error instanceof Error ? error : String(error)),
		);
	}
}

/**
 * @param {string[]} items
 */
function renderCapabilities(items) {
	renderListInto(capabilityList, items, (item) => item);
}
