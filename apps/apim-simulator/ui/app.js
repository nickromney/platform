const storageKey = "apim-console-settings";
const defaultHeaders = '{\n  "x-apim-trace": "true"\n}';
const state = {
  summary: null,
  traces: [],
  selectedTraceId: "",
  selectedScopeId: "",
  busy: false,
};

const el = {};

document.addEventListener("DOMContentLoaded", () => {
  for (const id of [
    "base-url",
    "tenant-key",
    "connection-form",
    "load-demo",
    "connect",
    "refresh",
    "status-message",
    "metric-apis",
    "metric-routes",
    "metric-products",
    "metric-subscriptions",
    "apis-list",
    "routes-list",
    "products-list",
    "backends-list",
    "policy-form",
    "policy-scope",
    "policy-xml",
    "save-policy",
    "policy-message",
    "replay-form",
    "replay-method",
    "replay-path",
    "replay-headers",
    "replay-body",
    "run-replay",
    "replay-result",
    "trace-list",
    "trace-detail",
    "subscription-grid",
  ]) {
    el[toCamel(id)] = document.getElementById(id);
  }

  loadStoredSettings();
  el.connectionForm.addEventListener("submit", (event) => {
    event.preventDefault();
    refreshDashboard();
  });
  el.loadDemo.addEventListener("click", loadLocalDemo);
  el.refresh.addEventListener("click", () => refreshDashboard(state.selectedScopeId));
  el.policyScope.addEventListener("change", () => {
    const scope = flattenPolicyScopes().find((item) => scopeId(item) === el.policyScope.value);
    if (scope) loadPolicy(scope);
  });
  el.policyForm.addEventListener("submit", savePolicy);
  el.replayForm.addEventListener("submit", runReplay);
});

function toCamel(id) {
  return id.replace(/-([a-z])/g, (_, char) => char.toUpperCase());
}

function loadStoredSettings() {
  try {
    const stored = JSON.parse(window.localStorage.getItem(storageKey) || "{}");
    if (stored.baseUrl) el.baseUrl.value = stored.baseUrl;
    if (stored.tenantKey) el.tenantKey.value = stored.tenantKey;
  } catch {
    window.localStorage.removeItem(storageKey);
  }
}

function persistSettings() {
  window.localStorage.setItem(storageKey, JSON.stringify({
    baseUrl: el.baseUrl.value.trim(),
    tenantKey: el.tenantKey.value.trim(),
  }));
}

function loadLocalDemo() {
  el.baseUrl.value = "http://localhost:8000";
  el.tenantKey.value = "local-dev-tenant-key";
  el.replayMethod.value = "GET";
  el.replayPath.value = "/api/health";
  el.replayHeaders.value = defaultHeaders;
  el.replayBody.value = "";
  state.summary = null;
  state.traces = [];
  state.selectedTraceId = "";
  state.selectedScopeId = "";
  el.policyXml.value = "";
  el.policyMessage.textContent = "";
  el.replayResult.textContent = "Run a replay to inspect the response and trace metadata.";
  render();
  setStatus("Loaded the default local demo values. Press Connect to sync with the simulator.");
  persistSettings();
}

async function apiFetch(path, options = {}) {
  persistSettings();
  const headers = new Headers(options.headers || {});
  headers.set("X-Apim-Tenant-Key", el.tenantKey.value.trim());
  if (options.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  const response = await fetch(`${el.baseUrl.value.trim()}${path}`, { ...options, headers });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`${response.status} ${response.statusText}: ${text}`);
  }
  return response.json();
}

async function refreshDashboard(preferredScope) {
  if (!el.tenantKey.value.trim()) {
    setStatus("Tenant key is required for management access.");
    return;
  }
  setBusy(true);
  setStatus("Refreshing summary, policies, and traces.");
  try {
    const [summary, tracePayload] = await Promise.all([
      apiFetch("/apim/management/summary"),
      apiFetch("/apim/management/traces"),
    ]);
    state.summary = summary;
    state.traces = tracePayload.items || [];
    if (!state.selectedTraceId && state.traces[0]) {
      state.selectedTraceId = state.traces[0].trace_id;
    }
    render();
    const scopes = flattenPolicyScopes();
    const nextScope = scopes.find((scope) => scopeId(scope) === preferredScope)
      || scopes.find((scope) => scopeId(scope) === state.selectedScopeId)
      || scopes[0];
    if (nextScope) {
      await loadPolicy(nextScope);
    }
    setStatus("Console is in sync with the simulator.");
  } catch (error) {
    setStatus(error.message || "Unable to refresh the console.");
  } finally {
    setBusy(false);
  }
}

async function loadPolicy(scope) {
  const policy = await apiFetch(`/apim/management/policies/${scope.scope_type}/${encodeURIComponent(scope.scope_name)}`);
  state.selectedScopeId = scopeId(scope);
  el.policyScope.value = state.selectedScopeId;
  el.policyXml.value = policy.xml || "";
  el.policyMessage.textContent = `Loaded ${scope.scope_type} policy for ${scope.scope_name}.`;
}

async function savePolicy(event) {
  event.preventDefault();
  const scope = flattenPolicyScopes().find((item) => scopeId(item) === state.selectedScopeId);
  if (!scope) {
    el.policyMessage.textContent = "No policy scope is selected.";
    return;
  }
  setBusy(true);
  try {
    await apiFetch(`/apim/management/policies/${scope.scope_type}/${encodeURIComponent(scope.scope_name)}`, {
      method: "PUT",
      body: JSON.stringify({ xml: el.policyXml.value }),
    });
    el.policyMessage.textContent = `Saved ${scope.scope_type} policy for ${scope.scope_name}.`;
  } catch (error) {
    el.policyMessage.textContent = error.message || "Policy update failed.";
  } finally {
    setBusy(false);
  }
}

async function runReplay(event) {
  event.preventDefault();
  setBusy(true);
  setStatus("Executing replay through the simulator.");
  try {
    const replay = await apiFetch("/apim/management/replay", {
      method: "POST",
      body: JSON.stringify({
        method: el.replayMethod.value,
        path: el.replayPath.value,
        headers: JSON.parse(el.replayHeaders.value || "{}"),
        body_text: el.replayBody.value || undefined,
      }),
    });
    el.replayResult.textContent = prettyJson(replay);
    if (replay.trace) {
      state.selectedTraceId = replay.trace.trace_id;
      state.traces = [replay.trace, ...state.traces.filter((trace) => trace.trace_id !== replay.trace.trace_id)];
      renderTraces();
    }
    setStatus("Replay completed.");
  } catch (error) {
    setStatus(error.message || "Replay failed.");
  } finally {
    setBusy(false);
  }
}

async function rotateKey(subscriptionId, key) {
  setBusy(true);
  setStatus(`Rotating ${key} key for ${subscriptionId}.`);
  try {
    await apiFetch(`/apim/management/subscriptions/${subscriptionId}/rotate?key=${key}`, { method: "POST" });
    await refreshDashboard(state.selectedScopeId);
  } catch (error) {
    setStatus(error.message || "Unable to rotate key.");
    setBusy(false);
  }
}

function flattenPolicyScopes() {
  const summary = state.summary;
  if (!summary) return [];
  const scopes = [summary.gateway_policy_scope];
  for (const api of summary.apis || []) {
    scopes.push(api.policy_scope);
    for (const operation of api.operations || []) scopes.push(operation.policy_scope);
  }
  for (const route of summary.routes || []) {
    if (route.policy_scope) scopes.push(route.policy_scope);
  }
  return scopes;
}

function scopeId(scope) {
  return `${scope.scope_type}:${scope.scope_name}`;
}

function render() {
  const summary = state.summary || {};
  el.metricApis.textContent = (summary.apis || []).length;
  el.metricRoutes.textContent = (summary.routes || []).length;
  el.metricProducts.textContent = (summary.products || []).length;
  el.metricSubscriptions.textContent = (summary.subscriptions || []).length;
  renderList(el.apisList, summary.apis, (api) => [api.name, `/${api.path}`, `${(api.operations || []).length} operations`]);
  renderList(el.routesList, summary.routes, (route) => [route.name, route.path_prefix, route.upstream_base_url]);
  renderList(el.productsList, summary.products, (product) => [
    product.id,
    product.name,
    product.require_subscription ? "Subscription required" : "Open access",
  ]);
  renderList(el.backendsList, summary.backends, (backend) => [backend.id, backend.url, backend.auth_type]);
  renderScopes();
  renderTraces();
  renderSubscriptions();
}

function renderList(target, items, fields) {
  if (!items || items.length === 0) {
    target.innerHTML = '<li class="empty">Nothing loaded.</li>';
    return;
  }
  target.innerHTML = items.map((item) => {
    const [title, subtitle, meta] = fields(item);
    return `<li><strong>${escapeHTML(title)}</strong><span>${escapeHTML(subtitle)}</span><small>${escapeHTML(meta)}</small></li>`;
  }).join("");
}

function renderScopes() {
  const scopes = flattenPolicyScopes();
  el.policyScope.innerHTML = scopes.map((scope) => {
    const id = scopeId(scope);
    return `<option value="${escapeHTML(id)}">${escapeHTML(scope.scope_type)} / ${escapeHTML(scope.scope_name)}</option>`;
  }).join("");
  if (state.selectedScopeId) el.policyScope.value = state.selectedScopeId;
}

function renderTraces() {
  if (state.traces.length === 0) {
    el.traceList.innerHTML = '<li class="empty">No traces captured yet.</li>';
    el.traceDetail.textContent = "Select a trace to inspect its metadata.";
    return;
  }
  el.traceList.innerHTML = state.traces.map((trace) => {
    const active = trace.trace_id === state.selectedTraceId ? " active" : "";
    return `<li><button type="button" class="trace-chip${active}" data-trace-id="${escapeHTML(trace.trace_id)}"><strong>${escapeHTML(trace.route)}</strong><span>${escapeHTML(String(trace.status))}</span><small>${escapeHTML(trace.forwarded_proto || "direct")}</small></button></li>`;
  }).join("");
  el.traceList.querySelectorAll("[data-trace-id]").forEach((button) => {
    button.addEventListener("click", () => {
      state.selectedTraceId = button.dataset.traceId || "";
      renderTraces();
    });
  });
  const selected = state.traces.find((trace) => trace.trace_id === state.selectedTraceId) || state.traces[0];
  el.traceDetail.textContent = prettyJson(selected);
}

function renderSubscriptions() {
  const subscriptions = state.summary?.subscriptions || [];
  if (subscriptions.length === 0) {
    el.subscriptionGrid.innerHTML = '<p class="empty">No subscriptions loaded.</p>';
    return;
  }
  el.subscriptionGrid.innerHTML = subscriptions.map((subscription) => `
    <article class="subscription-card">
      <header>
        <div><h3>${escapeHTML(subscription.name)}</h3><p>${escapeHTML(subscription.id)}</p></div>
        <span class="state-pill">${escapeHTML(subscription.state)}</span>
      </header>
      <dl>
        <div><dt>Primary</dt><dd>${escapeHTML(subscription.keys?.primary || "")}</dd></div>
        <div><dt>Secondary</dt><dd>${escapeHTML(subscription.keys?.secondary || "")}</dd></div>
        <div><dt>Products</dt><dd>${escapeHTML((subscription.products || []).join(", ") || "None")}</dd></div>
      </dl>
      <div class="subscription-actions">
        <button type="button" data-rotate="${escapeHTML(subscription.id)}" data-key="primary">Rotate Primary</button>
        <button type="button" data-rotate="${escapeHTML(subscription.id)}" data-key="secondary">Rotate Secondary</button>
      </div>
    </article>
  `).join("");
  el.subscriptionGrid.querySelectorAll("[data-rotate]").forEach((button) => {
    button.addEventListener("click", () => rotateKey(button.dataset.rotate, button.dataset.key));
  });
}

function setBusy(value) {
  state.busy = value;
  for (const button of document.querySelectorAll("button")) {
    button.disabled = value;
  }
  el.connect.textContent = value ? "Working..." : "Connect";
}

function setStatus(message) {
  el.statusMessage.textContent = message;
}

function prettyJson(value) {
  return JSON.stringify(value, null, 2);
}

function escapeHTML(value) {
  return String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[char]);
}
