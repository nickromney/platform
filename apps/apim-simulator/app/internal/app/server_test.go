package app

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"platform.local/idpauth"
)

type staticVerifier struct {
	claims idpauth.UserClaims
	err    error
}

func (v staticVerifier) Verify(context.Context, string) (idpauth.UserClaims, error) {
	if v.err != nil {
		return idpauth.UserClaims{}, v.err
	}
	return v.claims, nil
}

func TestHealthAndEmbeddedConsole(t *testing.T) {
	srv := NewServer(Config{AllowAnonymous: true}, nil)

	for _, path := range []string{"/apim/health", "/apim/startup"} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		rec := httptest.NewRecorder()
		srv.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s returned %d: %s", path, rec.Code, rec.Body.String())
		}
		if path == "/apim/health" {
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
		}
	}

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("console returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "APIM Simulator") {
		t.Fatalf("console did not render APIM shell: %s", rec.Body.String())
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
}

func TestEmbeddedConsoleHeadRequestsReturnHeadersOnly(t *testing.T) {
	srv := NewServer(Config{AllowAnonymous: true}, nil)

	req := httptest.NewRequest(http.MethodHead, "/", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("console HEAD returned %d: %s", rec.Code, rec.Body.String())
	}
	if rec.Body.Len() != 0 {
		t.Fatalf("console HEAD returned body: %s", rec.Body.String())
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("console HEAD Cache-Control=%q", got)
	}
	if got := rec.Header().Get("Content-Type"); !strings.Contains(got, "text/html") {
		t.Fatalf("console HEAD Content-Type=%q", got)
	}
}

func TestGatewayIdentityEndpointUsesOAuth2ProxyHeaders(t *testing.T) {
	srv := NewServer(Config{AllowAnonymous: true}, nil)

	req := httptest.NewRequest(http.MethodGet, "/.auth/me", nil)
	req.Header.Set("X-Auth-Request-Email", "demo@admin.test")
	req.Header.Set("X-Auth-Request-Preferred-Username", "demo")
	req.Header.Set("X-Auth-Request-Groups", "platform-admins,platform-viewers")
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("identity endpoint returned %d: %s", rec.Code, rec.Body.String())
	}
	for _, text := range []string{
		`"provider_name":"oauth2-proxy"`,
		`"user_id":"demo@admin.test"`,
		`"typ":"preferred_username","val":"demo"`,
		`"typ":"email","val":"demo@admin.test"`,
		`"typ":"groups","val":"platform-admins"`,
		`"typ":"groups","val":"platform-viewers"`,
	} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("identity payload missing %q in %s", text, rec.Body.String())
		}
	}
}

func TestServerUsesSharedRequestBodyReader(t *testing.T) {
	source, err := os.ReadFile("server.go")
	if err != nil {
		t.Fatal(err)
	}
	text := string(source)
	if !strings.Contains(text, "apphttp.ReadRequestBody(") {
		t.Fatalf("server.go should use shared apphttp.ReadRequestBody for raw request bodies")
	}
	if strings.Contains(text, "io.ReadAll(r.Body)") {
		t.Fatalf("server.go should not read request bodies with io.ReadAll directly")
	}
}

func TestEmbeddedConsoleRendersGatewayIdentityControls(t *testing.T) {
	indexHTML, err := web.ReadFile("web/index.html")
	if err != nil {
		t.Fatal(err)
	}
	appJS, err := web.ReadFile("web/app.js")
	if err != nil {
		t.Fatal(err)
	}

	for _, text := range []string{
		`<html lang="en" data-theme="system">`,
		`id="auth-state"`,
		`Not signed in.`,
		`id="logout-btn" class="sign-in-link" type="button" hidden`,
		`>Sign Out<`,
		`id="status" class="app-panel notice" role="status" aria-live="polite"`,
		`<label for="tenant-key">Tenant Key</label>`,
		`id="tenant-key" name="tenant_key"`,
		`<label for="method">HTTP method</label>`,
		`id="method" name="method"`,
		`<label for="path">Request path</label>`,
		`id="path" name="path"`,
		`<label for="headers">Request headers</label>`,
		`id="headers" name="headers"`,
		`<label for="body">Request body</label>`,
		`id="body" name="body"`,
		`/idpauth.js`,
		`/app-shell.js`,
	} {
		if !strings.Contains(string(indexHTML), text) {
			t.Fatalf("console index missing %q", text)
		}
	}
	for _, text := range []string{
		`PlatformIdpAuth`,
		`PlatformAppShell`,
		`initializeThemeSwitcher()`,
		`fetchJSON`,
		`errorMessage`,
		`parseJSONObjectText`,
		`renderJSONInto`,
		`setText`,
		`renderSummaryListInto`,
		`withButtonBusy`,
		`withSubmitterBusy`,
		`buttonElement`,
		`requireElement`,
		`inputElement`,
		`selectElement`,
		`textAreaElement`,
		`initializeGatewayAuthState(authState, logoutButton`,
		`errorMessage: (error) =>`,
		`bindGatewayLogout(logoutButton)`,
	} {
		if !strings.Contains(string(appJS), text) {
			t.Fatalf("console app missing %q", text)
		}
	}
	for _, text := range []string{
		`function normalizeGatewaySession`,
		`function gatewayDisplayName`,
		`function gatewayLogoutURL`,
		`function readThemeCookie`,
		`function writeThemeCookie`,
		`function themeCookieDomain`,
		`function escapeHTML`,
		`function formatError`,
		`error instanceof Error ? error.message : String(error)`,
		`JSON.stringify(data, null, 2)`,
		`JSON.stringify(payload.items, null, 2)`,
		`writeGatewayAuthState(authState, logoutButton, session)`,
		`fetchGatewaySession()`,
		`response.json()`,
		`return parseJSONResponse(response)`,
		`throw new Error(await response.text())`,
		`function inputElement`,
		`function selectElement`,
		`function textAreaElement`,
		`HTMLButtonElement`,
		`replayResult.textContent`,
		`traces.textContent`,
		`metricApis.textContent`,
		`metricRoutes.textContent`,
		`metricProducts.textContent`,
		`metricSubscriptions.textContent`,
	} {
		if strings.Contains(string(appJS), text) {
			t.Fatalf("console app should use shared helper instead of %q", text)
		}
	}
	for _, text := range []string{"pce-theme", "document.cookie"} {
		if strings.Contains(string(appJS), text) {
			t.Fatalf("theme implementation must live in shared app shell, not app.js %q", text)
		}
	}

	srv := NewServer(Config{AllowAnonymous: true}, nil)
	req := httptest.NewRequest(http.MethodGet, "/signed-out.html", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("signed-out page returned %d: %s", rec.Code, rec.Body.String())
	}
	for _, text := range []string{
		`<title>Signed out - APIM Simulator</title>`,
		`id="login-link"`,
		`>Sign in now<`,
		`Your APIM simulator session has ended.`,
	} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("signed-out page missing %q: %s", text, rec.Body.String())
		}
	}
}

func TestGatewayProxiesHostMatchedRouteAndRecordsTrace(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/health" {
			t.Fatalf("unexpected upstream path %s", r.URL.Path)
		}
		if r.Header.Get("X-Apim-User-Object-Id") != "user-123" {
			t.Fatalf("missing forwarded identity header")
		}
		w.Header().Set("X-Upstream", "ok")
		_, _ = w.Write([]byte(`{"status":"ready"}`))
	}))
	defer backend.Close()

	srv := NewServer(Config{
		AllowAnonymous: false,
		Routes: []RouteConfig{{
			Name:               "subnetcalc-dev",
			HostMatch:          []string{"subnetcalc.dev.127.0.0.1.sslip.io"},
			PathPrefix:         "/api",
			UpstreamBaseURL:    backend.URL,
			UpstreamPathPrefix: "/api",
		}},
	}, staticVerifier{claims: idpauth.UserClaims{Subject: "user-123", Email: "demo@example.test", Groups: []string{"users"}}})

	req := httptest.NewRequest(http.MethodGet, "http://subnetcalc.dev.127.0.0.1.sslip.io/api/v1/health", nil)
	req.Header.Set("Authorization", "Bearer good")
	req.Header.Set("X-Apim-Trace", "true")
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("proxy returned %d: %s", rec.Code, rec.Body.String())
	}
	if rec.Header().Get("X-Apim-Simulator") != "apim-simulator-go" {
		t.Fatalf("missing simulator response header")
	}
	if rec.Header().Get("X-Apim-Trace-Id") == "" {
		t.Fatalf("missing trace id")
	}

	req = httptest.NewRequest(http.MethodGet, "/apim/management/traces", nil)
	req.Header.Set("X-Apim-Tenant-Key", "local-dev-tenant-key")
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("traces returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "subnetcalc-dev") {
		t.Fatalf("trace payload missing route: %s", rec.Body.String())
	}
}

func TestGatewayEnforcesRouteAuthorizationPolicy(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"status":"ready"}`))
	}))
	defer backend.Close()

	srv := NewServer(Config{
		AllowAnonymous: false,
		Routes: []RouteConfig{{
			Name:            "admin-api",
			PathPrefix:      "/admin",
			UpstreamBaseURL: backend.URL,
			Authz: RouteAuthzConfig{
				RequiredGroups: []string{"platform-admins"},
				RequiredRoles:  []string{"approver"},
				RequiredClaims: map[string]string{"email": "alex@example.test"},
			},
		}},
	}, staticVerifier{claims: idpauth.UserClaims{
		Subject: "user-123",
		Email:   "alex@example.test",
		Groups:  []string{"platform-admins"},
		Roles:   []string{"approver"},
	}})

	req := httptest.NewRequest(http.MethodGet, "/admin/health", nil)
	req.Header.Set("Authorization", "Bearer good")
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("authorized route returned %d: %s", rec.Code, rec.Body.String())
	}

	denied := NewServer(Config{
		AllowAnonymous: false,
		Routes: []RouteConfig{{
			Name:            "admin-api",
			PathPrefix:      "/admin",
			UpstreamBaseURL: backend.URL,
			Authz:           RouteAuthzConfig{RequiredRoles: []string{"operator"}},
		}},
	}, staticVerifier{claims: idpauth.UserClaims{
		Subject: "user-123",
		Email:   "alex@example.test",
		Groups:  []string{"platform-admins"},
		Roles:   []string{"approver"},
	}})

	req = httptest.NewRequest(http.MethodGet, "/admin/health", nil)
	req.Header.Set("Authorization", "Bearer good")
	rec = httptest.NewRecorder()
	denied.ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("unauthorized route returned %d: %s", rec.Code, rec.Body.String())
	}
	if strings.TrimSpace(rec.Body.String()) != `{"error":"missing required role"}` {
		t.Fatalf("unexpected authorization error body: %s", rec.Body.String())
	}
}

func TestManagementSummaryReplayAndTenantKey(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer backend.Close()

	srv := NewServer(Config{
		AllowAnonymous: true,
		TenantAccess:   TenantAccessConfig{Enabled: true, PrimaryKey: "tenant"},
		Products:       map[string]ProductConfig{"default": {Name: "Default", RequireSubscription: false}},
		Subscriptions:  SubscriptionConfig{Required: false},
		APIs: map[string]APIConfig{"default": {
			Name:               "Default API",
			Path:               "api",
			UpstreamBaseURL:    backend.URL,
			UpstreamPathPrefix: "/api",
		}},
	}, nil)

	req := httptest.NewRequest(http.MethodGet, "/apim/management/summary", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("management without tenant key returned %d", rec.Code)
	}

	req = httptest.NewRequest(http.MethodGet, "/apim/management/summary", nil)
	req.Header.Set("X-Apim-Tenant-Key", "tenant")
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("summary returned %d: %s", rec.Code, rec.Body.String())
	}
	var summary map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &summary); err != nil {
		t.Fatal(err)
	}
	if len(summary["apis"].([]any)) != 1 || len(summary["routes"].([]any)) != 1 {
		t.Fatalf("summary did not expose api-derived route: %s", rec.Body.String())
	}

	req = httptest.NewRequest(http.MethodPost, "/apim/management/replay", strings.NewReader(`{"method":"GET","path":"/api/health","headers":{"x-apim-trace":"true"}}`))
	req.Header.Set("X-Apim-Tenant-Key", "tenant")
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("replay returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"status_code":200`) {
		t.Fatalf("replay did not include status code: %s", rec.Body.String())
	}
}

func TestManagementResourceCollectionsRetainAPIMSurface(t *testing.T) {
	srv := NewServer(Config{
		AllowAnonymous: true,
		TenantAccess:   TenantAccessConfig{Enabled: true, PrimaryKey: "tenant"},
		Products:       map[string]ProductConfig{"starter": {Name: "Starter", RequireSubscription: true}},
		NamedValues:    map[string]NamedValueConfig{"base-url": {Value: "https://example.test", Secret: false}},
		Subscriptions: SubscriptionConfig{Items: map[string]Subscription{
			"starter-sub": {ID: "starter-sub", Name: "Starter", Keys: SubscriptionKeys{Primary: "p", Secondary: "s"}, Products: []string{"starter"}},
		}},
		APIs: map[string]APIConfig{"starter-api": {Name: "Starter API", Path: "starter", UpstreamBaseURL: "http://example.test"}},
	}, nil)

	for _, path := range []string{
		"/apim/management/service",
		"/apim/management/apis",
		"/apim/management/products",
		"/apim/management/subscriptions",
		"/apim/management/named-values",
	} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		req.Header.Set("X-Apim-Tenant-Key", "tenant")
		rec := httptest.NewRecorder()
		srv.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s returned %d: %s", path, rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "items") && !strings.Contains(rec.Body.String(), "service") {
			t.Fatalf("%s did not return management payload: %s", path, rec.Body.String())
		}
	}

	req := httptest.NewRequest(http.MethodPost, "/apim/management/products", strings.NewReader(`{"id":"pro","name":"Pro","require_subscription":false}`))
	req.Header.Set("X-Apim-Tenant-Key", "tenant")
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("product create returned %d: %s", rec.Code, rec.Body.String())
	}

	req = httptest.NewRequest(http.MethodPost, "/apim/management/products", strings.NewReader(`{"id":"too-large","name":"`+strings.Repeat("x", 1<<20)+`"}`))
	req.Header.Set("X-Apim-Tenant-Key", "tenant")
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("oversized product payload returned %d: %s", rec.Code, rec.Body.String())
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"Invalid product payload"}` {
		t.Fatalf("oversized product error payload=%q", got)
	}

	req = httptest.NewRequest(http.MethodPost, "/apim/management/products", strings.NewReader(`{"id":"bad","name":"Bad"} {}`))
	req.Header.Set("X-Apim-Tenant-Key", "tenant")
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("trailing JSON product payload returned %d: %s", rec.Code, rec.Body.String())
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"Invalid product payload"}` {
		t.Fatalf("trailing JSON product error payload=%q", got)
	}

	req = httptest.NewRequest(http.MethodDelete, "/apim/management/products/pro", nil)
	req.Header.Set("X-Apim-Tenant-Key", "tenant")
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("product delete returned %d: %s", rec.Code, rec.Body.String())
	}
}

func TestMCPAPIConfigMaterializesBrokerRoutes(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/sse" {
			t.Fatalf("unexpected MCP upstream path %s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`event: ready`))
	}))
	defer backend.Close()

	srv := NewServer(Config{
		AllowAnonymous: true,
		APIs: map[string]APIConfig{"mcp": {
			Name:            "MCP Server",
			Path:            "mcp",
			Type:            "mcp",
			UpstreamBaseURL: backend.URL,
			MCPProperties: &MCPPropertiesConfig{
				TransportType: "sse",
				Endpoints: []MCPEndpointConfig{{
					Name:        "sse",
					URITemplate: "/sse",
				}},
			},
		}},
	}, nil)

	req := httptest.NewRequest(http.MethodGet, "/mcp/sse", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("mcp proxy returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "ready") {
		t.Fatalf("mcp proxy did not return upstream response: %s", rec.Body.String())
	}
}

func TestMCPAPIConfigAcceptsARMStylePropertyNames(t *testing.T) {
	var cfg Config
	err := json.Unmarshal([]byte(`{
		"allow_anonymous": true,
		"apis": {
			"platform-mcp": {
				"name": "Platform MCP",
				"path": "mcp",
				"type": "mcp",
				"upstream_base_url": "http://platform-mcp.mcp.svc.cluster.local:8080",
				"mcpProperties": {
					"transportType": "streamable",
					"endpoints": [
						{"name": "message", "uriTemplate": "/mcp"}
					]
				}
			}
		}
	}`), &cfg)
	if err != nil {
		t.Fatal(err)
	}
	cfg.ApplyRuntimeDefaults()
	if len(cfg.Routes) != 1 {
		t.Fatalf("expected one materialized MCP route, got %d", len(cfg.Routes))
	}
	route := cfg.Routes[0]
	if route.PathPrefix != "/mcp/mcp" || route.UpstreamPathPrefix != "/mcp" {
		t.Fatalf("unexpected materialized MCP route: %#v", route)
	}
	if route.Metadata["mcp_transport"] != "streamable" {
		t.Fatalf("missing MCP transport metadata: %#v", route.Metadata)
	}
}

func TestSubscriptionKeyIsRequiredWhenConfigured(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer backend.Close()

	srv := NewServer(Config{
		AllowAnonymous: true,
		Subscriptions: SubscriptionConfig{
			Required:    true,
			HeaderNames: []string{"Ocp-Apim-Subscription-Key"},
			Items: map[string]Subscription{
				"demo": {ID: "sub-demo", Name: "demo", Keys: SubscriptionKeys{Primary: "primary", Secondary: "secondary"}},
			},
		},
		Routes: []RouteConfig{{Name: "api", PathPrefix: "/api", UpstreamBaseURL: backend.URL, UpstreamPathPrefix: "/api"}},
	}, nil)

	req := httptest.NewRequest(http.MethodGet, "/api/health", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("missing subscription key returned %d", rec.Code)
	}

	req = httptest.NewRequest(http.MethodGet, "/api/health", nil)
	req.Header.Set("Ocp-Apim-Subscription-Key", "primary")
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("valid subscription key returned %d: %s", rec.Code, rec.Body.String())
	}
}
