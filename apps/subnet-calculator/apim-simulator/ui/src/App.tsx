import { FormEvent, startTransition, useEffect, useState } from "react";

type PolicyScope = {
  scope_type: string;
  scope_name: string;
};

type OperationSummary = {
  id: string;
  name: string;
  method: string;
  url_template: string;
  policy_scope: PolicyScope;
};

type ApiSummary = {
  id: string;
  name: string;
  path: string;
  upstream_base_url: string;
  products: string[];
  policy_scope: PolicyScope;
  operations: OperationSummary[];
};

type RouteSummary = {
  name: string;
  path_prefix: string;
  methods: string[] | null;
  upstream_base_url: string;
  upstream_path_prefix: string;
  product: string | null;
  products: string[];
  policy_scope?: PolicyScope;
};

type ProductSummary = {
  id: string;
  name: string;
  description?: string | null;
  require_subscription: boolean;
};

type SubscriptionSummary = {
  id: string;
  name: string;
  state: string;
  products: string[];
  keys: {
    primary: string;
    secondary: string;
  };
};

type BackendSummary = {
  id: string;
  url: string;
  description?: string | null;
  auth_type: string;
};

type SummaryPayload = {
  gateway_policy_scope: PolicyScope;
  apis: ApiSummary[];
  routes: RouteSummary[];
  products: ProductSummary[];
  subscriptions: SubscriptionSummary[];
  backends: BackendSummary[];
};

type TraceItem = {
  trace_id: string;
  created_at: string;
  route: string;
  status: number;
  correlation_id: string;
  incoming_host: string;
  forwarded_host: string;
  forwarded_proto: string;
  client_ip: string;
  upstream_url: string | null;
  [key: string]: unknown;
};

type ReplayResult = {
  response: {
    status_code: number;
    headers: Record<string, string>;
    body_text: string | null;
    body_base64: string | null;
  };
  trace_id: string | null;
  trace: TraceItem | null;
};

const STORAGE_KEY = "apim-console-settings";

const defaultHeaders = `{
  "x-apim-trace": "true"
}`;

function scopeId(scope: PolicyScope): string {
  return `${scope.scope_type}:${scope.scope_name}`;
}

function flattenPolicyScopes(summary: SummaryPayload | null): PolicyScope[] {
  if (!summary) {
    return [];
  }

  const scopes: PolicyScope[] = [summary.gateway_policy_scope];

  for (const api of summary.apis) {
    scopes.push(api.policy_scope);
    for (const operation of api.operations) {
      scopes.push(operation.policy_scope);
    }
  }

  for (const route of summary.routes) {
    if (route.policy_scope) {
      scopes.push(route.policy_scope);
    }
  }

  return scopes;
}

function prettyJson(value: unknown): string {
  return JSON.stringify(value, null, 2);
}

function App() {
  const storedSettings = (() => {
    try {
      return JSON.parse(window.localStorage.getItem(STORAGE_KEY) ?? "{}");
    } catch {
      return {};
    }
  })() as {
    baseUrl?: string;
    tenantKey?: string;
  };

  const [baseUrl, setBaseUrl] = useState(storedSettings.baseUrl ?? "http://localhost:8000");
  const [tenantKey, setTenantKey] = useState(storedSettings.tenantKey ?? "");
  const [summary, setSummary] = useState<SummaryPayload | null>(null);
  const [traces, setTraces] = useState<TraceItem[]>([]);
  const [selectedTraceId, setSelectedTraceId] = useState<string>("");
  const [selectedScopeId, setSelectedScopeId] = useState<string>("");
  const [policyXml, setPolicyXml] = useState("");
  const [policyMessage, setPolicyMessage] = useState("");
  const [replayMethod, setReplayMethod] = useState("GET");
  const [replayPath, setReplayPath] = useState("/api/health");
  const [replayHeaders, setReplayHeaders] = useState(defaultHeaders);
  const [replayBody, setReplayBody] = useState("");
  const [replayResult, setReplayResult] = useState<ReplayResult | null>(null);
  const [statusMessage, setStatusMessage] = useState("Connect to the simulator to load the console.");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify({ baseUrl, tenantKey }));
  }, [baseUrl, tenantKey]);

  async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
    const headers = new Headers(init?.headers);
    headers.set("X-Apim-Tenant-Key", tenantKey);
    if (init?.body && !headers.has("Content-Type")) {
      headers.set("Content-Type", "application/json");
    }

    const response = await fetch(`${baseUrl}${path}`, {
      ...init,
      headers,
    });

    if (!response.ok) {
      const text = await response.text();
      throw new Error(`${response.status} ${response.statusText}: ${text}`);
    }

    return (await response.json()) as T;
  }

  async function loadPolicy(scope: PolicyScope) {
    const policy = await apiFetch<{ xml: string }>(
      `/apim/management/policies/${scope.scope_type}/${encodeURIComponent(scope.scope_name)}`,
    );
    startTransition(() => {
      setSelectedScopeId(scopeId(scope));
      setPolicyXml(policy.xml);
      setPolicyMessage(`Loaded ${scope.scope_type} policy for ${scope.scope_name}.`);
    });
  }

  async function refreshDashboard(preferredScope?: string) {
    if (!tenantKey.trim()) {
      setStatusMessage("Tenant key is required for management access.");
      return;
    }

    setBusy(true);
    setStatusMessage("Refreshing summary, policies, and traces.");

    try {
      const [summaryPayload, tracesPayload] = await Promise.all([
        apiFetch<SummaryPayload>("/apim/management/summary"),
        apiFetch<{ items: TraceItem[] }>("/apim/management/traces"),
      ]);

      const scopes = flattenPolicyScopes(summaryPayload);
      const nextScope =
        scopes.find((scope) => scopeId(scope) === preferredScope) ??
        scopes.find((scope) => scopeId(scope) === selectedScopeId) ??
        scopes[0];

      startTransition(() => {
        setSummary(summaryPayload);
        setTraces(tracesPayload.items);
        if (!selectedTraceId && tracesPayload.items[0]) {
          setSelectedTraceId(tracesPayload.items[0].trace_id);
        }
      });

      if (nextScope) {
        await loadPolicy(nextScope);
      }

      setStatusMessage("Console is in sync with the simulator.");
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : "Unable to refresh the console.");
    } finally {
      setBusy(false);
    }
  }

  async function savePolicy(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const scopes = flattenPolicyScopes(summary);
    const currentScope = scopes.find((scope) => scopeId(scope) === selectedScopeId);
    if (!currentScope) {
      setPolicyMessage("No policy scope is selected.");
      return;
    }

    setBusy(true);
    setPolicyMessage(`Saving ${currentScope.scope_type} policy.`);

    try {
      await apiFetch(`/apim/management/policies/${currentScope.scope_type}/${encodeURIComponent(currentScope.scope_name)}`, {
        method: "PUT",
        body: JSON.stringify({ xml: policyXml }),
      });
      setPolicyMessage(`Saved ${currentScope.scope_type} policy for ${currentScope.scope_name}.`);
    } catch (error) {
      setPolicyMessage(error instanceof Error ? error.message : "Policy update failed.");
    } finally {
      setBusy(false);
    }
  }

  async function rotateKey(subscriptionId: string, key: "primary" | "secondary") {
    setBusy(true);
    setStatusMessage(`Rotating ${key} key for ${subscriptionId}.`);
    try {
      await apiFetch(`/apim/management/subscriptions/${subscriptionId}/rotate?key=${key}`, {
        method: "POST",
      });
      await refreshDashboard(selectedScopeId);
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : "Unable to rotate key.");
      setBusy(false);
    }
  }

  async function runReplay(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setStatusMessage("Executing replay through the simulator.");

    try {
      const replayPayload = await apiFetch<ReplayResult>("/apim/management/replay", {
        method: "POST",
        body: JSON.stringify({
          method: replayMethod,
          path: replayPath,
          headers: JSON.parse(replayHeaders || "{}"),
          body_text: replayBody || undefined,
        }),
      });

      startTransition(() => {
        setReplayResult(replayPayload);
        if (replayPayload.trace) {
          setSelectedTraceId(replayPayload.trace.trace_id);
          setTraces((current) => {
            const withoutSelected = current.filter((trace) => trace.trace_id !== replayPayload.trace?.trace_id);
            return replayPayload.trace ? [replayPayload.trace, ...withoutSelected] : current;
          });
        }
      });
      setStatusMessage("Replay completed.");
    } catch (error) {
      setStatusMessage(error instanceof Error ? error.message : "Replay failed.");
    } finally {
      setBusy(false);
    }
  }

  const scopes = flattenPolicyScopes(summary);
  const selectedTrace = traces.find((trace) => trace.trace_id === selectedTraceId) ?? traces[0] ?? null;

  return (
    <div className="console-shell">
      <div className="ambient ambient-left" />
      <div className="ambient ambient-right" />

      <header className="masthead">
        <div>
          <p className="eyebrow">Operator Console</p>
          <h1>APIM Simulator Control Room</h1>
          <p className="lede">
            Inspect route topology, edit policy XML, replay traffic, and rotate subscription keys without dropping back
            to raw JSON files.
          </p>
        </div>

        <form
          className="connection-panel"
          onSubmit={(event) => {
            event.preventDefault();
            void refreshDashboard();
          }}
        >
          <label>
            <span>Gateway base URL</span>
            <input value={baseUrl} onChange={(event) => setBaseUrl(event.target.value)} />
          </label>
          <label>
            <span>Tenant key</span>
            <input value={tenantKey} onChange={(event) => setTenantKey(event.target.value)} />
          </label>
          <button type="submit" disabled={busy}>
            {busy ? "Working..." : "Connect"}
          </button>
        </form>
      </header>

      <section className="status-bar">
        <span>{statusMessage}</span>
        <button type="button" onClick={() => void refreshDashboard(selectedScopeId)} disabled={busy}>
          Refresh
        </button>
      </section>

      <main className="console-grid">
        <section className="panel overview-panel">
          <div className="panel-head">
            <h2>Surface</h2>
            <p>Loaded APIs, routes, products, and backends.</p>
          </div>

          <div className="metric-ribbon">
            <article>
              <strong>{summary?.apis.length ?? 0}</strong>
              <span>APIs</span>
            </article>
            <article>
              <strong>{summary?.routes.length ?? 0}</strong>
              <span>Routes</span>
            </article>
            <article>
              <strong>{summary?.products.length ?? 0}</strong>
              <span>Products</span>
            </article>
            <article>
              <strong>{summary?.subscriptions.length ?? 0}</strong>
              <span>Subscriptions</span>
            </article>
          </div>

          <div className="surface-columns">
            <div>
              <h3>APIs</h3>
              <ul className="summary-list">
                {summary?.apis.map((api) => (
                  <li key={api.id}>
                    <strong>{api.name}</strong>
                    <span>/{api.path}</span>
                    <small>{api.operations.length} operations</small>
                  </li>
                )) ?? <li className="empty">No APIs loaded.</li>}
              </ul>
            </div>

            <div>
              <h3>Routes</h3>
              <ul className="summary-list">
                {summary?.routes.map((route) => (
                  <li key={route.name}>
                    <strong>{route.name}</strong>
                    <span>{route.path_prefix}</span>
                    <small>{route.upstream_base_url}</small>
                  </li>
                )) ?? <li className="empty">No routes loaded.</li>}
              </ul>
            </div>

            <div>
              <h3>Products</h3>
              <ul className="summary-list">
                {summary?.products.map((product) => (
                  <li key={product.id}>
                    <strong>{product.id}</strong>
                    <span>{product.name}</span>
                    <small>{product.require_subscription ? "Subscription required" : "Open access"}</small>
                  </li>
                )) ?? <li className="empty">No products loaded.</li>}
              </ul>
            </div>

            <div>
              <h3>Backends</h3>
              <ul className="summary-list">
                {summary?.backends.map((backend) => (
                  <li key={backend.id}>
                    <strong>{backend.id}</strong>
                    <span>{backend.url}</span>
                    <small>{backend.auth_type}</small>
                  </li>
                )) ?? <li className="empty">No backends loaded.</li>}
              </ul>
            </div>
          </div>
        </section>

        <section className="panel policy-panel">
          <div className="panel-head">
            <h2>Policy Editor</h2>
            <p>Edit raw XML at gateway, API, operation, or route scope.</p>
          </div>

          <form className="policy-form" onSubmit={(event) => void savePolicy(event)}>
            <label>
              <span>Scope</span>
              <select
                value={selectedScopeId}
                onChange={(event) => {
                  const scope = scopes.find((item) => scopeId(item) === event.target.value);
                  if (scope) {
                    void loadPolicy(scope);
                  }
                }}
              >
                {scopes.map((scope) => (
                  <option key={scopeId(scope)} value={scopeId(scope)}>
                    {scope.scope_type} / {scope.scope_name}
                  </option>
                ))}
              </select>
            </label>

            <label className="policy-editor">
              <span>XML</span>
              <textarea value={policyXml} onChange={(event) => setPolicyXml(event.target.value)} rows={18} />
            </label>

            <div className="policy-actions">
              <button type="submit" disabled={busy || !selectedScopeId}>
                Save Policy
              </button>
              <span>{policyMessage}</span>
            </div>
          </form>
        </section>

        <section className="panel replay-panel">
          <div className="panel-head">
            <h2>Replay Lab</h2>
            <p>Execute a replayable request through the gateway and inspect trace metadata.</p>
          </div>

          <form className="replay-form" onSubmit={(event) => void runReplay(event)}>
            <div className="replay-row">
              <label>
                <span>Method</span>
                <select value={replayMethod} onChange={(event) => setReplayMethod(event.target.value)}>
                  {["GET", "POST", "PUT", "PATCH", "DELETE"].map((method) => (
                    <option key={method} value={method}>
                      {method}
                    </option>
                  ))}
                </select>
              </label>

              <label className="path-field">
                <span>Path</span>
                <input value={replayPath} onChange={(event) => setReplayPath(event.target.value)} />
              </label>
            </div>

            <label>
              <span>Headers (JSON)</span>
              <textarea value={replayHeaders} onChange={(event) => setReplayHeaders(event.target.value)} rows={7} />
            </label>

            <label>
              <span>Body</span>
              <textarea value={replayBody} onChange={(event) => setReplayBody(event.target.value)} rows={7} />
            </label>

            <button type="submit" disabled={busy}>
              Run Replay
            </button>
          </form>

          <div className="replay-output">
            <h3>Replay Result</h3>
            <pre>{replayResult ? prettyJson(replayResult) : "Run a replay to inspect the response and trace metadata."}</pre>
          </div>
        </section>

        <section className="panel trace-panel">
          <div className="panel-head">
            <h2>Trace Ledger</h2>
            <p>Recent traces, forwarded headers, and selected trace details.</p>
          </div>

          <div className="trace-layout">
            <ul className="trace-list">
              {traces.map((trace) => (
                <li key={trace.trace_id}>
                  <button
                    type="button"
                    className={selectedTrace?.trace_id === trace.trace_id ? "trace-chip active" : "trace-chip"}
                    onClick={() => setSelectedTraceId(trace.trace_id)}
                  >
                    <strong>{trace.route}</strong>
                    <span>{trace.status}</span>
                    <small>{trace.forwarded_proto || "direct"}</small>
                  </button>
                </li>
              ))}
              {traces.length === 0 ? <li className="empty">No traces captured yet.</li> : null}
            </ul>

            <pre className="trace-detail">
              {selectedTrace ? prettyJson(selectedTrace) : "Select a trace to inspect its metadata."}
            </pre>
          </div>
        </section>

        <section className="panel subscription-panel">
          <div className="panel-head">
            <h2>Subscriptions</h2>
            <p>Inspect keys and rotate primary or secondary values without leaving the console.</p>
          </div>

          <div className="subscription-grid">
            {summary?.subscriptions.map((subscription) => (
              <article key={subscription.id} className="subscription-card">
                <header>
                  <div>
                    <h3>{subscription.name}</h3>
                    <p>{subscription.id}</p>
                  </div>
                  <span className="state-pill">{subscription.state}</span>
                </header>

                <dl>
                  <div>
                    <dt>Primary</dt>
                    <dd>{subscription.keys.primary}</dd>
                  </div>
                  <div>
                    <dt>Secondary</dt>
                    <dd>{subscription.keys.secondary}</dd>
                  </div>
                  <div>
                    <dt>Products</dt>
                    <dd>{subscription.products.join(", ") || "None"}</dd>
                  </div>
                </dl>

                <div className="subscription-actions">
                  <button type="button" onClick={() => void rotateKey(subscription.id, "primary")} disabled={busy}>
                    Rotate Primary
                  </button>
                  <button type="button" onClick={() => void rotateKey(subscription.id, "secondary")} disabled={busy}>
                    Rotate Secondary
                  </button>
                </div>
              </article>
            )) ?? <p className="empty">No subscriptions loaded.</p>}
          </div>
        </section>
      </main>
    </div>
  );
}

export default App;
