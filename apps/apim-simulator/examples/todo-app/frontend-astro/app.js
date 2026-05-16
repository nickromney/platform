class TodoFrontendApp {
  constructor() {
    const runtimeConfig = window.RUNTIME_CONFIG || {};
    const grafanaBaseUrl = runtimeConfig.GRAFANA_BASE_URL || "https://lgtm.apim.127.0.0.1.sslip.io:8443";
    this.config = {
      API_BASE_URL: runtimeConfig.API_BASE_URL || "http://localhost:8000",
      APIM_SUBSCRIPTION_KEY: runtimeConfig.APIM_SUBSCRIPTION_KEY || "",
      GRAFANA_BASE_URL: grafanaBaseUrl,
      OBSERVABILITY_DASHBOARD_URL:
        runtimeConfig.OBSERVABILITY_DASHBOARD_URL ||
        this.joinUrl(grafanaBaseUrl, "/d/apim-simulator-overview/apim-simulator-overview"),
    };

    this.form = document.querySelector('[data-testid="create-form"]');
    this.input = document.querySelector("#todo-title");
    this.list = document.querySelector('[data-testid="todo-list"]');
    this.emptyState = document.querySelector('[data-testid="empty-state"]');
    this.errorBanner = document.querySelector('[data-testid="error-banner"]');
    this.gatewayStatus = document.querySelector('[data-testid="gateway-status"]');
    this.policyIndicator = document.querySelector('[data-testid="policy-indicator"]');
    this.networkPath = document.querySelector('[data-testid="network-path"]');
    this.apiCallLog = document.querySelector('[data-testid="api-call-log"]');
    this.apiCallEmpty = document.querySelector('[data-testid="api-call-empty"]');
    this.dashboardLink = document.querySelector('[data-testid="observability-dashboard-link"]');
    this.grafanaHomeLink = document.querySelector('[data-testid="observability-home-link"]');
    this.networkHops = this.buildNetworkHops();
    this.todos = [];
    this.apiCalls = [];
    this.busy = false;
  }

  async start() {
    this.form.addEventListener("submit", (event) => {
      event.preventDefault();
      void this.handleCreate();
    });

    this.hydrateObservabilityLinks();
    this.renderNetworkPath();
    this.renderApiCalls();
    await this.refresh();
  }

  async refresh() {
    this.setBusy(true);
    this.setError("");

    try {
      await this.checkHealth();
      this.todos = await this.fetchTodos();
      this.render();
    } catch (error) {
      this.setError(this.messageFor(error));
      this.gatewayStatus.textContent = "Gateway error";
    } finally {
      this.setBusy(false);
    }
  }

  async checkHealth() {
    const response = await this.request("/api/health");
    if (!response.ok) {
      throw await this.errorFromResponse(response, "Unable to reach the APIM-backed health endpoint.");
    }

    this.gatewayStatus.textContent = "Connected via APIM";
    this.updatePolicyIndicator(response);
  }

  async fetchTodos() {
    const response = await this.request("/api/todos");
    if (!response.ok) {
      throw await this.errorFromResponse(response, "Unable to load todos through APIM.");
    }

    this.updatePolicyIndicator(response);
    const payload = await response.json();
    return payload.items;
  }

  async handleCreate() {
    const title = this.input.value.trim();
    if (!title || this.busy) {
      return;
    }

    this.setBusy(true);
    this.setError("");

    try {
      const response = await this.request("/api/todos", {
        method: "POST",
        body: JSON.stringify({ title }),
      });

      if (!response.ok) {
        throw await this.errorFromResponse(response, "Unable to create the todo through APIM.");
      }

      this.updatePolicyIndicator(response);
      this.input.value = "";
      this.todos.unshift(await response.json());
      this.render();
    } catch (error) {
      this.setError(this.messageFor(error));
    } finally {
      this.setBusy(false);
    }
  }

  async toggleTodo(todo) {
    if (this.busy) {
      return;
    }

    this.setBusy(true);
    this.setError("");

    try {
      const response = await this.request(`/api/todos/${todo.id}`, {
        method: "PATCH",
        body: JSON.stringify({ completed: !todo.completed }),
      });

      if (!response.ok) {
        throw await this.errorFromResponse(response, "Unable to update the todo through APIM.");
      }

      const updated = await response.json();
      this.updatePolicyIndicator(response);
      this.todos = this.todos.map((item) => (item.id === updated.id ? updated : item));
      this.render();
    } catch (error) {
      this.setError(this.messageFor(error));
    } finally {
      this.setBusy(false);
    }
  }

  async request(path, init = {}) {
    const headers = new Headers(init.headers || {});
    const method = (init.method || "GET").toUpperCase();
    const requestUrl = this.joinUrl(this.config.API_BASE_URL, path);
    const requestTime = new Date().toISOString();
    const startedAt = performance.now();
    const requestBody = this.summarizeBody(init.body);

    headers.set("Accept", "application/json");
    if (init.body) {
      headers.set("Content-Type", "application/json");
    }
    if (this.config.APIM_SUBSCRIPTION_KEY) {
      headers.set("Ocp-Apim-Subscription-Key", this.config.APIM_SUBSCRIPTION_KEY);
    }

    try {
      const response = await fetch(requestUrl, {
        ...init,
        headers,
      });

      this.recordApiCall({
        method,
        path,
        requestUrl,
        upstreamPath: this.toUpstreamPath(path),
        requestTime,
        responseTime: new Date().toISOString(),
        durationMs: Math.round(performance.now() - startedAt),
        statusLabel: String(response.status),
        requestBody,
        gatewayMarker: response.headers.get("x-apim-simulator") || undefined,
        correlationId: response.headers.get("x-correlation-id") || undefined,
        policyHeader: response.headers.get("x-todo-demo-policy") || undefined,
      });

      return response;
    } catch (error) {
      this.recordApiCall({
        method,
        path,
        requestUrl,
        upstreamPath: this.toUpstreamPath(path),
        requestTime,
        responseTime: new Date().toISOString(),
        durationMs: Math.round(performance.now() - startedAt),
        statusLabel: "network-error",
        requestBody,
        errorMessage: this.messageFor(error),
      });
      throw error;
    }
  }

  render() {
    this.list.innerHTML = "";

    if (this.todos.length === 0) {
      this.emptyState.hidden = false;
      return;
    }

    this.emptyState.hidden = true;

    for (const todo of this.todos) {
      const item = document.createElement("li");
      item.className = todo.completed ? "todo-item is-complete" : "todo-item";
      item.dataset.testid = "todo-item";

      const button = document.createElement("button");
      button.type = "button";
      button.className = "todo-toggle";
      button.setAttribute("aria-pressed", String(todo.completed));
      button.setAttribute("data-testid", `toggle-${todo.id}`);
      button.addEventListener("click", () => {
        void this.toggleTodo(todo);
      });

      const badge = document.createElement("span");
      badge.className = "todo-check";
      badge.textContent = todo.completed ? "Done" : "Open";

      const body = document.createElement("span");
      body.className = "todo-body";
      body.textContent = todo.title;

      button.append(badge, body);
      item.appendChild(button);
      this.list.appendChild(item);
    }
  }

  renderNetworkPath() {
    this.networkPath.innerHTML = "";

    for (const [index, hop] of this.networkHops.entries()) {
      const item = document.createElement("li");
      item.className = "hop-item";

      const indexPill = document.createElement("span");
      indexPill.className = "hop-index";
      indexPill.textContent = String(index + 1).padStart(2, "0");

      const copy = document.createElement("div");
      copy.className = "hop-copy";

      const label = document.createElement("strong");
      label.textContent = hop.label;

      const detail = document.createElement("p");
      detail.className = "hop-detail";
      detail.textContent = hop.detail;

      const role = document.createElement("p");
      role.className = "hop-role";
      role.textContent = hop.role;

      copy.append(label, detail, role);
      item.append(indexPill, copy);
      this.networkPath.appendChild(item);
    }
  }

  hydrateObservabilityLinks() {
    this.dashboardLink.href = this.config.OBSERVABILITY_DASHBOARD_URL;
    this.grafanaHomeLink.href = this.config.GRAFANA_BASE_URL;
  }

  renderApiCalls() {
    this.apiCallLog.innerHTML = "";

    if (this.apiCalls.length === 0) {
      this.apiCallEmpty.hidden = false;
      return;
    }

    this.apiCallEmpty.hidden = true;

    for (const entry of this.apiCalls) {
      const card = document.createElement("article");
      card.className = "call-entry";
      card.setAttribute("data-testid", "api-call-entry");

      const top = document.createElement("div");
      top.className = "call-entry-top";

      const method = document.createElement("span");
      method.className = "call-method";
      method.textContent = entry.method;

      const requestUrl = document.createElement("code");
      requestUrl.className = "call-url";
      requestUrl.textContent = entry.requestUrl;

      const status = document.createElement("span");
      status.className = "call-status";
      status.textContent = `${entry.statusLabel} in ${entry.durationMs}ms`;

      top.append(method, requestUrl, status);

      const route = document.createElement("p");
      route.className = "call-route";
      route.textContent = `Route /api -> upstream /api, backend receives ${entry.upstreamPath}`;

      const timing = document.createElement("p");
      timing.className = "call-meta";
      timing.textContent = `${entry.requestTime} -> ${entry.responseTime}`;

      const proofs = document.createElement("div");
      proofs.className = "call-proof-list";
      proofs.append(
        this.createProofChip("Gateway", entry.gatewayMarker || "not exposed", !entry.gatewayMarker),
        this.createProofChip("Policy", entry.policyHeader || "not observed", !entry.policyHeader),
      );
      if (entry.correlationId) {
        proofs.append(this.createProofChip("Correlation", entry.correlationId));
      }

      card.append(top, route, timing, proofs);

      if (entry.requestBody) {
        const body = document.createElement("p");
        body.className = "call-body";

        const label = document.createElement("span");
        label.textContent = "Payload ";

        const value = document.createElement("code");
        value.textContent = entry.requestBody;

        body.append(label, value);
        card.appendChild(body);
      }

      if (entry.errorMessage) {
        const error = document.createElement("p");
        error.className = "call-error";
        error.textContent = entry.errorMessage;
        card.appendChild(error);
      }

      this.apiCallLog.appendChild(card);
    }
  }

  setBusy(nextBusy) {
    this.busy = nextBusy;
    this.form.toggleAttribute("aria-busy", nextBusy);
    this.input.disabled = nextBusy;
    const submit = this.form.querySelector("button[type='submit']");
    submit.disabled = nextBusy;
  }

  setError(message) {
    if (!message) {
      this.errorBanner.hidden = true;
      this.errorBanner.textContent = "";
      return;
    }

    this.errorBanner.hidden = false;
    this.errorBanner.textContent = message;
  }

  messageFor(error) {
    if (error instanceof Error) {
      return error.message;
    }
    return "The APIM-backed request failed.";
  }

  updatePolicyIndicator(response) {
    const policyMarker = response.headers.get("x-todo-demo-policy");
    if (policyMarker) {
      this.policyIndicator.textContent = `APIM policy header detected: ${policyMarker}`;
      return;
    }

    this.policyIndicator.textContent = "APIM policy header not yet observed";
  }

  async errorFromResponse(response, fallback) {
    try {
      const payload = await response.json();
      if (payload.detail) {
        return new Error(payload.detail);
      }
    } catch {
      // Ignore JSON parsing errors and fall through to the fallback text.
    }

    return new Error(fallback);
  }

  buildNetworkHops() {
    return [
      {
        label: "Browser",
        detail: window.location.origin,
        role: "User actions trigger fetch calls from the todo UI.",
      },
      {
        label: "Static frontend",
        detail: `${window.location.origin}/`,
        role: "HTML, CSS, vanilla JS, and the runtime-config bootstrap are served by nginx.",
      },
      {
        label: "APIM simulator",
        detail: this.joinUrl(this.config.API_BASE_URL, "/api"),
        role: "Subscription-protected ingress that applies the outbound demo policy.",
      },
      {
        label: "FastAPI todo API",
        detail: "Configured upstream route /api -> /api",
        role: "Internal backend target. The browser never calls it directly.",
      },
    ];
  }

  recordApiCall(entry) {
    this.apiCalls = [entry, ...this.apiCalls].slice(0, 12);
    this.renderApiCalls();
  }

  createProofChip(label, value, muted = false) {
    const chip = document.createElement("span");
    chip.className = muted ? "call-proof is-muted" : "call-proof";
    chip.textContent = `${label}: ${value}`;
    return chip;
  }

  summarizeBody(body) {
    if (typeof body !== "string") {
      return undefined;
    }

    if (body.length <= 96) {
      return body;
    }

    return `${body.slice(0, 93)}...`;
  }

  toUpstreamPath(path) {
    return path.startsWith("/api") ? path : `/api${path}`;
  }

  joinUrl(base, path) {
    if (!base) {
      return path;
    }

    const normalizedBase = base.endsWith("/") ? base.slice(0, -1) : base;
    const normalizedPath = path.startsWith("/") ? path : `/${path}`;
    return `${normalizedBase}${normalizedPath}`;
  }
}

async function bootTodoApp() {
  const app = new TodoFrontendApp();
  await app.start();
}

void bootTodoApp();
