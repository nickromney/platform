package app

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"platform.local/apphttp"
	"platform.local/appshell"
	"platform.local/idpauth"
)

func TestHealthAndStaticFrontend(t *testing.T) {
	srv := NewServer(Config{RuntimeRole: "all", DataDir: t.TempDir()})

	for _, path := range []string{"/health", "/health/ready", "/health/live", "/api/v1/health", "/api/v1/health/ready", "/api/v1/health/live"} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		rec := httptest.NewRecorder()
		srv.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s returned %d: %s", path, rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), `"status"`) {
			t.Fatalf("%s returned unexpected body: %s", path, rec.Body.String())
		}
		if path == "/health" || path == "/api/v1/health" {
			var health map[string]any
			if err := json.Unmarshal(rec.Body.Bytes(), &health); err != nil {
				t.Fatalf("%s returned invalid health JSON: %v", path, err)
			}
			if got := health["dependency_footprint"]; got != "go-plus-shared-idpauth" {
				t.Fatalf("%s dependency_footprint=%v, want go-plus-shared-idpauth", path, got)
			}
			if got := health["frontend_dependency_footprint"]; got != "vanilla" {
				t.Fatalf("%s frontend_dependency_footprint=%v, want vanilla", path, got)
			}
			if _, ok := health["dependencies"]; ok {
				t.Fatalf("%s should use canonical dependency_footprint fields, got legacy dependencies in %v", path, health)
			}
		}
		if path == "/api/v1/health" {
			for _, text := range []string{`"service":"Sentiment API (Go)"`, `"version":"1.0.0"`, `"server_side_token_validation":false`} {
				if !strings.Contains(rec.Body.String(), text) {
					t.Fatalf("%s missing %q in %s", path, text, rec.Body.String())
				}
			}
		}
	}

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("frontend returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "<title>Sentiment (Authenticated)</title>") {
		t.Fatalf("frontend title missing: %s", rec.Body.String())
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
		"Sentiment",
		`@social-5h3ll/5h3ll-ui`,
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
	if strings.Contains(rec.Body.String(), `href="/style.css"`) {
		t.Fatalf("signed-out page should not load app-local CSS: %s", rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), `loginLink.href = "/"`) {
		t.Fatalf("signed-out page must not rewrite SSO login to the local app root: %s", rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "logged-out.html") {
		t.Fatalf("signed-out page must not retain the old logged-out route name: %s", rec.Body.String())
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("signed-out Cache-Control=%q", got)
	}
}

func TestServerUsesSharedHTTPErrorHelpers(t *testing.T) {
	serverSource, err := os.ReadFile("server.go")
	if err != nil {
		t.Fatal(err)
	}
	typesSource, err := os.ReadFile("types.go")
	if err != nil {
		t.Fatal(err)
	}
	serverText := string(serverSource)
	typesText := string(typesSource)

	for _, text := range []string{
		"apphttp.WriteError(",
		"apphttp.DecodeJSONError(",
		"apphttp.NewAPIProxy(apphttp.APIProxyConfig{",
	} {
		if !strings.Contains(serverText, text) {
			t.Fatalf("sentiment server should use shared HTTP helper %q", text)
		}
	}
	for _, text := range []string{"type errorResponse", "errorResponse{"} {
		if strings.Contains(serverText, text) || strings.Contains(typesText, text) {
			t.Fatalf("sentiment server should not keep local JSON error helper %q", text)
		}
	}
}

func TestCommentsPersistAndReturnNewestFirst(t *testing.T) {
	srv := NewServer(Config{RuntimeRole: "backend", DataDir: t.TempDir()})

	post(t, srv, "/api/v1/comments", `{"text":"I love how small and fast this is."}`, http.StatusOK)
	post(t, srv, "/api/v1/comments", `{"text":"I am disappointed and frustrated."}`, http.StatusOK)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/comments?limit=1", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("list returned %d: %s", rec.Code, rec.Body.String())
	}

	var payload struct {
		Items []Comment `json:"items"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if len(payload.Items) != 1 {
		t.Fatalf("items length=%d", len(payload.Items))
	}
	if payload.Items[0].Text != "I am disappointed and frustrated." || payload.Items[0].Label != Negative {
		t.Fatalf("unexpected newest record: %#v", payload.Items[0])
	}
	if payload.Items[0].Timestamp == "" {
		t.Fatalf("newest record missing timestamp: %#v", payload.Items[0])
	}
}

func TestCommentsListToleratesLegacyAndCurrentCSVRows(t *testing.T) {
	dataDir := t.TempDir()
	csvPath := filepath.Join(dataDir, "comments.csv")
	csvBody := strings.Join([]string{
		"timestamp,text,label,confidence,latency_ms",
		`"2026-03-16T11:59:22.294Z","I love how small and fast this is.","positive","1","8235"`,
		`comment-1779305010205722583,2026-05-20T19:23:30.205722583Z,I absolutely love this. Great work and fantastic experience.,positive,0.97,1`,
		"",
	}, "\n")
	if err := os.WriteFile(csvPath, []byte(csvBody), 0o644); err != nil {
		t.Fatal(err)
	}

	srv := NewServer(Config{RuntimeRole: "backend", CSVPath: csvPath})
	req := httptest.NewRequest(http.MethodGet, "/api/v1/comments?limit=25", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("list returned %d: %s", rec.Code, rec.Body.String())
	}
	var payload struct {
		Items []Comment `json:"items"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if len(payload.Items) != 2 {
		t.Fatalf("items length=%d, body=%s", len(payload.Items), rec.Body.String())
	}
	if payload.Items[0].ID != "comment-1779305010205722583" || payload.Items[0].Label != Positive {
		t.Fatalf("unexpected current row: %#v", payload.Items[0])
	}
	if payload.Items[1].ID == "" || payload.Items[1].Text != "I love how small and fast this is." {
		t.Fatalf("unexpected legacy row: %#v", payload.Items[1])
	}
}

func TestClassifyDoesNotPersistAndRejectsEmptyText(t *testing.T) {
	srv := NewServer(Config{RuntimeRole: "backend", DataDir: t.TempDir()})

	rec := post(t, srv, "/api/v1/sentiment/classify", `{"text":"Some parts are fine, but overall I am disappointed and frustrated."}`, http.StatusOK)
	if !strings.Contains(rec.Body.String(), `"label":"neutral"`) {
		t.Fatalf("mixed wording should classify neutral: %s", rec.Body.String())
	}

	rec = post(t, srv, "/api/v1/comments", `{"text":"   "}`, http.StatusBadRequest)
	if strings.TrimSpace(rec.Body.String()) != `{"error":"text is required"}` {
		t.Fatalf("unexpected empty text body: %s", rec.Body.String())
	}

	req := httptest.NewRequest(http.MethodGet, "/api/v1/comments?limit=25", nil)
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if strings.TrimSpace(rec.Body.String()) != `{"items":[]}` {
		t.Fatalf("classify persisted a comment or empty POST changed state: %s", rec.Body.String())
	}
}

func TestClassifyRejectsTrailingJSON(t *testing.T) {
	srv := NewServer(Config{RuntimeRole: "backend", DataDir: t.TempDir()})

	rec := post(t, srv, "/api/v1/sentiment/classify", `{"text":"clear enough"} {}`, http.StatusBadRequest)
	if strings.TrimSpace(rec.Body.String()) != `{"error":"invalid JSON body"}` {
		t.Fatalf("unexpected trailing JSON body: %s", rec.Body.String())
	}
}

func TestRuntimeRolesKeepFrontendAndBackendSeparate(t *testing.T) {
	backend := NewServer(Config{RuntimeRole: "backend", DataDir: t.TempDir()})
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()
	backend.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("backend role served frontend with status %d", rec.Code)
	}

	frontend := NewServer(Config{RuntimeRole: "frontend", BackendURL: "http://backend.example.test"})
	req = httptest.NewRequest(http.MethodGet, "/api/v1/comments", nil)
	rec = httptest.NewRecorder()
	frontend.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("frontend role handled API locally with status %d", rec.Code)
	}

	req = httptest.NewRequest(http.MethodGet, "/health", nil)
	rec = httptest.NewRecorder()
	frontend.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"role":"frontend"`) {
		t.Fatalf("frontend health returned %d: %s", rec.Code, rec.Body.String())
	}

	req = httptest.NewRequest(http.MethodGet, "/", nil)
	rec = httptest.NewRecorder()
	frontend.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("frontend role did not serve static assets: %d", rec.Code)
	}
}

func TestFrontendAPIProxyPrefersForwardedAccessToken(t *testing.T) {
	var gotAuth string
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		apphttp.WriteJSON(w, http.StatusOK, map[string][]Comment{"items": []Comment{}})
	}))
	t.Cleanup(backend.Close)

	frontend := NewServer(Config{RuntimeRole: "frontend", BackendURL: backend.URL})
	req := httptest.NewRequest(http.MethodGet, "/api/v1/comments", nil)
	req.Header.Set("Authorization", "Bearer id-token")
	req.Header.Set("X-Auth-Request-Access-Token", "access-token")
	rec := httptest.NewRecorder()
	frontend.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("frontend proxy returned %d: %s", rec.Code, rec.Body.String())
	}
	if gotAuth != "Bearer access-token" {
		t.Fatalf("Authorization=%q, want forwarded access token", gotAuth)
	}
}

func TestFrontendAPIProxyFallsBackToAuthorizationHeader(t *testing.T) {
	var gotAuth string
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		apphttp.WriteJSON(w, http.StatusOK, map[string][]Comment{"items": []Comment{}})
	}))
	t.Cleanup(backend.Close)

	frontend := NewServer(Config{RuntimeRole: "frontend", BackendURL: backend.URL})
	req := httptest.NewRequest(http.MethodGet, "/api/v1/comments", nil)
	req.Header.Set("Authorization", "Bearer existing-token")
	rec := httptest.NewRecorder()
	frontend.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("frontend proxy returned %d: %s", rec.Code, rec.Body.String())
	}
	if gotAuth != "Bearer existing-token" {
		t.Fatalf("Authorization=%q, want original authorization header", gotAuth)
	}
}

func TestAPIsRequireValidBearerTokenWhenOIDCEnabled(t *testing.T) {
	srv := NewServer(
		Config{RuntimeRole: "backend", AuthMode: "oidc", DataDir: t.TempDir()},
		fakeVerifier{claims: idpauth.UserClaims{Subject: "user-123", Groups: []string{"platform"}}},
	)

	post(t, srv, "/api/v1/comments", `{"text":"I love this."}`, http.StatusUnauthorized)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/comments", strings.NewReader(`{"text":"I love this."}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer invalid-token")
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("invalid token returned %d: %s", rec.Code, rec.Body.String())
	}

	req = httptest.NewRequest(http.MethodPost, "/api/v1/sentiment/classify", strings.NewReader(`{"text":"I love this."}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "bearer valid-token")
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("lower-case bearer scheme returned %d: %s", rec.Code, rec.Body.String())
	}

	req = httptest.NewRequest(http.MethodPost, "/api/v1/comments", strings.NewReader(`{"text":"I love this."}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer valid-token")
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("valid token returned %d: %s", rec.Code, rec.Body.String())
	}
}

func TestWhoamiExposesSafeIdentity(t *testing.T) {
	anonymous := NewServer(Config{RuntimeRole: "backend", AuthMode: "none", DataDir: t.TempDir()})
	req := httptest.NewRequest(http.MethodGet, "/api/whoami", nil)
	rec := httptest.NewRecorder()
	anonymous.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("anonymous whoami returned %d: %s", rec.Code, rec.Body.String())
	}
	if strings.TrimSpace(rec.Body.String()) != `{"sub":"anonymous","groups":[]}` {
		t.Fatalf("unexpected anonymous whoami: %s", rec.Body.String())
	}

	oidc := NewServer(
		Config{RuntimeRole: "backend", AuthMode: "oidc", DataDir: t.TempDir()},
		fakeVerifier{claims: idpauth.UserClaims{Subject: "user-123", PreferredUsername: "alice", Email: "alice@example.test", Groups: []string{"app-sentiment-dev"}}},
	)
	req = httptest.NewRequest(http.MethodGet, "/api/v1/whoami", nil)
	req.Header.Set("Authorization", "Bearer valid-token")
	rec = httptest.NewRecorder()
	oidc.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("oidc whoami returned %d: %s", rec.Code, rec.Body.String())
	}
	for _, text := range []string{`"sub":"user-123"`, `"preferred_username":"alice"`, `"email":"alice@example.test"`, `"groups":["app-sentiment-dev"]`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("whoami missing %q in %s", text, rec.Body.String())
		}
	}
}

func TestWhoamiRequiresBearerTokenWhenOIDCIsEnabled(t *testing.T) {
	srv := NewServer(
		Config{RuntimeRole: "backend", AuthMode: "oidc", DataDir: t.TempDir()},
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

func TestRuntimeConfigExposesFrontendAndAPIAuthModes(t *testing.T) {
	srv := NewServer(Config{
		RuntimeRole:     "frontend",
		AuthMode:        "none",
		APIAuthMode:     "oidc",
		BackendURL:      "http://apim-simulator:8080",
		APIBasePath:     "/api/v1",
		ShowNetworkPath: "true",
		NetworkHops:     `[{"label":"Browser","detail":"http://localhost:8304","role":"User agent"},{"label":"APIM simulator","detail":"http://apim-simulator:8080","role":"API gateway"}]`,
	})

	req := httptest.NewRequest(http.MethodGet, "/runtime-config.js", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("runtime config returned %d: %s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("runtime config Cache-Control=%q", got)
	}
	body := rec.Body.String()
	for _, text := range []string{
		`window.SENTIMENT_RUNTIME_CONFIG`,
		`"authMethod":"none"`,
		`"apiAuthMethod":"oidc"`,
		`"apiBasePath":"/api/v1"`,
		`"backendURL":"http://apim-simulator:8080"`,
		`"showNetworkPath":true`,
		`"label":"APIM simulator"`,
	} {
		if !strings.Contains(body, text) {
			t.Fatalf("runtime config missing %q in %s", text, body)
		}
	}
}

func TestFrontendKeepsThemeSwitcherParity(t *testing.T) {
	indexHTML, err := web.ReadFile("web/index.html")
	if err != nil {
		t.Fatal(err)
	}
	appJS, err := web.ReadFile("web/app.js")
	if err != nil {
		t.Fatal(err)
	}

	for _, text := range []string{`class="skip-link" href="#main"`, `<main id="main" tabindex="-1">`, `<header>`, `@social-5h3ll/5h3ll-ui`, `/app-shell.css`, `/app-shell.js`, `/idpauth.js`, `class="header-actions"`, `data-theme="system"`, `id="theme-switcher"`, `class="theme-toggle"`, `id="auth-state"`, `id="logout-btn" class="sign-in-link"`, `>Sign Out<`, `id="api-status" class="app-panel notice" role="status" aria-live="polite"`, `Checking API...`, `class="comment-actions"`, `aria-label="Sample comments"`, `data-sample="positive"`, `data-sample="mixed"`, `data-sample="negative"`, `class="analyse-action"`, `>Analyze<`, `id="diagnostics"`} {
		if !strings.Contains(string(indexHTML), text) {
			t.Fatalf("frontend index missing %q", text)
		}
	}
	html := string(indexHTML)
	if strings.Contains(html, `href="/style.css"`) {
		t.Fatalf("frontend should not load app-local CSS: %s", html)
	}
	for _, text := range []string{`id="login-btn"`, `>Sign In<`} {
		if strings.Contains(html, text) {
			t.Fatalf("protected frontend index must not render login control %q: %s", text, html)
		}
	}
	if strings.Contains(html, `<main class="shell">`) {
		t.Fatalf("frontend shell must use the shared bare main container: %s", html)
	}
	if strings.Index(html, `<header>`) > strings.Index(html, `<section `) {
		t.Fatalf("frontend shell header must be the first app section before content: %s", html)
	}
	if strings.Index(html, `id="api-status"`) > strings.Index(html, `id="comment-form"`) {
		t.Fatalf("frontend API status must render before comment form: %s", html)
	}
	if strings.Index(html, `id="logout-btn"`) > strings.Index(html, `id="theme-switcher"`) {
		t.Fatalf("frontend shell actions must be ordered auth, sign out, theme: %s", html)
	}
	if strings.Index(html, `id="comments"`) > strings.Index(html, `id="diagnostics"`) {
		t.Fatalf("frontend diagnostics must render after comments: %s", html)
	}
	for _, text := range []string{
		"PlatformAppShell",
		"initializeThemeSwitcher()",
		"requireElement",
		"requireSelector",
		"buttonSelector",
		`buttonSelector('[data-action="analyze"]')`,
		"textAreaElement",
		"withSubmitterBusy",
		"renderNetworkPathInto",
		"resolveNetworkHops",
		"fetchJSON",
		"fetchJSONWithTiming",
		"errorMessage",
		"apiTimingElement",
		"renderElementsInto",
		`readRuntimeConfig("SENTIMENT_RUNTIME_CONFIG")`,
		"checkHealth()",
		"formatAPIHealthStatus(data, runtimeConfig())",
		"apiReadyForUserAction()",
		"apiActionReady(runtimeConfig())",
		"usesGatewayAuth(runtimeConfig())",
		"authRequiredMessage()",
		`apiAuthRequiredMessage("using sentiment analysis")`,
		"apiErrorMessage(runtimeConfig(), error",
		"API authentication is disabled for this environment",
		"usesGatewayAuth(runtimeConfig())",
		"PlatformIdpAuth",
		"initializeGatewayAuthState(authState, logoutButton)",
		"bindGatewayLogout(",
		"timedFetchJSON(",
		"apiPath(runtimeConfig()",
		"formatTimestamp(item.timestamp)",
		`[data-sample="negative"]`,
		"I am disappointed and frustrated. This was a poor experience.",
		"fetchJSONWithTiming(url",
		"decodeAPIMTrace",
		"apiBasePath",
		"backendURL",
		"apiJSONHeaders(runtimeConfig())",
		"apiTimingElement(timing",
		"renderNetworkPathInto(",
		"renderStatusInto(statusEl",
		"diagnosticsEl.replaceChildren(",
		"configuredNetworkHops()",
		"shouldShowNetworkPath(runtimeConfig())",
	} {
		if !strings.Contains(string(appJS), text) {
			t.Fatalf("frontend app.js missing %q", text)
		}
	}
	for _, text := range []string{
		"function fetchGatewaySession",
		"function normalizeGatewaySession",
		"function gatewayDisplayName",
		"function readThemeCookie",
		"function writeThemeCookie",
		"function themeCookieDomain",
		"function requireElement",
		"HTMLButtonElement",
		`requireSelector('[data-action="analyze"]')`,
		"function textAreaElement",
		"async function parseJSONResponse",
		"parseJSONResponse(response)",
		"const response = await fetch(url",
		"function isNetworkHop",
		"traceId: response.headers.get",
		"correlationId: response.headers.get",
		"<summary>Network Path",
		"fetchGatewaySession()",
		"writeGatewayAuthState(authState, logoutButton, session)",
		"function usesGatewayAuth",
		"function expiredSessionMessage",
		"function authSessionExpired",
		"function escapeHTML",
		"commentsEl.innerHTML",
		"diagnosticsEl.innerHTML",
		"renderAPITiming(timing",
		"renderNetworkPath(configuredNetworkHops())",
		`<article class="comment">`,
		"error.message",
		`Array<[string, string | number | boolean | null | undefined]>`,
		"statusEl.textContent",
		"window.SENTIMENT_RUNTIME_CONFIG",
		"The backend validates JWT/OIDC tokens, so this frontend",
	} {
		if strings.Contains(string(appJS), text) {
			t.Fatalf("frontend app.js should use shared helper instead of %q", text)
		}
	}
	for _, text := range []string{"pce-theme", "document.cookie"} {
		if strings.Contains(string(appJS), text) {
			t.Fatalf("theme implementation must live in shared app shell, not app.js %q", text)
		}
	}

	sharedReq := httptest.NewRequest(http.MethodGet, "/app-shell.css", nil)
	sharedRec := httptest.NewRecorder()
	appshell.Stylesheet(sharedRec, sharedReq)
	if !strings.Contains(sharedRec.Body.String(), `:root[data-theme="dark"]`) {
		t.Fatalf("shared app shell CSS missing explicit dark theme override")
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

func post(t *testing.T, handler http.Handler, path string, body string, want int) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != want {
		t.Fatalf("%s returned %d, want %d: %s", path, rec.Code, want, rec.Body.String())
	}
	return rec
}
