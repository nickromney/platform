const config = window.PCE_CHATGPT_GO_CONFIG || {};
const messages = document.getElementById("messages");
const statusEl = document.getElementById("status");
const toolOutput = document.getElementById("tool-output");
const discoveryOutput = document.getElementById("discovery-output");
const connectorSelect = document.getElementById("connector");
const connectorList = document.getElementById("connector-list");

document.getElementById("mcp-url").textContent = config.mcpUrl || "unknown";
document.getElementById("model-provider").textContent = config.modelProvider || "deterministic";
document.getElementById("dependencies").textContent = config.dependencies || "go-stdlib-only";
document.getElementById("chat-form").addEventListener("submit", submitChat);
document.getElementById("discover").addEventListener("click", refreshDiscovery);
document.getElementById("connector-form").addEventListener("submit", addConnector);
connectorList.addEventListener("click", deleteConnector);
document.getElementById("connector-url").value = config.mcpUrl || "";

initialize();

async function initialize() {
  await refreshConnectors();
  await refreshDiscovery();
}

async function submitChat(event) {
  event.preventDefault();
  const input = document.getElementById("message");
  const message = input.value.trim();
  if (!message) return;
  input.value = "";
  appendMessage("user", "You", message);
  statusEl.textContent = "Calling MCP";
  try {
    const result = await postJSON("/api/chat", {
      message,
      tool: document.getElementById("tool").value,
      connector_id: connectorSelect.value,
    });
    const connector = result.connector || selectedConnectorSummary();
    appendMessage("assistant", connectorLabel(connector), result.assistant, connectorMeta(connector));
    toolOutput.textContent = JSON.stringify({
      connector,
      selected_tool: result.selected_tool,
      model: result.model,
      tool_arguments: result.tool_arguments,
      tool_result: result.tool_result,
      mcp_steps: result.mcp_steps,
    }, null, 2);
    discoveryOutput.textContent = JSON.stringify(result.discovery, null, 2);
    statusEl.textContent = `Called ${result.selected_tool}`;
  } catch (error) {
    appendMessage("assistant", "ChatGPT Sim", `Error: ${error.message}`);
    statusEl.textContent = `Error: ${error.message}`;
  }
}

async function refreshDiscovery() {
  statusEl.textContent = "Discovering";
  try {
    const result = await fetchJSON("/api/discovery");
    discoveryOutput.textContent = JSON.stringify(result, null, 2);
    statusEl.textContent = "Ready";
  } catch (error) {
    discoveryOutput.textContent = JSON.stringify({ error: error.message }, null, 2);
    statusEl.textContent = `Discovery failed: ${error.message}`;
  }
}

async function refreshConnectors() {
  const result = await fetchJSON("/api/connectors");
  const items = result.items || [];
  connectorSelect.innerHTML = items.map((item) => (
    `<option value="${escapeAttr(item.id)}">${escapeHTML(item.name)} (${escapeHTML(item.auth)})</option>`
  )).join("");
  connectorList.innerHTML = items.map(renderConnector).join("") || "<p>No MCP connectors configured.</p>";
}

async function addConnector(event) {
  event.preventDefault();
  statusEl.textContent = "Adding MCP";
  try {
    const result = await postJSON("/api/connectors", {
      name: document.getElementById("connector-name").value,
      url: document.getElementById("connector-url").value,
      auth: document.getElementById("connector-auth").value,
      oauth_client_mode: document.getElementById("connector-client-mode").value,
      oauth_client_id: document.getElementById("connector-client-id").value,
      oauth_client_secret: document.getElementById("connector-client-secret").value,
      oauth_token_endpoint_auth_method: document.getElementById("connector-token-auth-method").value,
      oauth_requested_scopes: document.getElementById("connector-requested-scopes").value,
      oauth_base_scopes: document.getElementById("connector-base-scopes").value,
      oauth_authorization_url: document.getElementById("connector-auth-url").value,
      oauth_token_url: document.getElementById("connector-token-url").value,
      oauth_registration_url: document.getElementById("connector-registration-url").value,
      oauth_authorization_server_base: document.getElementById("connector-auth-server-base").value,
      oauth_resource: document.getElementById("connector-resource").value,
      oauth_oidc_configuration_url: document.getElementById("connector-oidc-config-url").value,
      oauth_oidc_userinfo_endpoint: document.getElementById("connector-oidc-userinfo").value,
      oauth_oidc_scopes_supported: document.getElementById("connector-oidc-scopes").value,
    });
    await refreshConnectors();
    connectorSelect.value = result.id;
    discoveryOutput.textContent = JSON.stringify(result.discovery || result, null, 2);
    statusEl.textContent = result.status === "ready" ? "MCP added" : "MCP discovery failed";
  } catch (error) {
    if (error.status === 409 && error.payload && error.payload.connector) {
      await refreshConnectors();
      connectorSelect.value = error.payload.connector.id;
      statusEl.textContent = "MCP already exists";
      return;
    }
    statusEl.textContent = `Add failed: ${error.message}`;
  }
}

async function deleteConnector(event) {
  const button = event.target.closest("[data-delete-connector]");
  if (!button) return;
  const id = button.getAttribute("data-delete-connector");
  statusEl.textContent = "Deleting MCP";
  try {
    await requestJSON(`/api/connectors/${encodeURIComponent(id)}`, { method: "DELETE" });
    await refreshConnectors();
    await refreshDiscovery();
    statusEl.textContent = "MCP deleted";
  } catch (error) {
    statusEl.textContent = `Delete failed: ${error.message}`;
  }
}

function renderConnector(item) {
  const oauth = item.oauth && item.oauth.authorization_endpoint
    ? `<span>OAuth: ${escapeHTML(item.oauth.authorization_endpoint)}</span>`
    : "<span>OAuth: not discovered</span>";
  const login = item.login_url
    ? `<a class="login-link" href="${escapeAttr(item.login_url)}" target="_blank" rel="noopener">Sign in</a>`
    : item.oauth && item.oauth.authorization_endpoint
      ? `<span>Login: enter an OAuth Client ID, then add this connector.</span>`
      : "";
  const error = item.error ? `<span class="error">${escapeHTML(item.error)}</span>` : "";
  const advanced = item.oauth_advanced
    ? `<details class="connector-details"><summary>Advanced OAuth</summary><pre>${escapeHTML(JSON.stringify(item.oauth_advanced, null, 2))}</pre></details>`
    : "";
  const actions = item.id === "default"
    ? ""
    : `<button type="button" class="danger" data-delete-connector="${escapeAttr(item.id)}">Delete</button>`;
  return `
    <article class="connector">
      <div class="connector-header">
        <strong>${escapeHTML(item.name)}</strong>
        ${actions}
      </div>
      <span>${escapeHTML(item.url)}</span>
      <span>Status: ${escapeHTML(item.status)} | Auth: ${escapeHTML(item.auth)}</span>
      ${oauth}
      ${login}
      ${advanced}
      ${error}
    </article>
  `;
}

function appendMessage(kind, label, text, meta) {
  const article = document.createElement("article");
  article.className = `message ${kind}`;
  const strong = document.createElement("strong");
  strong.textContent = label;
  article.append(strong);
  if (meta) {
    const metaEl = document.createElement("span");
    metaEl.className = "message-meta";
    metaEl.textContent = meta;
    article.append(metaEl);
  }
  const body = document.createElement("div");
  body.textContent = text;
  article.append(body);
  messages.append(article);
  messages.scrollTop = messages.scrollHeight;
}

function selectedConnectorSummary() {
  const option = connectorSelect.selectedOptions && connectorSelect.selectedOptions[0];
  return {
    id: connectorSelect.value,
    name: option ? option.textContent : connectorSelect.value,
  };
}

function connectorLabel(connector) {
  const name = connector && connector.name ? connector.name : "selected MCP";
  return `ChatGPT Sim via ${name}`;
}

function connectorMeta(connector) {
  if (!connector) return "";
  const parts = [];
  if (connector.id) parts.push(`id=${connector.id}`);
  if (connector.auth) parts.push(`auth=${connector.auth}`);
  if (connector.url) parts.push(connector.url);
  return parts.join(" | ");
}

function escapeHTML(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[char]);
}

function escapeAttr(value) {
  return escapeHTML(value).replace(/`/g, "&#96;");
}

async function postJSON(url, body) {
  return requestJSON(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

async function requestJSON(url, options = {}) {
  const response = await fetch(url, options);
  if (response.status === 204) return {};
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload.error || `HTTP ${response.status}`);
    error.status = response.status;
    error.payload = payload;
    throw error;
  }
  return payload;
}

async function fetchJSON(url) {
  return requestJSON(url);
}
