package app

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"platform.local/apphttp"
	"platform.local/idpauth"
)

func TestShellHealthAndFrontendReportSharedDependencyFootprint(t *testing.T) {
	srv := NewServer(Config{Role: "shell", MCPURL: "http://mcp.example/mcp"}, nil)

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
	if rec.Code != http.StatusOK {
		t.Fatalf("frontend returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "<title>ChatGPT Sim</title>") {
		t.Fatalf("frontend title missing: %s", rec.Body.String())
	}
	for _, text := range []string{
		`/app-shell.css`,
		`/app-shell.js`,
		`data-theme="system"`,
		`class="header-actions"`,
		`id="auth-state"`,
		`id="logout-btn"`,
		`>Sign Out<`,
		`id="theme-switcher"`,
		`class="theme-toggle"`,
		`id="network-path"`,
	} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("frontend missing %q: %s", text, rec.Body.String())
		}
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("frontend Cache-Control=%q", got)
	}

	req = httptest.NewRequest(http.MethodGet, "/app-shell.css", nil)
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("shared app shell CSS returned %d: %s", rec.Code, rec.Body.String())
	}
	for _, text := range []string{`.header-actions`, `.auth-state`, `.theme-toggle`, `.sign-in-link`, `min-height: 42px`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("shared app shell CSS missing %q: %s", text, rec.Body.String())
		}
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("shared app shell CSS Cache-Control=%q", got)
	}

	req = httptest.NewRequest(http.MethodGet, "/app-shell.js", nil)
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("shared app shell JS returned %d: %s", rec.Code, rec.Body.String())
	}
	for _, text := range []string{"PlatformAppShell", "initializeThemeSwitcher", "toggleTheme", "pce-theme"} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("shared app shell JS missing %q: %s", text, rec.Body.String())
		}
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("shared app shell JS Cache-Control=%q", got)
	}

	req = httptest.NewRequest(http.MethodGet, "/signed-out.html", nil)
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("signed-out page returned %d: %s", rec.Code, rec.Body.String())
	}
	for _, text := range []string{
		"ChatGPT Sim",
		`/app-shell.css`,
		`/app-shell.js`,
		"Signed out",
		"Sign in now",
		"/.auth/login/sso",
		`id="theme-switcher"`,
		`class="theme-toggle"`,
		"redirect-delay",
		"Redirecting to sign in in 5 seconds",
		"window.PlatformAppShell.initializeSignedOutRedirect()",
	} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("signed-out page missing %q: %s", text, rec.Body.String())
		}
	}
	if strings.Contains(rec.Body.String(), "logged-out.html") {
		t.Fatalf("signed-out page must not retain the old logged-out route name: %s", rec.Body.String())
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("signed-out Cache-Control=%q", got)
	}
}

type selectiveSlowClient struct {
	delegate *http.Client
	slowHost string
	delay    time.Duration
}

func (c selectiveSlowClient) Do(req *http.Request) (*http.Response, error) {
	if req.URL.Host == c.slowHost {
		time.Sleep(c.delay)
		return nil, errors.New("slow client finished after caller budget")
	}
	return c.delegate.Do(req)
}

func TestFrontendUsesSharedLightweightAppShellContract(t *testing.T) {
	indexHTML, err := web.ReadFile("web/index.html")
	if err != nil {
		t.Fatal(err)
	}
	appJS, err := web.ReadFile("web/app.js")
	if err != nil {
		t.Fatal(err)
	}

	html := string(indexHTML)
	for _, text := range []string{
		`class="skip-link" href="#main"`,
		`<main id="main" tabindex="-1">`,
		`<header>`,
		`/app-shell.css`,
		`/idpauth.js`,
		`class="header-actions"`,
		`id="auth-state"`,
		`id="logout-btn" class="sign-in-link"`,
		`>Sign Out<`,
		`id="theme-switcher"`,
		`class="theme-toggle"`,
		`id="status" role="status" aria-live="polite"`,
		`id="network-path"`,
		`<section class="app-panel conversation"`,
		`<aside class="inspector"`,
	} {
		if !strings.Contains(html, text) {
			t.Fatalf("frontend shell missing %q: %s", text, html)
		}
	}

	if strings.Contains(html, `<main class="shell">`) {
		t.Fatalf("frontend shell must use the shared bare main container: %s", html)
	}
	for _, text := range []string{`id="login-btn"`, `>Sign In<`} {
		if strings.Contains(html, text) {
			t.Fatalf("protected frontend index must not render login control %q: %s", text, html)
		}
	}
	if strings.Index(html, `<header>`) > strings.Index(html, `<section class="app-panel conversation"`) {
		t.Fatalf("frontend shell header must be the first app section before content: %s", html)
	}
	if strings.Index(html, `id="logout-btn"`) > strings.Index(html, `id="theme-switcher"`) {
		t.Fatalf("frontend shell actions must be ordered auth, sign out, theme: %s", html)
	}

	js := string(appJS)
	for _, text := range []string{
		"PlatformIdpAuth",
		"PlatformAppShell",
		`readRuntimeConfig("PCE_CHATGPT_GO_CONFIG")`,
		"initializeThemeSwitcher()",
		"requireElement",
		"inputElement",
		"selectElement",
		"renderNetworkPathInto",
		"resolveNetworkHops",
		"fetchJSON",
		"setText",
		"networkPathEl",
		"configuredNetworkHops()",
		"config.showNetworkPath !== false",
		"withButtonBusy",
		"withSubmitterBusy",
		"errorMessage",
		"renderElementsInto",
		"renderJSONInto",
		"bindGatewayLogout(",
		"initializeGatewayAuthState(",
		"ignoreErrors: true",
		"showNetworkPath",
		"setTextDefault",
		`config.mcpUrl, "not configured"`,
	} {
		if !strings.Contains(js, text) {
			t.Fatalf("frontend auth code missing %q: %s", text, js)
		}
	}
	for _, text := range []string{
		"function fetchGatewaySession",
		"fetchGatewaySession()",
		"writeGatewayAuthState(authState, logoutButton, session)",
		"function normalizeGatewaySession",
		"function gatewayDisplayName",
		"function readThemeCookie",
		"function writeThemeCookie",
		"window.PCE_CHATGPT_GO_CONFIG || {}",
		"function themeCookieDomain",
		"function requireElement",
		"function inputElement",
		"function selectElement",
		"function renderNetworkPath",
		"async function requestJSON",
		"async function fetchJSON",
		"const response = await fetch(url)",
		"new Error(payload.error",
		"error.status = response.status",
		"error.payload = payload",
		"function isNetworkHop",
		"<summary>Network Path",
		"function escapeHTML",
		"function escapeAttr",
		"connectorList.innerHTML",
		"function renderConnector",
		"<article",
		"error.message",
		"JSON.stringify(result.discovery, null, 2)",
		"JSON.stringify(result, null, 2)",
		"JSON.stringify(\n\t\t\tresult.discovery || result,\n\t\t\tnull,\n\t\t\t2,\n\t\t)",
		"JSON.stringify(item.oauth_advanced, null, 2)",
		`config.mcpUrl || "` + "unk" + `nown"`,
		`requireElement("mcp-url").textContent`,
		`requireElement("model-provider").textContent`,
		`requireElement("dependencies").textContent`,
	} {
		if strings.Contains(js, text) {
			t.Fatalf("frontend app code should use shared helper instead of %q", text)
		}
	}
	for _, text := range []string{"pce-theme", "document.cookie"} {
		if strings.Contains(js, text) {
			t.Fatalf("theme implementation must live in shared app shell, not app.js %q", text)
		}
	}
}

func TestRuntimeConfigIncludesNetworkPathToggle(t *testing.T) {
	srv := NewServer(Config{
		Role:              "shell",
		MCPURL:            "http://mcp.example/mcp",
		LLMURL:            "http://llm.example/v1/chat/completions",
		LangfuseHost:      "http://langfuse.example",
		LangfusePublicKey: "pk-test",
		LangfuseSecretKey: "sk-test",
		OIDCIssuer:        "http://keycloak.example.test/realms/chatgpt-sim///",
		OIDCClientID:      "chatgpt-sim",
		ShowNetworkPath:   "false",
		NetworkHops:       `[{"label":"Browser","detail":"localhost","role":"User agent"}]`,
	}, nil)

	healthReq := httptest.NewRequest(http.MethodGet, "/health", nil)
	healthRec := httptest.NewRecorder()
	srv.ServeHTTP(healthRec, healthReq)
	if healthRec.Code != http.StatusOK {
		t.Fatalf("health returned %d: %s", healthRec.Code, healthRec.Body.String())
	}
	for _, text := range []string{
		`"model_provider":"openai-compatible via agentgateway"`,
		`"llm_configured":true`,
		`"trace_provider":"langfuse"`,
		`"trace_ingestion":"configured"`,
	} {
		if !strings.Contains(healthRec.Body.String(), text) {
			t.Fatalf("health missing runtime wiring %q: %s", text, healthRec.Body.String())
		}
	}
	if strings.Contains(healthRec.Body.String(), "sk-test") || strings.Contains(healthRec.Body.String(), "pk-test") {
		t.Fatalf("health must not expose Langfuse credentials: %s", healthRec.Body.String())
	}

	req := httptest.NewRequest(http.MethodGet, "/runtime-config.js", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("runtime config returned %d: %s", rec.Code, rec.Body.String())
	}
	for _, text := range []string{
		`"dependencyFootprint":"go-plus-shared-idpauth"`,
		`"modelProvider":"openai-compatible via agentgateway"`,
		`"oidcAuthority":"http://keycloak.example.test/realms/chatgpt-sim"`,
		`"oidcClientId":"chatgpt-sim"`,
		`"traceProvider":"langfuse configured"`,
		`"showNetworkPath":false`,
		`"networkHops":[{"detail":"localhost","label":"Browser","role":"User agent"}]`,
	} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("runtime config missing %q: %s", text, rec.Body.String())
		}
	}
	if strings.Contains(rec.Body.String(), "sk-test") || strings.Contains(rec.Body.String(), "pk-test") {
		t.Fatalf("runtime config must not expose Langfuse credentials: %s", rec.Body.String())
	}

	indexHTML, err := web.ReadFile("web/index.html")
	if err != nil {
		t.Fatal(err)
	}
	appJS, err := web.ReadFile("web/app.js")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(indexHTML), `id="trace-provider"`) {
		t.Fatalf("frontend connection panel must expose trace provider status: %s", string(indexHTML))
	}
	for _, text := range []string{`requireElement("trace-provider")`, `config.traceProvider`, `"disabled"`} {
		if !strings.Contains(string(appJS), text) {
			t.Fatalf("frontend app must render trace provider runtime config missing %q: %s", text, string(appJS))
		}
	}
}

func TestServerUsesSharedOIDCIssuerNormalization(t *testing.T) {
	source, err := os.ReadFile("server.go")
	if err != nil {
		t.Fatal(err)
	}
	for _, text := range []string{
		`appconfig.NormalizeURL(s.cfg.OIDCIssuer)`,
		`strings.TrimRight(s.cfg.OIDCIssuer`,
	} {
		has := strings.Contains(string(source), text)
		if strings.Contains(text, "NormalizeURL") && !has {
			t.Fatalf("server.go should normalize OIDC issuer through shared apphttp helper")
		}
		if strings.Contains(text, "TrimRight") && has {
			t.Fatalf("server.go should not hand-roll OIDC issuer URL normalization")
		}
	}
}

func TestFrontendComposerStaysCompact(t *testing.T) {
	styleCSS, err := web.ReadFile("web/style.css")
	if err != nil {
		t.Fatal(err)
	}
	css := string(styleCSS)

	for _, text := range []string{
		`.conversation {`,
		`grid-template-rows: auto auto;`,
		`max-height: min(680px, calc(100vh - 152px));`,
		`.messages {`,
		`max-height: min(440px, calc(100vh - 308px));`,
		`.messages:empty {`,
		`padding-block: 0;`,
		`.inspector {`,
		`max-height: min(680px, calc(100vh - 152px));`,
		`@media (max-width: 840px)`,
		`min-height: 0;`,
		`.composer {`,
		`padding: 10px;`,
		`min-height: 58px;`,
	} {
		if !strings.Contains(css, text) {
			t.Fatalf("compact composer CSS missing %q: %s", text, css)
		}
	}

	for _, text := range []string{
		`grid-template-rows: auto 1fr auto;`,
		`grid-template-rows: minmax(0, 1fr) auto;`,
		`min-height: calc(100vh - 32px);`,
		`min-height: min(680px, calc(100vh - 152px));`,
		`min-height: 72vh;`,
		`min-height: 92px;`,
	} {
		if strings.Contains(css, text) {
			t.Fatalf("composer CSS still contains oversized rule %q: %s", text, css)
		}
	}

	indexHTML, err := web.ReadFile("web/index.html")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(indexHTML), `id="message" rows="3"`) {
		t.Fatalf("composer textarea must not force a three-row minimum: %s", string(indexHTML))
	}
}

func TestGatewaySessionAdaptsOauth2ProxyUserHeaders(t *testing.T) {
	srv := NewServer(Config{Role: "shell"}, nil)
	req := httptest.NewRequest(http.MethodGet, "/.auth/me", nil)
	req.Header.Set("X-Auth-Request-Email", "demo@dev.test")
	req.Header.Set("X-Forwarded-Preferred-Username", "demo@dev.test")
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("gateway session returned %d: %s", rec.Code, rec.Body.String())
	}
	for _, text := range []string{
		`"clientPrincipal"`,
		`"userDetails":"demo@dev.test"`,
		`"typ":"preferred_username"`,
		`"val":"demo@dev.test"`,
		`"typ":"email"`,
	} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("gateway session missing %q: %s", text, rec.Body.String())
		}
	}
}

func TestMCPDiscoveryAndToolCall(t *testing.T) {
	mcp := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer mcp.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: mcp.URL + "/mcp"}, mcp.Client())

	req := httptest.NewRequest(http.MethodGet, "/api/discovery", nil)
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("discovery returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"registration_endpoint"`) {
		t.Fatalf("discovery did not include OAuth metadata: %s", rec.Body.String())
	}

	req = httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"who am I?","tool":"auto"}`))
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload["selected_tool"] != "whoami" {
		t.Fatalf("selected_tool=%v", payload["selected_tool"])
	}
	if !strings.Contains(payload["assistant"].(string), "local-chatgpt-go-user") {
		t.Fatalf("assistant did not summarize tool result: %s", payload["assistant"])
	}
}

func TestChatUsesConfiguredOpenAICompatibleModelWithMCPContext(t *testing.T) {
	mcp := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer mcp.Close()
	var llmRequest map[string]any
	llm := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			http.NotFound(w, r)
			return
		}
		if err := json.NewDecoder(r.Body).Decode(&llmRequest); err != nil {
			t.Fatal(err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"model":"agentgateway-test-model","choices":[{"message":{"role":"assistant","content":"The MCP server says you are local-chatgpt-go-user."}}]}`))
	}))
	defer llm.Close()
	langfuseRequests := make(chan map[string]any, 1)
	langfuse := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/public/ingestion" {
			http.NotFound(w, r)
			return
		}
		user, password, ok := r.BasicAuth()
		if !ok || user != "pk-test" || password != "sk-test" {
			t.Fatalf("missing Langfuse basic auth: %q %q ok=%v", user, password, ok)
		}
		var langfuseRequest map[string]any
		if err := json.NewDecoder(r.Body).Decode(&langfuseRequest); err != nil {
			t.Fatal(err)
		}
		langfuseRequests <- langfuseRequest
		w.WriteHeader(http.StatusAccepted)
	}))
	defer langfuse.Close()
	shell := NewServer(Config{
		Role:              "shell",
		MCPURL:            mcp.URL + "/mcp",
		LLMURL:            llm.URL + "/v1/chat/completions",
		LLMModel:          "agentgateway-test-model",
		LangfuseHost:      langfuse.URL,
		LangfusePublicKey: "pk-test",
		LangfuseSecretKey: "sk-test",
	}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"who am I?","tool":"auto"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload["assistant"] != "The MCP server says you are local-chatgpt-go-user." {
		t.Fatalf("assistant=%v", payload["assistant"])
	}
	model := payload["model"].(map[string]any)
	if model["provider"] != "openai-compatible" || model["route"] != "agentgateway" {
		t.Fatalf("model metadata=%#v", model)
	}
	if model["status"] != "ok" {
		t.Fatalf("model status=%#v", model)
	}
	messages := llmRequest["messages"].([]any)
	encodedMessages, _ := json.Marshal(messages)
	if !strings.Contains(string(encodedMessages), "who am I?") || !strings.Contains(string(encodedMessages), "local-chatgpt-go-user") {
		t.Fatalf("LLM request did not include user message and MCP result: %s", encodedMessages)
	}
	if !strings.Contains(string(encodedMessages), "platform shell has already executed") || !strings.Contains(string(encodedMessages), "Observed MCP tool result") {
		t.Fatalf("LLM request did not clearly ground the completion in an executed MCP call: %s", encodedMessages)
	}
	trace := payload["trace"].(map[string]any)
	if trace["provider"] != "langfuse" || trace["status"] != "ok" || !strings.HasPrefix(trace["traceId"].(string), "chatgpt-sim-") {
		t.Fatalf("trace metadata=%#v", trace)
	}
	var langfuseRequest map[string]any
	select {
	case langfuseRequest = <-langfuseRequests:
	case <-time.After(time.Second):
		t.Fatal("Langfuse ingestion was not sent after queued trace response")
	}
	batch := langfuseRequest["batch"].([]any)
	encodedBatch, _ := json.Marshal(batch)
	for _, text := range []string{"trace-create", "generation-create", "chatgpt-sim.chat", "agentgateway-test-model", "whoami", "local-chatgpt-go-user"} {
		if !strings.Contains(string(encodedBatch), text) {
			t.Fatalf("Langfuse batch missing %q: %s", text, encodedBatch)
		}
	}
}

func TestChatFallsBackToMCPResultWhenAgentgatewayUnavailable(t *testing.T) {
	mcp := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer mcp.Close()
	llm := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "upstream unavailable", http.StatusServiceUnavailable)
	}))
	defer llm.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: mcp.URL + "/mcp", LLMURL: llm.URL + "/v1/chat/completions", LLMModel: "agentgateway-test-model"}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"who am I?","tool":"auto"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(payload["assistant"].(string), "local-chatgpt-go-user") {
		t.Fatalf("assistant did not fall back to MCP result: %s", payload["assistant"])
	}
	model := payload["model"].(map[string]any)
	if model["status"] != "unavailable" || !strings.Contains(model["error"].(string), "503") {
		t.Fatalf("model metadata=%#v", model)
	}
}

func TestIdentityQuestionListsToolsWhenMCPDoesNotAdvertiseIdentityTool(t *testing.T) {
	tools := map[string]any{
		"jsonrpc": "2.0",
		"id":      2,
		"result": map[string]any{"tools": []any{
			map[string]any{"name": "model_ping"},
			map[string]any{"name": "d2_validate"},
		}},
	}

	toolName, _ := chooseAdvertisedTool(tools, "what is your identity")
	if toolName != "tools/list" {
		t.Fatalf("toolName=%q", toolName)
	}
}

func TestIntentQuestionListsToolsWhenMCPDoesNotAdvertiseMatchingTool(t *testing.T) {
	tools := map[string]any{
		"jsonrpc": "2.0",
		"id":      2,
		"result": map[string]any{"tools": []any{
			map[string]any{"name": "model_ping"},
			map[string]any{"name": "d2_validate"},
			map[string]any{"name": "d2_render"},
		}},
	}

	for _, message := range []string{
		"give me route evidence",
		"tell me the security posture",
		"is the service healthy",
	} {
		toolName, _ := chooseAdvertisedTool(tools, message)
		if toolName != "tools/list" {
			t.Fatalf("message %q selected %q", message, toolName)
		}
	}
}

func TestChatDiscoversOpenAICompatibleModelWhenNotConfigured(t *testing.T) {
	mcp := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer mcp.Close()
	var llmRequest map[string]any
	llm := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"object":"list","data":[{"id":"served-local-model","object":"model"}]}`))
		case "/v1/chat/completions":
			if err := json.NewDecoder(r.Body).Decode(&llmRequest); err != nil {
				t.Fatal(err)
			}
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"model":"served-local-model","choices":[{"message":{"role":"assistant","content":"Discovered model answered with MCP context."}}]}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer llm.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: mcp.URL + "/mcp", LLMURL: llm.URL + "/v1/chat/completions"}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"who am I?","tool":"auto"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if llmRequest["model"] != "served-local-model" {
		t.Fatalf("model sent to LLM=%v", llmRequest["model"])
	}
	if llmRequest["max_tokens"] != float64(32) {
		t.Fatalf("max_tokens sent to LLM=%v", llmRequest["max_tokens"])
	}
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	model := payload["model"].(map[string]any)
	if model["model"] != "served-local-model" {
		t.Fatalf("response model metadata=%#v", model)
	}
}

func TestModelPingUsesFastOpenAICompatibleModelsEndpoint(t *testing.T) {
	mcp := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer mcp.Close()
	var sawModels bool
	llm := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			sawModels = true
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"object":"list","data":[{"id":"served-local-model","object":"model"}]}`))
		case "/v1/chat/completions":
			t.Fatal("model_ping must not spend the interactive budget on generation")
		default:
			http.NotFound(w, r)
		}
	}))
	defer llm.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: mcp.URL + "/mcp", LLMURL: llm.URL + "/v1/chat/completions"}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"ping the model","tool":"model_ping"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if !sawModels {
		t.Fatal("model_ping did not call /v1/models")
	}
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload["selected_tool"] != "model_ping" {
		t.Fatalf("selected_tool=%v", payload["selected_tool"])
	}
	model := payload["model"].(map[string]any)
	if model["status"] != "ok" || model["model"] != "served-local-model" || model["source"] != "llm.models" {
		t.Fatalf("model metadata=%#v", model)
	}
	if strings.Contains(rec.Body.String(), "exceeded") {
		t.Fatalf("model_ping should not return a timeout-shaped tool error: %s", rec.Body.String())
	}
}

func TestChatFallsBackWhenOpenAICompatibleModelExceedsAppTimeout(t *testing.T) {
	mcp := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer mcp.Close()
	llm := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			http.NotFound(w, r)
			return
		}
		select {
		case <-r.Context().Done():
			return
		case <-time.After(100 * time.Millisecond):
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"late"}}]}`))
		}
	}))
	defer llm.Close()
	shell := NewServer(Config{
		Role:       "shell",
		MCPURL:     mcp.URL + "/mcp",
		LLMURL:     llm.URL + "/v1/chat/completions",
		LLMModel:   "slow-model",
		LLMTimeout: 50 * time.Millisecond,
	}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"who am I?","tool":"whoami"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	model, ok := payload["model"].(map[string]any)
	if !ok {
		t.Fatalf("model metadata missing in payload: %#v", payload)
	}
	errText, ok := model["error"].(string)
	if !ok {
		t.Fatalf("model error missing in metadata: %#v", model)
	}
	if model["status"] != "unavailable" || (!strings.Contains(errText, "timeout") && !strings.Contains(errText, "deadline") && !strings.Contains(errText, "exceeded")) {
		t.Fatalf("model metadata=%#v", model)
	}
}

func TestChatFallsBackWhenOpenAICompatibleClientIgnoresTimeout(t *testing.T) {
	mcp := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer mcp.Close()
	llm := httptest.NewServer(http.NotFoundHandler())
	defer llm.Close()
	llmURL, err := url.Parse(llm.URL)
	if err != nil {
		t.Fatal(err)
	}
	shell := NewServer(Config{
		Role:       "shell",
		MCPURL:     mcp.URL + "/mcp",
		LLMURL:     llm.URL + "/v1/chat/completions",
		LLMModel:   "slow-model",
		LLMTimeout: 50 * time.Millisecond,
	}, selectiveSlowClient{delegate: mcp.Client(), slowHost: llmURL.Host, delay: 200 * time.Millisecond})

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"who am I?","tool":"whoami"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	started := time.Now()
	shell.ServeHTTP(rec, req)
	elapsed := time.Since(started)

	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if elapsed > 100*time.Millisecond {
		t.Fatalf("chat took %s, want bounded fallback", elapsed)
	}
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	model, ok := payload["model"].(map[string]any)
	if !ok {
		t.Fatalf("model metadata missing in payload: %#v", payload)
	}
	errText, ok := model["error"].(string)
	if !ok {
		t.Fatalf("model error missing in metadata: %#v", model)
	}
	if model["status"] != "unavailable" || !strings.Contains(errText, "exceeded") {
		t.Fatalf("model metadata=%#v", model)
	}
}

func TestChatCleansLeakedThinkingProcessFromOpenAICompatibleModel(t *testing.T) {
	got := cleanAssistantText(`Thinking Process:

1. Analyze.
*   Direct Answer: Yes, it can reach the model gateway through agentgateway.

5. Review constraints`)
	if got != "Yes, it can reach the model gateway through agentgateway." {
		t.Fatalf("cleaned assistant text=%q", got)
	}
}

func TestDeterministicReplySummarizesStructuredModelPing(t *testing.T) {
	got := deterministicReply("model_ping", map[string]any{
		"content": []any{map[string]any{
			"type": "text",
			"text": `{"success":true,"route":"agentgateway","model":"Qwen3.5-9B-MLX-4bit"}`,
		}},
	})
	if got != "Yes. The MCP server reached Qwen3.5-9B-MLX-4bit through agentgateway." {
		t.Fatalf("model_ping reply=%q", got)
	}
}

func TestLocalLLMRoleServesOpenAICompatibleChatCompletions(t *testing.T) {
	srv := NewServer(Config{Role: "llm"}, nil)
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"model":"local","messages":[{"role":"user","content":"who am I?"},{"role":"system","content":"MCP tool result JSON: {\"subject\":\"local-chatgpt-go-user\"}"}]}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("completion returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"choices"`) || !strings.Contains(rec.Body.String(), "local-chatgpt-go-user") || !strings.Contains(rec.Body.String(), "local deterministic stub") {
		t.Fatalf("completion response is not OpenAI-compatible enough for compose: %s", rec.Body.String())
	}
}

func TestLocalLLMRoleUsesExplicitMissingSubjectLabel(t *testing.T) {
	srv := NewServer(Config{Role: "llm"}, nil)
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", strings.NewReader(`{"model":"local","messages":[{"role":"user","content":"who am I?"}]}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("completion returned %d: %s", rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "unk"+"nown") || !strings.Contains(rec.Body.String(), "not provided") {
		t.Fatalf("completion response should avoid ambiguous placeholders: %s", rec.Body.String())
	}
}

func TestLocalLLMRoleDefaultModelNameMakesStubExplicit(t *testing.T) {
	srv := NewServer(Config{Role: "llm"}, nil)
	req := httptest.NewRequest(http.MethodGet, "/v1/models", nil)
	rec := httptest.NewRecorder()

	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("models returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"id":"go-local-openai-compatible-stub"`) {
		t.Fatalf("default local model must be clearly identified as a stub: %s", rec.Body.String())
	}
}

func TestLocalLLMRoleServesOpenAICompatibleModels(t *testing.T) {
	srv := NewServer(Config{Role: "llm", LLMModel: "compose-served-model"}, nil)
	req := httptest.NewRequest(http.MethodGet, "/v1/models", nil)
	rec := httptest.NewRecorder()

	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("models returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"id":"compose-served-model"`) {
		t.Fatalf("models response did not advertise configured model: %s", rec.Body.String())
	}
}

func TestSettingsCanAddMCPConnectorAndUseItForChat(t *testing.T) {
	firstMCP := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer firstMCP.Close()
	secondMCP := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer secondMCP.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: firstMCP.URL + "/mcp"}, firstMCP.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/connectors", strings.NewReader(`{"name":"Second MCP","url":"`+secondMCP.URL+`/mcp","auth":"oauth"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("add connector returned %d: %s", rec.Code, rec.Body.String())
	}
	var conn connector
	if err := json.Unmarshal(rec.Body.Bytes(), &conn); err != nil {
		t.Fatal(err)
	}
	if conn.Status != "ready" || conn.OAuth["authorization_endpoint"] == "" {
		t.Fatalf("connector did not capture OAuth metadata: %#v", conn)
	}

	req = httptest.NewRequest(http.MethodGet, "/api/connectors", nil)
	rec = httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("list connectors returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "Second MCP") {
		t.Fatalf("connector list missing added MCP: %s", rec.Body.String())
	}

	req = httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"what tools did you discover?","tool":"auto","connector_id":"`+conn.ID+`"}`))
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"selected_tool":"tools/list"`) {
		t.Fatalf("chat did not use selected connector for tool discovery: %s", rec.Body.String())
	}
}

func TestConfigFromEnvSeedsAPIMGatedMCPConnector(t *testing.T) {
	t.Setenv("MCP_CONNECTORS", `[
		{"id":"platform-mcp","name":"Platform MCP via APIM","url":"https://mcpserver.dev.127.0.0.1.sslip.io/mcp","internal_url":"http://subnetcalc-apim-simulator.apim.svc.cluster.local:8000/mcp"}
	]`)
	shell := NewServer(ConfigFromEnv(), nil)

	req := httptest.NewRequest(http.MethodGet, "/api/connectors", nil)
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("list connectors returned %d: %s", rec.Code, rec.Body.String())
	}
	var payload struct {
		Items []connector `json:"items"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if len(payload.Items) != 1 {
		t.Fatalf("seeded connector count=%d body=%s", len(payload.Items), rec.Body.String())
	}
	if payload.Items[0].ID != "platform-mcp" ||
		payload.Items[0].Name != "Platform MCP via APIM" ||
		payload.Items[0].URL != "https://mcpserver.dev.127.0.0.1.sslip.io/mcp" ||
		payload.Items[0].InternalURL != "http://subnetcalc-apim-simulator.apim.svc.cluster.local:8000/mcp" {
		t.Fatalf("connector not seeded from MCP_CONNECTORS: %#v", payload.Items[0])
	}
}

func TestConfigFromEnvDefaultsLLMToInteractiveLatencyBudget(t *testing.T) {
	t.Setenv("LLM_TIMEOUT_SECONDS", "")

	cfg := ConfigFromEnv()

	if cfg.LLMTimeout != time.Second {
		t.Fatalf("LLMTimeout=%s, want 1s", cfg.LLMTimeout)
	}
	if cfg.LLMMaxTokens != 32 {
		t.Fatalf("LLMMaxTokens=%d, want 32", cfg.LLMMaxTokens)
	}
	if cfg.LangfuseTimeout != time.Second {
		t.Fatalf("LangfuseTimeout=%s, want 1s", cfg.LangfuseTimeout)
	}
}

func TestConnectorWithoutInternalURLDoesNotUseGlobalMCPInternalURL(t *testing.T) {
	s := &server{cfg: Config{MCPInternalURL: "http://subnetcalc-apim-simulator.apim.svc.cluster.local:8000/mcp"}}
	if got := s.resolveMCPURL("http://direct-mcp.dev.svc.cluster.local:8080/mcp", ""); got != "http://direct-mcp.dev.svc.cluster.local:8080/mcp" {
		t.Fatalf("connector without internal URL used global MCP_INTERNAL_URL: %s", got)
	}

	var protectedHost string
	var mcpHost string
	directMCP := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/.well-known/oauth-protected-resource/mcp":
			protectedHost = r.Host
			apphttp.WriteJSON(w, http.StatusOK, map[string]any{"resource": "http://" + r.Host + "/mcp", "authorization_servers": []string{}, "scopes_supported": []string{"mcp.access"}})
		case "/mcp":
			mcpHost = r.Host
			NewServer(Config{Role: "mcp"}, nil).ServeHTTP(w, r)
		default:
			http.NotFound(w, r)
		}
	}))
	defer directMCP.Close()
	apim := httptest.NewServer(http.NotFoundHandler())
	defer apim.Close()
	shell := NewServer(Config{
		Role:           "shell",
		MCPURL:         "https://mcpserver.dev.127.0.0.1.sslip.io/mcp",
		MCPInternalURL: apim.URL + "/mcp",
		MCPConnectors: []ConnectorConfig{{
			ID:   "direct-mcp",
			Name: "Direct MCP",
			URL:  directMCP.URL + "/mcp",
		}},
	}, directMCP.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"which tools do you have","tool":"auto"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if protectedHost == "" || mcpHost == "" {
		t.Fatalf("direct MCP did not receive discovery and mcp calls: protected=%q mcp=%q", protectedHost, mcpHost)
	}
}

func TestInternalMCPRoutePreservesExternalHostForAPIMRouting(t *testing.T) {
	var protectedHost string
	var mcpHost string
	apim := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/.well-known/oauth-protected-resource/mcp":
			protectedHost = r.Host
			if r.Host != "mcpserver.dev.127.0.0.1.sslip.io" {
				http.NotFound(w, r)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"resource":"https://mcpserver.dev.127.0.0.1.sslip.io/mcp","authorization_servers":[],"scopes_supported":["mcp.access"]}`))
		case "/mcp":
			mcpHost = r.Host
			if r.Host != "mcpserver.dev.127.0.0.1.sslip.io" {
				http.NotFound(w, r)
				return
			}
			NewServer(Config{Role: "mcp"}, nil).ServeHTTP(w, r)
		default:
			http.NotFound(w, r)
		}
	}))
	defer apim.Close()

	shell := NewServer(Config{
		Role:           "shell",
		MCPURL:         "https://mcpserver.dev.127.0.0.1.sslip.io/mcp",
		MCPInternalURL: apim.URL + "/mcp",
	}, apim.Client())

	req := httptest.NewRequest(http.MethodGet, "/api/discovery", nil)
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("discovery returned %d: %s", rec.Code, rec.Body.String())
	}
	if protectedHost != "mcpserver.dev.127.0.0.1.sslip.io" {
		t.Fatalf("protected resource discovery Host=%q", protectedHost)
	}

	req = httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"what tools did you discover?","tool":"tools/list"}`))
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if mcpHost != "mcpserver.dev.127.0.0.1.sslip.io" {
		t.Fatalf("mcp call Host=%q", mcpHost)
	}
}

func TestChatForwardsSSOAccessTokenToMCP(t *testing.T) {
	var gotAuth string
	mcp := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		NewServer(Config{Role: "mcp"}, nil).ServeHTTP(w, r)
	}))
	defer mcp.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: mcp.URL + "/mcp"}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"what tools did you discover?","tool":"tools/list"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Forwarded-Access-Token", "sso-token-value")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if gotAuth != "Bearer sso-token-value" {
		t.Fatalf("Authorization forwarded to MCP=%q", gotAuth)
	}
}

func TestSSOBearerConnectorDoesNotFallBackToLocalBearer(t *testing.T) {
	mcp := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer mcp.Close()
	shell := NewServer(Config{
		Role: "shell",
		MCPConnectors: []ConnectorConfig{{
			ID:   "platform-mcp",
			Name: "Platform MCP via APIM",
			URL:  mcp.URL + "/mcp",
			Auth: "sso_bearer",
		}},
	}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"which tools do you have","tool":"tools/list","connector_id":"platform-mcp"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "requires an SSO bearer token") {
		t.Fatalf("missing clear SSO token error: %s", rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"isError":true`) {
		t.Fatalf("SSO token failure must be reported as a tool error: %s", rec.Body.String())
	}
}

func TestMCPHTTPErrorIncludesResponseDetail(t *testing.T) {
	mcp := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/.well-known/oauth-protected-resource/mcp":
			apphttp.WriteJSON(w, http.StatusOK, map[string]any{"resource": mcpResource(r), "authorization_servers": []string{}, "scopes_supported": []string{"mcp.access"}})
		case "/mcp":
			apphttp.WriteJSON(w, http.StatusUnauthorized, map[string]string{"detail": "Invalid or expired access token"})
		default:
			http.NotFound(w, r)
		}
	}))
	defer mcp.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: mcp.URL + "/mcp"}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"which tools do you have","tool":"tools/list"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "401 Unauthorized from initialize: Invalid or expired access token") {
		t.Fatalf("missing response detail in error: %s", rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"isError":true`) {
		t.Fatalf("MCP HTTP failure must be reported as a tool error: %s", rec.Body.String())
	}
}

func TestChatReturnsJSONBeforeProxyTimeoutWhenMCPConnectorHangs(t *testing.T) {
	mcp := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/.well-known/oauth-protected-resource/mcp":
			apphttp.WriteJSON(w, http.StatusOK, map[string]any{"resource": mcpResource(r), "authorization_servers": []string{}, "scopes_supported": []string{"mcp.access"}})
		case "/mcp":
			time.Sleep(200 * time.Millisecond)
			writeRPC(w, 1, map[string]any{})
		default:
			http.NotFound(w, r)
		}
	}))
	defer mcp.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: mcp.URL + "/mcp", LLMTimeout: 5 * time.Millisecond}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"call the model","tool":"model_ping"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	started := time.Now()
	shell.ServeHTTP(rec, req)
	elapsed := time.Since(started)

	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if elapsed > 100*time.Millisecond {
		t.Fatalf("chat took %s, want bounded JSON error", elapsed)
	}
	if !strings.Contains(rec.Body.String(), "MCP connector call exceeded") {
		t.Fatalf("missing bounded MCP timeout error: %s", rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"isError":true`) {
		t.Fatalf("bounded MCP timeout must be reported as a tool error: %s", rec.Body.String())
	}
}

func TestChatReturnsJSONBeforeProxyTimeoutWhenMCPDiscoveryHangs(t *testing.T) {
	mcp := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/.well-known/oauth-protected-resource/mcp":
			time.Sleep(200 * time.Millisecond)
			apphttp.WriteJSON(w, http.StatusOK, map[string]any{"resource": mcpResource(r), "authorization_servers": []string{}, "scopes_supported": []string{"mcp.access"}})
		default:
			http.NotFound(w, r)
		}
	}))
	defer mcp.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: mcp.URL + "/mcp", LLMTimeout: 5 * time.Millisecond}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"which tools do you have","tool":"tools/list"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	started := time.Now()
	shell.ServeHTTP(rec, req)
	elapsed := time.Since(started)

	if rec.Code != http.StatusBadGateway {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if elapsed > 100*time.Millisecond {
		t.Fatalf("chat took %s, want bounded discovery error", elapsed)
	}
	if !strings.Contains(rec.Body.String(), "MCP discovery exceeded") {
		t.Fatalf("missing bounded discovery timeout error: %s", rec.Body.String())
	}
}

func mcpResource(r *http.Request) string {
	return "http://" + r.Host + "/mcp"
}

func TestSettingsNormalizesBareMCPHostForChat(t *testing.T) {
	firstMCP := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer firstMCP.Close()
	secondMCP := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer secondMCP.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: firstMCP.URL + "/mcp"}, firstMCP.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/connectors", strings.NewReader(`{"name":"Bare host","url":"`+secondMCP.URL+`"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("add connector returned %d: %s", rec.Code, rec.Body.String())
	}
	var conn connector
	if err := json.Unmarshal(rec.Body.Bytes(), &conn); err != nil {
		t.Fatal(err)
	}
	if conn.URL != secondMCP.URL+"/mcp" {
		t.Fatalf("bare host was not normalized to /mcp: %q", conn.URL)
	}

	req = httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"what tools did you discover?","connector_id":"`+conn.ID+`"}`))
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"selected_tool":"tools/list"`) {
		t.Fatalf("chat did not use normalized connector URL: %s", rec.Body.String())
	}
}

func TestDiscoveryFallsBackToOIDCConfiguration(t *testing.T) {
	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/.well-known/openid-configuration" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"issuer":"` + r.Host + `","authorization_endpoint":"https://login.example/authorize","token_endpoint":"https://login.example/token","userinfo_endpoint":"https://login.example/userinfo","scopes_supported":["openid","profile","mcp.access"]}`))
	}))
	defer auth.Close()
	mcp := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/.well-known/oauth-protected-resource/mcp":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"resource":"` + r.Host + `/mcp","authorization_servers":["` + auth.URL + `"],"scopes_supported":["mcp.access"]}`))
		case "/mcp":
			NewServer(Config{Role: "mcp"}, nil).ServeHTTP(w, r)
		default:
			http.NotFound(w, r)
		}
	}))
	defer mcp.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: mcp.URL + "/mcp"}, mcp.Client())

	req := httptest.NewRequest(http.MethodGet, "/api/discovery", nil)
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("discovery returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"oidc_configuration"`) || !strings.Contains(rec.Body.String(), `"userinfo_endpoint"`) {
		t.Fatalf("discovery did not include OIDC fallback metadata: %s", rec.Body.String())
	}
}

func TestSettingsBuildsOAuthLoginPromptURL(t *testing.T) {
	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/.well-known/openid-configuration":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"issuer":"` + authIssuer(r) + `","authorization_endpoint":"` + authIssuer(r) + `/authorize","token_endpoint":"` + authIssuer(r) + `/token","scopes_supported":["openid","profile"]}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer auth.Close()
	mcp := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/.well-known/oauth-protected-resource/mcp":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"resource":"` + r.Host + `/mcp","authorization_servers":["` + auth.URL + `"],"scopes_supported":["api://local/mcp.access"]}`))
		case "/mcp":
			NewServer(Config{Role: "mcp"}, nil).ServeHTTP(w, r)
		default:
			http.NotFound(w, r)
		}
	}))
	defer mcp.Close()
	defaultMCP := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer defaultMCP.Close()
	shell := NewServer(Config{Role: "shell", PublicBaseURL: "http://localhost:18083", MCPURL: defaultMCP.URL + "/mcp"}, mcp.Client())

	body := `{"name":"OIDC MCP","url":"` + mcp.URL + `","oauth_client_id":"client-123"}`
	req := httptest.NewRequest(http.MethodPost, "/api/connectors", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("add connector returned %d: %s", rec.Code, rec.Body.String())
	}
	var conn connector
	if err := json.Unmarshal(rec.Body.Bytes(), &conn); err != nil {
		t.Fatal(err)
	}
	if conn.LoginURL == "" {
		t.Fatalf("login URL was not generated: %#v", conn)
	}
	if !strings.Contains(conn.LoginURL, "/authorize?") ||
		!strings.Contains(conn.LoginURL, "client_id=client-123") ||
		!strings.Contains(conn.LoginURL, "redirect_uri=http%3A%2F%2Flocalhost%3A18083%2Foauth%2Fcallback") ||
		!strings.Contains(conn.LoginURL, "scope=api%3A%2F%2Flocal%2Fmcp.access") {
		t.Fatalf("login URL does not contain expected OAuth parameters: %s", conn.LoginURL)
	}
}

func TestSettingsCapturesAdvancedOAuthSettings(t *testing.T) {
	mcp := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer mcp.Close()
	defaultMCP := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer defaultMCP.Close()
	shell := NewServer(Config{Role: "shell", PublicBaseURL: "http://localhost:18083", MCPURL: defaultMCP.URL + "/mcp"}, mcp.Client())

	body := `{
		"name":"Advanced OAuth MCP",
		"url":"` + mcp.URL + `",
		"oauth_client_mode":"USER_DEFINED",
		"oauth_client_id":"client-advanced",
		"oauth_client_secret":"secret-value",
		"oauth_token_endpoint_auth_method":"client_secret_post",
		"oauth_requested_scopes":"api://default.scope, api://extra.scope",
		"oauth_base_scopes":"openid\nprofile",
		"oauth_authorization_url":"https://login.example/authorize",
		"oauth_token_url":"https://login.example/token",
		"oauth_registration_url":"https://login.example/register",
		"oauth_authorization_server_base":"https://login.example",
		"oauth_resource":"api://resource",
		"oauth_oidc_configuration_url":"https://login.example/.well-known/openid-configuration",
		"oauth_oidc_userinfo_endpoint":"https://login.example/userinfo",
		"oauth_oidc_scopes_supported":"openid,profile,email"
	}`
	req := httptest.NewRequest(http.MethodPost, "/api/connectors", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("add connector returned %d: %s", rec.Code, rec.Body.String())
	}
	var conn connector
	if err := json.Unmarshal(rec.Body.Bytes(), &conn); err != nil {
		t.Fatal(err)
	}
	advanced := conn.OAuthAdvanced
	if advanced["registration_method"] != "USER_DEFINED" ||
		advanced["token_endpoint_auth_method"] != "client_secret_post" ||
		advanced["client_secret_configured"] != true {
		t.Fatalf("advanced OAuth settings not preserved: %#v", advanced)
	}
	if conn.OAuth["authorization_endpoint"] != "https://login.example/authorize" ||
		conn.OAuth["token_endpoint"] != "https://login.example/token" ||
		conn.OAuth["registration_endpoint"] != "https://login.example/register" {
		t.Fatalf("endpoint overrides not reflected in OAuth summary: %#v", conn.OAuth)
	}
	loginURL, err := url.Parse(conn.LoginURL)
	if err != nil {
		t.Fatal(err)
	}
	if loginURL.Host != "login.example" || loginURL.Path != "/authorize" {
		t.Fatalf("login URL did not use authorization override: %s", conn.LoginURL)
	}
	if got := loginURL.Query().Get("scope"); got != "openid profile api://default.scope api://extra.scope" {
		t.Fatalf("scope=%q", got)
	}
}

func TestSettingsRejectDuplicateMCPConnectorURL(t *testing.T) {
	mcp := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer mcp.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: mcp.URL + "/mcp"}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/connectors", strings.NewReader(`{"url":"`+mcp.URL+`/mcp/"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("duplicate connector returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "connector already exists") {
		t.Fatalf("duplicate response did not explain conflict: %s", rec.Body.String())
	}
}

func authIssuer(r *http.Request) string {
	return "http://" + r.Host
}

func TestSettingsCanDeleteAddedMCPConnector(t *testing.T) {
	firstMCP := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer firstMCP.Close()
	secondMCP := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer secondMCP.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: firstMCP.URL + "/mcp"}, firstMCP.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/connectors", strings.NewReader(`{"name":"Disposable","url":"`+secondMCP.URL+`/mcp"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("add connector returned %d: %s", rec.Code, rec.Body.String())
	}
	var conn connector
	if err := json.Unmarshal(rec.Body.Bytes(), &conn); err != nil {
		t.Fatal(err)
	}

	req = httptest.NewRequest(http.MethodDelete, "/api/connectors/"+conn.ID, nil)
	rec = httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("delete connector returned %d: %s", rec.Code, rec.Body.String())
	}

	req = httptest.NewRequest(http.MethodGet, "/api/connectors", nil)
	rec = httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if strings.Contains(rec.Body.String(), "Disposable") {
		t.Fatalf("deleted connector still listed: %s", rec.Body.String())
	}
}

func TestShellCanDiscussDiscoveredMCPTools(t *testing.T) {
	mcp := httptest.NewServer(NewServer(Config{Role: "mcp"}, nil))
	defer mcp.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: mcp.URL + "/mcp"}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"what tools did you discover?","tool":"auto"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload["selected_tool"] != "tools/list" {
		t.Fatalf("selected_tool=%v", payload["selected_tool"])
	}
	if !strings.Contains(payload["assistant"].(string), "`whoami`") || !strings.Contains(payload["assistant"].(string), "`infer`") {
		t.Fatalf("assistant did not describe discovered tools: %s", payload["assistant"])
	}
	result := payload["tool_result"].(map[string]any)
	content := result["structuredContent"].(map[string]any)
	if int(content["count"].(float64)) != 9 {
		t.Fatalf("count=%v", content["count"])
	}
}

func TestShellTreatsRouteExamplesAsDiscovery(t *testing.T) {
	mcp := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet && r.URL.Path == "/.well-known/oauth-protected-resource/mcp" {
			apphttp.WriteJSON(w, http.StatusOK, map[string]any{"resource": "http://" + r.Host + "/mcp", "authorization_servers": []string{}, "scopes_supported": []string{"mcp.access"}})
			return
		}
		var req rpcRequest
		if !apphttp.DecodeJSONError(w, r, &req, "invalid JSON body") {
			return
		}
		switch req.Method {
		case "initialize":
			writeRPC(w, req.ID, map[string]any{"protocolVersion": "2025-06-18", "capabilities": map[string]any{"tools": map[string]any{}}})
		case "tools/list":
			writeRPC(w, req.ID, map[string]any{"tools": []map[string]any{{
				"name":        "model_ping",
				"description": "Validate model gateway routing.",
				"inputSchema": map[string]any{"type": "object"},
			}}})
		case "tools/call":
			t.Fatalf("route example discovery should not call a tool")
		default:
			writeRPCError(w, req.ID, -32601, "method not found")
		}
	}))
	defer mcp.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: mcp.URL + "/mcp"}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"give me examples of routes you have","tool":"auto"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"selected_tool":"tools/list"`) ||
		!strings.Contains(rec.Body.String(), "`model_ping`") {
		t.Fatalf("chat did not answer route examples from discovered tools: %s", rec.Body.String())
	}
}

func TestShellDiscoveryQuestionDoesNotRequireLLM(t *testing.T) {
	mcp := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet && r.URL.Path == "/.well-known/oauth-protected-resource/mcp" {
			apphttp.WriteJSON(w, http.StatusOK, map[string]any{"resource": "http://" + r.Host + "/mcp", "authorization_servers": []string{}, "scopes_supported": []string{"mcp.access"}})
			return
		}
		var req rpcRequest
		if !apphttp.DecodeJSONError(w, r, &req, "invalid JSON body") {
			return
		}
		switch req.Method {
		case "initialize":
			writeRPC(w, req.ID, map[string]any{"protocolVersion": "2025-06-18", "capabilities": map[string]any{"tools": map[string]any{}}})
		case "tools/list":
			writeRPC(w, req.ID, map[string]any{"tools": []map[string]any{{
				"name":        "route_trace",
				"description": "Show the service route used for a request.",
			}}})
		default:
			writeRPCError(w, req.ID, -32601, "method not found")
		}
	}))
	defer mcp.Close()
	llm := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "unavailable", http.StatusServiceUnavailable)
	}))
	defer llm.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: mcp.URL + "/mcp", LLMURL: llm.URL + "/v1/chat/completions"}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"which tools do you have","tool":"auto"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"selected_tool":"tools/list"`) ||
		!strings.Contains(rec.Body.String(), "`route_trace`") {
		t.Fatalf("chat did not answer discovery question from MCP tools: %s", rec.Body.String())
	}
}

func TestAutoToolSelectionUsesAdvertisedMCPTools(t *testing.T) {
	mcp := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet && r.URL.Path == "/.well-known/oauth-protected-resource/mcp" {
			apphttp.WriteJSON(w, http.StatusOK, map[string]any{"resource": "http://" + r.Host + "/mcp", "authorization_servers": []string{}, "scopes_supported": []string{"mcp.access"}})
			return
		}
		var req rpcRequest
		if !apphttp.DecodeJSONError(w, r, &req, "invalid JSON body") {
			return
		}
		switch req.Method {
		case "initialize":
			writeRPC(w, req.ID, map[string]any{"protocolVersion": "2025-06-18", "capabilities": map[string]any{"tools": map[string]any{}}})
		case "tools/list":
			writeRPC(w, req.ID, map[string]any{"tools": []map[string]any{{
				"name":        "model_ping",
				"description": "Send a chat completion request.",
				"inputSchema": map[string]any{"type": "object", "properties": map[string]any{"prompt": map[string]string{"type": "string"}}},
			}}})
		case "tools/call":
			var params toolCallParams
			_ = remarshal(req.Params, &params)
			if params.Name != "model_ping" {
				t.Fatalf("called unadvertised/fallback tool %q", params.Name)
			}
			if params.Arguments["prompt"] != "can the model respond?" {
				t.Fatalf("prompt argument=%v", params.Arguments["prompt"])
			}
			writeRPC(w, req.ID, map[string]any{"content": []map[string]string{{"type": "text", "text": "model_ping ok"}}})
		default:
			writeRPCError(w, req.ID, -32601, "method not found")
		}
	}))
	defer mcp.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: mcp.URL + "/mcp"}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"can the model respond?","tool":"auto"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"selected_tool":"model_ping"`) {
		t.Fatalf("chat did not select advertised model_ping tool: %s", rec.Body.String())
	}
}

func TestChatReportsMCPJSONRPCErrorMessage(t *testing.T) {
	mcp := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet && r.URL.Path == "/.well-known/oauth-protected-resource/mcp" {
			apphttp.WriteJSON(w, http.StatusOK, map[string]any{"resource": "http://" + r.Host + "/mcp", "authorization_servers": []string{}, "scopes_supported": []string{"mcp.access"}})
			return
		}
		var req rpcRequest
		if !apphttp.DecodeJSONError(w, r, &req, "invalid JSON body") {
			return
		}
		switch req.Method {
		case "initialize":
			writeRPC(w, req.ID, map[string]any{"protocolVersion": "2025-06-18", "capabilities": map[string]any{"tools": map[string]any{}}})
		case "tools/list":
			writeRPC(w, req.ID, map[string]any{"tools": []map[string]any{{"name": "model_ping", "description": "Ping model gateway."}}})
		case "tools/call":
			writeRPCError(w, req.ID, -32000, "llm gateway returned 503")
		default:
			writeRPCError(w, req.ID, -32601, "method not found")
		}
	}))
	defer mcp.Close()
	shell := NewServer(Config{Role: "shell", MCPURL: mcp.URL + "/mcp"}, mcp.Client())

	req := httptest.NewRequest(http.MethodPost, "/api/chat", strings.NewReader(`{"message":"call the model","tool":"model_ping"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	shell.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "json-rpc error from tools/call: llm gateway returned 503") {
		t.Fatalf("chat did not report JSON-RPC error detail: %s", rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"isError":true`) {
		t.Fatalf("JSON-RPC failure must be reported as a tool error: %s", rec.Body.String())
	}
}

func TestWhoamiRequiresBearerTokenWhenOIDCIsEnabled(t *testing.T) {
	srv := NewServer(
		Config{Role: "shell", AuthMode: "oidc"},
		nil,
		fakeVerifier{claims: idpauth.UserClaims{Subject: "user-123"}},
	)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/whoami", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("missing token returned %d: %s", rec.Code, rec.Body.String())
	}
	if strings.TrimSpace(rec.Body.String()) != `{"error":"missing bearer token"}` {
		t.Fatalf("unexpected missing-token body: %s", rec.Body.String())
	}
}

func TestMCPRequiresBearerToken(t *testing.T) {
	srv := NewServer(Config{Role: "mcp", PublicBaseURL: "http://mcp.local"}, nil)
	req := httptest.NewRequest(http.MethodPost, "/mcp", strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"tools/list"}`))
	rec := httptest.NewRecorder()

	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Header().Get("WWW-Authenticate"), `resource_metadata="http://mcp.local/.well-known/oauth-protected-resource/mcp"`) {
		t.Fatalf("challenge header=%q", rec.Header().Get("WWW-Authenticate"))
	}
}

type fakeVerifier struct {
	claims idpauth.UserClaims
	err    error
}

func (v fakeVerifier) Verify(_ context.Context, token string) (idpauth.UserClaims, error) {
	if token != "valid-token" {
		return idpauth.UserClaims{}, idpauth.ErrInvalidToken
	}
	if v.err != nil {
		return idpauth.UserClaims{}, v.err
	}
	return v.claims, nil
}
