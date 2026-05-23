package app

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) Do(r *http.Request) (*http.Response, error) {
	return f(r)
}

func TestHealthMetricsAndFrontendAreLightweight(t *testing.T) {
	srv := NewServer(Config{Role: "trace-chat", LangfuseHost: "http://langfuse", OpenAIBaseURL: "http://llm/v1", OpenAIModel: "local"}, nil)

	for _, target := range []string{"/", "/runtime-config.js", "/metrics"} {
		req := httptest.NewRequest(http.MethodGet, target, nil)
		rec := httptest.NewRecorder()
		srv.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s returned %d: %s", target, rec.Code, rec.Body.String())
		}
	}

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("health returned %d: %s", rec.Code, rec.Body.String())
	}
	var health map[string]any
	if err := json.NewDecoder(rec.Body).Decode(&health); err != nil {
		t.Fatalf("health did not return JSON: %v", err)
	}
	if got := health["dependency_footprint"]; got != "go-plus-shared-idpauth" {
		t.Fatalf("dependency_footprint=%v, want go-plus-shared-idpauth", got)
	}
	if got := health["frontend_dependency_footprint"]; got != "vanilla" {
		t.Fatalf("frontend_dependency_footprint=%v, want vanilla", got)
	}
	if _, ok := health["dependencies"]; ok {
		t.Fatalf("health should use canonical dependency_footprint fields, got legacy dependencies in %v", health)
	}

	req = httptest.NewRequest(http.MethodGet, "/", nil)
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	for _, text := range []string{"Langfuse Trace Chat", "/api/run", "traceId", "score-list", "/app-shell.css", "/app-shell.js"} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("frontend missing %q: %s", text, rec.Body.String())
		}
	}

	req = httptest.NewRequest(http.MethodGet, "/metrics", nil)
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if got := rec.Header().Get("Content-Type"); got != "text/plain; version=0.0.4; charset=utf-8" {
		t.Fatalf("metrics Content-Type=%q", got)
	}
	if got := rec.Header().Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("metrics X-Content-Type-Options=%q", got)
	}
	for _, text := range []string{"langfuse_demo_runs_total", "langfuse_demo_llm_calls_total", `role="trace-chat"`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("metrics missing %q: %s", text, rec.Body.String())
		}
	}
}

func TestServerUsesSharedHTTPJSONHelpersDirectly(t *testing.T) {
	source, err := os.ReadFile("server.go")
	if err != nil {
		t.Fatal(err)
	}
	text := string(source)
	for _, required := range []string{
		"apphttp.WriteJSON(w, http.StatusOK",
		"apphttp.DecodeJSONError(w, r, &req",
		"apphttp.FirstNonEmpty(",
	} {
		if !strings.Contains(text, required) {
			t.Fatalf("server.go missing shared HTTP helper call %q", required)
		}
	}
	for _, forbidden := range []string{
		"func writeJSON(",
		"func decodeJSON(",
		"func firstNonEmpty(",
	} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("server.go should not keep pass-through helper %q", forbidden)
		}
	}
}

func TestRunDemoRejectsInvalidJSONWithCanonicalErrorPayload(t *testing.T) {
	srv := NewServer(Config{Role: "trace-chat"}, nil)

	req := httptest.NewRequest(http.MethodPost, "/api/run", strings.NewReader(`{"prompt":`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("invalid JSON returned %d: %s", rec.Code, rec.Body.String())
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"invalid JSON body"}` {
		t.Fatalf("invalid JSON body = %s", rec.Body.String())
	}
}

func TestFrontendFaviconIsHandled(t *testing.T) {
	srv := NewServer(Config{Role: "trace-chat", LangfuseHost: "http://langfuse", OpenAIBaseURL: "http://llm/v1", OpenAIModel: "local"}, nil)

	req := httptest.NewRequest(http.MethodGet, "/favicon.ico", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("favicon should return an icon response: %d", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); got != "image/svg+xml" {
		t.Fatalf("favicon Content-Type=%q", got)
	}
}

func TestFrontendStaticAssetsUseSharedMethodContract(t *testing.T) {
	srv := NewServer(Config{Role: "trace-chat", LangfuseHost: "http://langfuse", OpenAIBaseURL: "http://llm/v1", OpenAIModel: "local"}, nil)

	req := httptest.NewRequest(http.MethodHead, "/", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("HEAD frontend returned %d: %s", rec.Code, rec.Body.String())
	}
	if rec.Body.Len() != 0 {
		t.Fatalf("HEAD frontend returned body: %s", rec.Body.String())
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("HEAD frontend Cache-Control=%q", got)
	}
	if got := rec.Header().Get("Content-Type"); !strings.Contains(got, "text/html") {
		t.Fatalf("HEAD frontend Content-Type=%q", got)
	}

	req = httptest.NewRequest(http.MethodPost, "/style.css", nil)
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("POST static asset returned %d: %s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Allow"); got != "GET, HEAD" {
		t.Fatalf("POST static asset Allow=%q", got)
	}
}

func TestFrontendUsesSharedAuthShellControls(t *testing.T) {
	srv := NewServer(Config{Role: "trace-chat", LangfuseHost: "http://langfuse", OpenAIBaseURL: "http://llm/v1", OpenAIModel: "local"}, nil)

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("frontend returned %d: %s", rec.Code, rec.Body.String())
	}
	html := rec.Body.String()
	for _, text := range []string{`class="skip-link" href="#main"`, `<main id="main" tabindex="-1">`, `class="header-actions"`, `id="auth-state"`, `class="auth-state"`, `id="logout-btn"`, `>Sign Out<`, `id="theme-switcher"`, `class="theme-toggle"`, `/oauth2/sign_out?rd=/signed-out.html`, `/idpauth.js`, `/app-shell.css`, `/app-shell.js`, `class="app-panel results" aria-live="polite" aria-labelledby="results-heading"`, `<h2 id="results-heading">Run Results</h2>`} {
		if !strings.Contains(html, text) {
			t.Fatalf("frontend missing auth shell control %q: %s", text, html)
		}
	}
}

func TestSharedAppShellBundleIsServed(t *testing.T) {
	srv := NewServer(Config{Role: "trace-chat", LangfuseHost: "http://langfuse", OpenAIBaseURL: "http://llm/v1", OpenAIModel: "local"}, nil)

	req := httptest.NewRequest(http.MethodGet, "/app-shell.js", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("app-shell bundle returned %d: %s", rec.Code, rec.Body.String())
	}
	for _, text := range []string{`PlatformAppShell`, `initializeThemeSwitcher`, `pce-theme`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("app-shell bundle missing %q: %s", text, rec.Body.String())
		}
	}

	req = httptest.NewRequest(http.MethodGet, "/app-shell.css", nil)
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("app-shell stylesheet returned %d: %s", rec.Code, rec.Body.String())
	}
	for _, text := range []string{`.header-actions`, `.auth-state`, `.theme-toggle`, `.sign-in-link`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("app-shell stylesheet missing %q: %s", text, rec.Body.String())
		}
	}
}

func TestGatewaySessionPrefersEmailOverOpaqueSubject(t *testing.T) {
	srv := NewServer(Config{Role: "tool-agent", LangfuseHost: "http://langfuse", OpenAIBaseURL: "http://llm/v1", OpenAIModel: "local"}, nil)

	req := httptest.NewRequest(http.MethodGet, "/.auth/me", nil)
	req.Header.Set("X-Forwarded-User", "baa3e24f-39c3-4693-8754-ca65d0842572")
	req.Header.Set("X-Forwarded-Email", "demo@dev.test")
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("gateway session returned %d: %s", rec.Code, rec.Body.String())
	}

	var payload struct {
		ClientPrincipal struct {
			UserDetails string `json:"userDetails"`
			Claims      []struct {
				Type  string `json:"typ"`
				Value string `json:"val"`
			} `json:"claims"`
		} `json:"clientPrincipal"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload.ClientPrincipal.UserDetails != "demo@dev.test" {
		t.Fatalf("expected display identity to use email, got %q in %s", payload.ClientPrincipal.UserDetails, rec.Body.String())
	}
}

func TestFrontendUsesSharedGatewayIdentityNormalization(t *testing.T) {
	srv := NewServer(Config{Role: "trace-chat", LangfuseHost: "http://langfuse", OpenAIBaseURL: "http://llm/v1", OpenAIModel: "local"}, nil)

	req := httptest.NewRequest(http.MethodGet, "/app.js", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("app.js returned %d: %s", rec.Code, rec.Body.String())
	}
	script := rec.Body.String()
	for _, text := range []string{`PlatformIdpAuth`, `PlatformAppShell`, `readRuntimeConfig("LANGFUSE_DEMO_CONFIG")`, `initializeGatewayAuthState(authState, logoutButton`, `path: "/.auth/me"`, `ignoreErrors: true`, `bindGatewayLogout(logoutButton)`, `initializeThemeSwitcher()`, `requireElement`, `formElement`, `formElement("run-form")`, `postJSON`, `fetchText`, `withButtonBusy`, `withSubmitterBusy`, `setText`, `renderStatusInto`, `renderListInto`, `errorMessage(`, `not reported`} {
		if !strings.Contains(script, text) {
			t.Fatalf("app.js missing shared gateway identity helper %q: %s", text, script)
		}
	}
	if !strings.Contains(script, "setText(\n\t\t\tmetricsOutput,") {
		t.Fatalf("app.js should route metrics output through the shared text helper: %s", script)
	}
	for _, text := range []string{`window.LANGFUSE_DEMO_CONFIG || {}`, `setText(runStatus`, `error instanceof Error ? error.message : String(error)`, `fetchGatewaySession("/.auth/me")`, `writeGatewayAuthState(authState, logoutButton, session)`, `function normalizeGatewaySession`, `function gatewayDisplayName`, `function readThemeCookie`, `document.cookie`, `pce-theme`, `HTMLFormElement`, `idpAuth?.bindGatewayLogout`, `const idpAuth = window.PlatformIdpAuth`, `const appShell = window.PlatformAppShell`, `function setText`, `function renderList`, `await response.json()`, `parseJSONResponse(response)`} {
		if strings.Contains(script, text) {
			t.Fatalf("app.js should consume shared shell bundles, but still defines %q: %s", text, script)
		}
	}
	if strings.Contains(script, `metricsOutput.textContent`) {
		t.Fatalf("app.js should not write metrics output text directly: %s", script)
	}
	if strings.Contains(script, "unk"+"nown") {
		t.Fatalf("app.js should not expose placeholder status labels: %s", script)
	}
}

func TestSharedIdpAuthBundleIsServed(t *testing.T) {
	srv := NewServer(Config{Role: "trace-chat", LangfuseHost: "http://langfuse", OpenAIBaseURL: "http://llm/v1", OpenAIModel: "local"}, nil)

	req := httptest.NewRequest(http.MethodGet, "/idpauth.js", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("idpauth bundle returned %d: %s", rec.Code, rec.Body.String())
	}
	for _, text := range []string{`PlatformIdpAuth`, `normalizeGatewaySession`, `gatewayDisplayName`, `bindGatewayLogout`, `writeGatewayAuthState`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("idpauth bundle missing %q: %s", text, rec.Body.String())
		}
	}
}

func TestFrontendMobileHeaderStacksShellControls(t *testing.T) {
	srv := NewServer(Config{Role: "trace-chat", LangfuseHost: "http://langfuse", OpenAIBaseURL: "http://llm/v1", OpenAIModel: "local"}, nil)

	req := httptest.NewRequest(http.MethodGet, "/app-shell.css", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("app-shell.css returned %d: %s", rec.Code, rec.Body.String())
	}
	for _, text := range []string{`@media (max-width: 720px)`, `flex-direction: column;`, `.header-actions`, `@media (max-width: 520px)`, `flex: 1 1 160px;`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("app-shell.css missing mobile shell rule %q: %s", text, rec.Body.String())
		}
	}
}

func TestFrontendShowsMetricsPanelOnMainView(t *testing.T) {
	srv := NewServer(Config{Role: "trace-chat", LangfuseHost: "http://langfuse", OpenAIBaseURL: "http://llm/v1", OpenAIModel: "local"}, nil)

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("frontend returned %d: %s", rec.Code, rec.Body.String())
	}
	html := rec.Body.String()
	for _, text := range []string{`id="metrics-panel"`, `id="refresh-metrics"`, `id="metrics-output"`, `href="/metrics"`, `Raw Metrics`} {
		if !strings.Contains(html, text) {
			t.Fatalf("frontend missing metrics panel affordance %q: %s", text, html)
		}
	}

	req = httptest.NewRequest(http.MethodGet, "/app.js", nil)
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("app.js returned %d: %s", rec.Code, rec.Body.String())
	}
	script := rec.Body.String()
	for _, text := range []string{`refreshMetrics`, `cfg.metricsEndpoint || "/metrics"`, `requireElement("metrics-output")`} {
		if !strings.Contains(script, text) {
			t.Fatalf("app.js missing metrics panel behavior %q: %s", text, script)
		}
	}
}

func TestRuntimeConfigProvidesDistinctRoleUI(t *testing.T) {
	roles := map[string]string{
		"trace-chat":  "Single prompt",
		"tool-agent":  "Planner",
		"eval-runner": "Eval cases",
	}

	for role, expectedCopy := range roles {
		t.Run(role, func(t *testing.T) {
			srv := NewServer(Config{Role: role, LangfuseHost: "http://langfuse", OpenAIBaseURL: "http://llm/v1", OpenAIModel: "local"}, nil)
			req := httptest.NewRequest(http.MethodGet, "/runtime-config.js", nil)
			rec := httptest.NewRecorder()
			srv.ServeHTTP(rec, req)
			if rec.Code != http.StatusOK {
				t.Fatalf("runtime config returned %d: %s", rec.Code, rec.Body.String())
			}
			body := rec.Body.String()
			for _, text := range []string{`"scenarioCopy"`, `"promptLabel"`, `"actionLabel"`, expectedCopy} {
				if !strings.Contains(body, text) {
					t.Fatalf("%s runtime config missing %q: %s", role, text, body)
				}
			}
		})
	}
}

func TestRuntimeConfigDocumentsLocalOMLXPrerequisite(t *testing.T) {
	srv := NewServer(Config{Role: "tool-agent", LangfuseHost: "http://langfuse", OpenAIBaseURL: "http://agentgateway-ai-gateway.agentgateway-system.svc.cluster.local/v1", OpenAIModel: "auto"}, nil)

	req := httptest.NewRequest(http.MethodGet, "/runtime-config.js", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("runtime config returned %d: %s", rec.Code, rec.Body.String())
	}
	body := rec.Body.String()
	for _, text := range []string{`"llmPrerequisite"`, `http://127.0.0.1:8000/v1`, `host.docker.internal:8000`, `start the oMLX OpenAI-compatible server`} {
		if !strings.Contains(body, text) {
			t.Fatalf("runtime config missing local oMLX prerequisite %q: %s", text, body)
		}
	}

	req = httptest.NewRequest(http.MethodGet, "/", nil)
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if !strings.Contains(rec.Body.String(), `id="prereq-note"`) {
		t.Fatalf("frontend missing prerequisite note mount: %s", rec.Body.String())
	}
}

func TestConfigDefaultsGiveLocalOMLXSufficientTime(t *testing.T) {
	t.Setenv("LLM_TIMEOUT_SECONDS", "")
	t.Setenv("LANGFUSE_TIMEOUT_SECONDS", "")
	t.Setenv("OPENAI_MODEL", "")

	cfg := ConfigFromEnv()
	if cfg.OpenAIModel != "auto" {
		t.Fatalf("default model should be discovered from /v1/models, got %q", cfg.OpenAIModel)
	}
	if cfg.LLMTimeout < 10*time.Second {
		t.Fatalf("local oMLX completions need more than the gateway smoke timeout, got %s", cfg.LLMTimeout)
	}
	if cfg.LangfuseTimeout != 15*time.Second {
		t.Fatalf("Langfuse ingestion timeout should remain tight, got %s", cfg.LangfuseTimeout)
	}
}

func TestConfigNormalizesPublicBaseURL(t *testing.T) {
	t.Setenv("PUBLIC_BASE_URL", "https://langfuse-demos.127.0.0.1.sslip.io///")

	cfg := ConfigFromEnv()
	if cfg.PublicBaseURL != "https://langfuse-demos.127.0.0.1.sslip.io" {
		t.Fatalf("public base URL should not keep trailing slash noise, got %q", cfg.PublicBaseURL)
	}
}

func TestTraceChatCallsLLMAndIngestsTraceGenerationAndScores(t *testing.T) {
	var ingestion map[string][]map[string]any
	client := roundTripFunc(func(r *http.Request) (*http.Response, error) {
		switch {
		case strings.Contains(r.URL.Path, "/chat/completions"):
			return jsonResponse(http.StatusOK, `{"choices":[{"message":{"content":"Langfuse trace response"}}]}`), nil
		case strings.Contains(r.URL.Path, "/api/public/ingestion"):
			raw, _ := io.ReadAll(r.Body)
			if err := json.Unmarshal(raw, &ingestion); err != nil {
				t.Fatal(err)
			}
			user, pass, ok := r.BasicAuth()
			if !ok || user != "pk" || pass != "sk" {
				t.Fatalf("bad Langfuse basic auth")
			}
			return jsonResponse(http.StatusOK, `{"successes":[],"errors":[]}`), nil
		default:
			t.Fatalf("unexpected request: %s", r.URL.String())
			return nil, nil
		}
	})
	srv := NewServer(Config{
		Role:              "trace-chat",
		LangfuseHost:      "http://langfuse",
		LangfusePublicKey: "pk",
		LangfuseSecretKey: "sk",
		OpenAIBaseURL:     "http://llm/v1",
		OpenAIModel:       "local",
	}, client)

	req := httptest.NewRequest(http.MethodPost, "/api/run", strings.NewReader(`{"prompt":"hello"}`))
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("run returned %d: %s", rec.Code, rec.Body.String())
	}
	var response runResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if response.LangfuseStatus != "ok" || response.LLMStatus != "ok" || response.TraceID == "" {
		t.Fatalf("unexpected response: %+v", response)
	}

	types := map[string]int{}
	for _, event := range ingestion["batch"] {
		types[event["type"].(string)]++
	}
	for _, typ := range []string{"trace-create", "generation-create", "score-create"} {
		if types[typ] == 0 {
			t.Fatalf("missing Langfuse event type %s in %#v", typ, ingestion)
		}
	}
}

func TestTraceChatAutoDiscoversOpenAIModel(t *testing.T) {
	var sawModels bool
	client := roundTripFunc(func(r *http.Request) (*http.Response, error) {
		switch {
		case strings.Contains(r.URL.Path, "/models"):
			sawModels = true
			return jsonResponse(http.StatusOK, `{"data":[{"id":"Qwen3.5-9B-MLX-4bit"}]}`), nil
		case strings.Contains(r.URL.Path, "/chat/completions"):
			raw, _ := io.ReadAll(r.Body)
			if !strings.Contains(string(raw), `"model":"Qwen3.5-9B-MLX-4bit"`) {
				t.Fatalf("chat request did not use discovered model: %s", string(raw))
			}
			return jsonResponse(http.StatusOK, `{"choices":[{"message":{"content":"discovered model response"}}]}`), nil
		case strings.Contains(r.URL.Path, "/api/public/ingestion"):
			raw, _ := io.ReadAll(r.Body)
			if !strings.Contains(string(raw), `"model":"Qwen3.5-9B-MLX-4bit"`) {
				t.Fatalf("ingestion did not record discovered model: %s", string(raw))
			}
			return jsonResponse(http.StatusOK, `{"successes":[],"errors":[]}`), nil
		default:
			t.Fatalf("unexpected request: %s", r.URL.String())
			return nil, nil
		}
	})
	srv := NewServer(Config{
		Role:              "trace-chat",
		LangfuseHost:      "http://langfuse",
		LangfusePublicKey: "pk",
		LangfuseSecretKey: "sk",
		OpenAIBaseURL:     "http://llm/v1",
		OpenAIModel:       "auto",
	}, client)

	req := httptest.NewRequest(http.MethodPost, "/api/run", strings.NewReader(`{"prompt":"hello"}`))
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("run returned %d: %s", rec.Code, rec.Body.String())
	}
	if !sawModels {
		t.Fatalf("expected /models discovery request")
	}
	var response runResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if response.LLMStatus != "ok" || response.Steps[0].Detail != "Qwen3.5-9B-MLX-4bit" {
		t.Fatalf("unexpected response after model discovery: %+v", response)
	}
}

func TestToolAgentAndEvalRunnerEmitScoresWhenLLMFails(t *testing.T) {
	for _, role := range []string{"tool-agent", "eval-runner"} {
		t.Run(role, func(t *testing.T) {
			var sawIngestion bool
			client := roundTripFunc(func(r *http.Request) (*http.Response, error) {
				if strings.Contains(r.URL.Path, "/chat/completions") {
					return jsonResponse(http.StatusServiceUnavailable, `{"error":"offline"}`), nil
				}
				if strings.Contains(r.URL.Path, "/api/public/ingestion") {
					sawIngestion = true
					raw, _ := io.ReadAll(r.Body)
					if !strings.Contains(string(raw), "score-create") {
						t.Fatalf("ingestion missing scores: %s", string(raw))
					}
					return jsonResponse(http.StatusOK, `{"successes":[],"errors":[]}`), nil
				}
				t.Fatalf("unexpected request: %s", r.URL.String())
				return nil, nil
			})
			srv := NewServer(Config{
				Role:              role,
				LangfuseHost:      "http://langfuse",
				LangfusePublicKey: "pk",
				LangfuseSecretKey: "sk",
				OpenAIBaseURL:     "http://llm/v1",
				OpenAIModel:       "local",
			}, client)
			req := httptest.NewRequest(http.MethodPost, "/api/run", strings.NewReader(`{"prompt":"evaluate this"}`))
			rec := httptest.NewRecorder()
			srv.ServeHTTP(rec, req)
			if rec.Code != http.StatusOK {
				t.Fatalf("run returned %d: %s", rec.Code, rec.Body.String())
			}
			if !sawIngestion {
				t.Fatalf("expected Langfuse ingestion for %s", role)
			}
			if !strings.Contains(rec.Body.String(), `"scores"`) {
				t.Fatalf("response missing scores: %s", rec.Body.String())
			}
		})
	}
}

func TestToolAgentPresentsDeterministicFallbackWhenLLMUnavailable(t *testing.T) {
	client := roundTripFunc(func(r *http.Request) (*http.Response, error) {
		if strings.Contains(r.URL.Path, "/chat/completions") {
			return jsonResponse(http.StatusServiceUnavailable, `{"error":"offline"}`), nil
		}
		if strings.Contains(r.URL.Path, "/api/public/ingestion") {
			return jsonResponse(http.StatusOK, `{"successes":[],"errors":[]}`), nil
		}
		t.Fatalf("unexpected request: %s", r.URL.String())
		return nil, nil
	})
	srv := NewServer(Config{
		Role:              "tool-agent",
		LangfuseHost:      "http://langfuse",
		LangfusePublicKey: "pk",
		LangfuseSecretKey: "sk",
		OpenAIBaseURL:     "http://llm/v1",
		OpenAIModel:       "local",
	}, client)

	req := httptest.NewRequest(http.MethodPost, "/api/run", strings.NewReader(`{"prompt":"check langfuse wiring"}`))
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("run returned %d: %s", rec.Code, rec.Body.String())
	}
	var response runResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if response.LLMStatus != "deterministic fallback" {
		t.Fatalf("expected clear deterministic fallback status, got %+v", response)
	}
	if strings.Contains(strings.ToLower(response.Answer), "did not return content") {
		t.Fatalf("fallback answer should not expose raw LLM failure: %q", response.Answer)
	}
	for _, step := range response.Steps {
		if (step.Name == "planner" || step.Name == "final-response") && step.Status != "deterministic fallback" {
			t.Fatalf("expected %s to show deterministic fallback status, got %+v", step.Name, step)
		}
	}
}

func TestTraceChatUsesBoundedLLMTimeoutAndStillIngestsFallbackTrace(t *testing.T) {
	var sawIngestion bool
	client := roundTripFunc(func(r *http.Request) (*http.Response, error) {
		if strings.Contains(r.URL.Path, "/chat/completions") {
			<-r.Context().Done()
			return nil, r.Context().Err()
		}
		if strings.Contains(r.URL.Path, "/api/public/ingestion") {
			sawIngestion = true
			return jsonResponse(http.StatusOK, `{"successes":[],"errors":[]}`), nil
		}
		t.Fatalf("unexpected request: %s", r.URL.String())
		return nil, nil
	})
	srv := NewServer(Config{
		Role:              "trace-chat",
		LangfuseHost:      "http://langfuse",
		LangfusePublicKey: "pk",
		LangfuseSecretKey: "sk",
		OpenAIBaseURL:     "http://llm/v1",
		OpenAIModel:       "local",
		LLMTimeout:        10 * time.Millisecond,
		LangfuseTimeout:   time.Second,
	}, client)

	start := time.Now()
	req := httptest.NewRequest(http.MethodPost, "/api/run", strings.NewReader(`{"prompt":"hello"}`))
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if elapsed := time.Since(start); elapsed > 500*time.Millisecond {
		t.Fatalf("run took too long after LLM timeout: %s", elapsed)
	}
	if rec.Code != http.StatusOK {
		t.Fatalf("run returned %d: %s", rec.Code, rec.Body.String())
	}
	if !sawIngestion {
		t.Fatalf("expected fallback trace ingestion after LLM timeout")
	}
	if !strings.Contains(rec.Body.String(), `"llmStatus":"error"`) || !strings.Contains(rec.Body.String(), `"langfuseStatus":"ok"`) {
		t.Fatalf("unexpected timeout response: %s", rec.Body.String())
	}
}

func TestStatusJoinsUseExplicitMissingLabel(t *testing.T) {
	if got := joinStatuses("", " ", ""); got != "not reported" {
		t.Fatalf("empty joined status should be explicit, got %q", got)
	}
	if got := joinAgentStatuses("", ""); got != "not reported" {
		t.Fatalf("empty joined agent status should be explicit, got %q", got)
	}
}

func jsonResponse(status int, body string) *http.Response {
	return &http.Response{
		StatusCode: status,
		Header:     http.Header{"Content-Type": []string{"application/json"}},
		Body:       io.NopCloser(strings.NewReader(body)),
	}
}
