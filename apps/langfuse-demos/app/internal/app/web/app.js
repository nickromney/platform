// @ts-check

const cfg = window.LANGFUSE_DEMO_CONFIG || {};
const form = document.querySelector("#run-form");
const promptField = /** @type {HTMLTextAreaElement | null} */ (document.querySelector("#prompt"));
const title = document.querySelector("#app-title");
const traceID = document.querySelector("#trace-id");
const langfuseStatus = document.querySelector("#langfuse-status");
const llmStatus = document.querySelector("#llm-status");
const answer = document.querySelector("#answer");
const stepList = document.querySelector("#step-list");
const scoreList = document.querySelector("#score-list");
const button = form?.querySelector("button");
const promptLabel = document.querySelector("#prompt-label");
const scenarioCopy = document.querySelector("#scenario-copy");
const prereqNote = document.querySelector("#prereq-note");
const capabilityList = document.querySelector("#capability-list");
const logoutButton = /** @type {HTMLButtonElement | null} */ (document.querySelector("#logout-btn"));
const authState = document.querySelector("#auth-state");
const metricsOutput = document.querySelector("#metrics-output");
const refreshMetricsButton = /** @type {HTMLButtonElement | null} */ (document.querySelector("#refresh-metrics"));
const idpAuth = window.PlatformIdpAuth;

document.body.dataset.role = cfg.role || "trace-chat";

if (title && cfg.demoName) {
  title.textContent = cfg.demoName;
  document.title = cfg.demoName;
}
setText(scenarioCopy, cfg.scenarioCopy || "");
setText(prereqNote, cfg.llmPrerequisite || "");
setText(promptLabel, cfg.promptLabel || "Prompt");
if (promptField && cfg.defaultPrompt) {
  promptField.value = cfg.defaultPrompt;
}
if (button && cfg.actionLabel) {
  button.textContent = cfg.actionLabel;
}
renderCapabilities(Array.isArray(cfg.capabilities) ? cfg.capabilities : []);

logoutButton?.addEventListener("click", () => {
  window.location.assign(logoutButton.dataset.signOutUrl || "/oauth2/sign_out?rd=/signed-out.html");
});

initializeAuthState();
refreshMetrics();

refreshMetricsButton?.addEventListener("click", () => {
  refreshMetrics();
});

form?.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!promptField || !button) return;
  button.disabled = true;
  setText(langfuseStatus, "running");
  setText(llmStatus, "running");
  try {
    const response = await fetch(cfg.runEndpoint || "/api/run", {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({prompt: promptField.value}),
    });
    const payload = await response.json();
    render(payload);
    refreshMetrics();
  } catch (error) {
    setText(answer, error instanceof Error ? error.message : String(error));
    setText(langfuseStatus, "error");
    setText(llmStatus, "unknown");
  } finally {
    button.disabled = false;
  }
});

async function initializeAuthState() {
  if (!authState || !logoutButton || !idpAuth) return;
  try {
    const session = await idpAuth.fetchGatewaySession("/.auth/me");
    if (session) {
      authState.textContent = `Signed in as ${idpAuth.gatewayDisplayName(session)}`;
      logoutButton.hidden = false;
      return;
    }
  } catch (error) {
    // Direct local runs do not expose forwarded SSO identity headers.
  }
  authState.textContent = "Not signed in.";
  logoutButton.hidden = true;
}

function render(payload) {
  setText(traceID, payload.traceId || "missing");
  setText(langfuseStatus, payload.langfuseStatus || "unknown");
  setText(llmStatus, payload.llmStatus || "unknown");
  setText(answer, payload.answer || "No answer returned.");
  renderList(stepList, payload.steps || [], (step) => `${step.name}: ${step.status} (${step.type}) ${step.detail || ""}`);
  renderList(scoreList, payload.scores || [], (score) => `${score.name}: ${score.value} ${score.comment || ""}`);
}

async function refreshMetrics() {
  if (!metricsOutput) return;
  try {
    const response = await fetch(cfg.metricsEndpoint || "/metrics", {cache: "no-store"});
    metricsOutput.textContent = await response.text();
  } catch (error) {
    metricsOutput.textContent = error instanceof Error ? error.message : String(error);
  }
}

function renderList(node, items, format) {
  if (!node) return;
  node.textContent = "";
  for (const item of items) {
    const li = document.createElement("li");
    li.textContent = format(item);
    node.append(li);
  }
}

function renderCapabilities(items) {
  if (!capabilityList) return;
  capabilityList.textContent = "";
  for (const item of items) {
    const li = document.createElement("li");
    li.textContent = item;
    capabilityList.append(li);
  }
}

function setText(node, value) {
  if (node) node.textContent = value;
}
