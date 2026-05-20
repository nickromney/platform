package app

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
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

	req = httptest.NewRequest(http.MethodGet, "/signed-out.html", nil)
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("signed-out page returned %d: %s", rec.Code, rec.Body.String())
	}
	for _, text := range []string{
		"Sentiment",
		"Signed out",
		"Sign in now",
		"/.auth/login/sso",
		`id="theme-switcher"`,
		`class="theme-toggle"`,
		"redirect-delay",
		"Redirecting to sign in in 5 seconds",
		"pce-theme",
		"setTimeout(() => {",
		"window.location.assign(loginLink.href)",
		"5000",
	} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("signed-out page missing %q: %s", text, rec.Body.String())
		}
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

func TestAPIsRequireValidBearerTokenWhenOIDCEnabled(t *testing.T) {
	srv := NewServer(
		Config{RuntimeRole: "backend", AuthMode: "oidc", DataDir: t.TempDir()},
		fakeVerifier{claims: UserClaims{Subject: "user-123", Groups: []string{"platform"}}},
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
		fakeVerifier{claims: UserClaims{Subject: "user-123", PreferredUsername: "alice", Email: "alice@example.test", Groups: []string{"app-sentiment-dev"}}},
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

	for _, text := range []string{`<main>`, `<header>`, `class="header-actions"`, `data-theme="system"`, `id="theme-switcher"`, `class="theme-toggle"`, `data-theme-icon="light"`, `data-theme-icon="dark"`, `data-theme-icon="system"`, `id="auth-state"`, `id="login-btn"`, `>Sign In<`, `id="logout-btn"`, `>Sign Out<`, `id="diagnostics"`} {
		if !strings.Contains(string(indexHTML), text) {
			t.Fatalf("frontend index missing %q", text)
		}
	}
	html := string(indexHTML)
	if strings.Contains(html, `<main class="shell">`) {
		t.Fatalf("frontend shell must use the shared bare main container: %s", html)
	}
	if strings.Index(html, `<header>`) > strings.Index(html, `<section>`) {
		t.Fatalf("frontend shell header must be the first app section before content: %s", html)
	}
	if strings.Index(html, `id="login-btn"`) > strings.Index(html, `id="logout-btn"`) ||
		strings.Index(html, `id="logout-btn"`) > strings.Index(html, `id="theme-switcher"`) {
		t.Fatalf("frontend shell actions must be ordered auth, sign in, sign out, theme: %s", html)
	}
	for _, text := range []string{
		"readThemeCookie()",
		"writeThemeCookie(nextTheme)",
		"pce-theme",
		"themeCookieDomain",
		"document.cookie",
		"toggleTheme",
		"themePreference",
		`matchMedia("(prefers-color-scheme: dark)")`,
		`["system", "light", "dark"]`,
		"window.SENTIMENT_RUNTIME_CONFIG",
		"apiReadyForUserAction()",
		"authRequiredMessage()",
		"Sign in before using sentiment analysis",
		"expiredSessionMessage()",
		"Session expired. Sign out and sign in again to refresh API access.",
		"authSessionExpired(error)",
		"invalid or expired access token",
		"API authentication is disabled for this environment",
		"usesGatewayAuth()",
		"fetchGatewaySession()",
		"fetch(\"/.auth/me\"",
		"payload.clientPrincipal",
		"gatewayDisplayName(session)",
		"/oauth2/sign_out?rd=/signed-out.html",
		"timedFetchJSON(",
		"apiURL(",
		"apiBasePath",
		"backendURL",
		"x-apim-trace",
		"x-apim-trace-id",
		"x-correlation-id",
		"Request (UTC)",
		"Response (UTC)",
		"API Call Timing",
		"Network Path",
		"configuredNetworkHops()",
		"showNetworkPath",
	} {
		if !strings.Contains(string(appJS), text) {
			t.Fatalf("frontend app.js missing %q", text)
		}
	}
	if strings.Contains(string(appJS), `localStorage.setItem("theme"`) {
		t.Fatalf("theme preference must be written to the shared cookie, not localStorage")
	}

	styleCSS, err := web.ReadFile("web/style.css")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(styleCSS), `:root[data-theme="dark"]`) {
		t.Fatalf("frontend style.css missing explicit dark theme override")
	}
}

type fakeVerifier struct {
	claims UserClaims
	err    error
}

func (v fakeVerifier) Verify(_ context.Context, token string) (UserClaims, error) {
	if token != "valid-token" {
		return UserClaims{}, ErrInvalidToken
	}
	if v.err != nil {
		return UserClaims{}, v.err
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
