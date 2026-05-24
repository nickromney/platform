package app

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"platform.local/apphttp"
	"platform.local/appshell"
	"platform.local/idpauth"
)

func TestHealthAndStaticFrontend(t *testing.T) {
	srv := NewServer(Config{AuthMode: "none"}, nil)

	for _, path := range []string{"/api/v1/health", "/api/v1/health/ready", "/api/v1/health/live"} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		rec := httptest.NewRecorder()
		srv.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s returned %d: %s", path, rec.Code, rec.Body.String())
		}
		if path == "/api/v1/health" {
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
		t.Fatalf("frontend returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "IPv4 Subnet Calculator") {
		t.Fatalf("frontend did not contain heading: %s", rec.Body.String())
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
		"IPv4 Subnet Calculator",
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
	files := []string{"server.go", "calculator.go", "types.go"}
	sources := make(map[string]string, len(files))
	for _, file := range files {
		source, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		sources[file] = string(source)
	}
	combined := sources["server.go"] + sources["calculator.go"] + sources["types.go"]

	for _, text := range []string{
		"apphttp.WriteError(",
		"apphttp.DecodeJSONError(",
		"apphttp.NewAPIProxy(apphttp.APIProxyConfig{",
	} {
		if !strings.Contains(combined, text) {
			t.Fatalf("subnetcalc should use shared HTTP helper %q", text)
		}
	}
	for _, text := range []string{"type errorResponse", "errorResponse{"} {
		if strings.Contains(combined, text) {
			t.Fatalf("subnetcalc should not keep local JSON error helper %q", text)
		}
	}
}

func TestRuntimeRolesKeepFrontendAndBackendSeparate(t *testing.T) {
	backend := NewServer(Config{AuthMode: "none", RuntimeRole: "backend"}, nil)
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()
	backend.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("backend role served frontend with status %d", rec.Code)
	}

	frontend := NewServer(Config{RuntimeRole: "frontend", BackendURL: "http://backend.example.test"}, nil)
	req = httptest.NewRequest(http.MethodGet, "/api/v1/health", nil)
	rec = httptest.NewRecorder()
	frontend.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("frontend role handled API locally with status %d", rec.Code)
	}

	req = httptest.NewRequest(http.MethodGet, "/", nil)
	rec = httptest.NewRecorder()
	frontend.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("frontend role did not serve static assets: %d", rec.Code)
	}

	req = httptest.NewRequest(http.MethodGet, "/runtime-config.js", nil)
	rec = httptest.NewRecorder()
	frontend.ServeHTTP(rec, req)
	if !strings.Contains(rec.Body.String(), `"backendURL":"http://backend.example.test"`) {
		t.Fatalf("runtime config did not expose frontend backend route: %s", rec.Body.String())
	}
}

func TestFrontendAPIProxyPrefersForwardedAccessToken(t *testing.T) {
	var gotAuth string
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		apphttp.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	}))
	t.Cleanup(backend.Close)

	frontend := NewServer(Config{RuntimeRole: "frontend", BackendURL: backend.URL}, nil)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/ipv4/validate", strings.NewReader(`{"ip":"10.0.0.1"}`))
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

func TestFrontendRendersE2ESubnetcalcResultSections(t *testing.T) {
	appJS, err := web.ReadFile("web/app.js")
	if err != nil {
		t.Fatal(err)
	}
	indexHTML, err := web.ReadFile("web/index.html")
	if err != nil {
		t.Fatal(err)
	}
	styleCSS, err := web.ReadFile("web/style.css")
	if err != nil {
		t.Fatal(err)
	}

	required := []string{
		"Validation",
		"Private Address Check",
		"Cloudflare Check",
		"Provider Range Check",
		"Subnet Information",
		"Performance Timing",
		"apiTimingElement",
		"renderNetworkPathInto(",
		"Total Response Time",
	}
	for _, text := range required {
		if !strings.Contains(string(appJS), text) {
			t.Fatalf("frontend app.js missing %q", text)
		}
	}
	for _, text := range []string{"provider-form", "provider-ranges/check"} {
		if !strings.Contains(string(indexHTML)+string(appJS), text) {
			t.Fatalf("frontend missing %q", text)
		}
	}
	if !strings.Contains(string(appJS), `requireSelectorAll("[data-example]")`) {
		t.Fatalf("frontend must use shared selector helper for example buttons")
	}
	if strings.Contains(string(appJS), `document.querySelectorAll("[data-example]")`) {
		t.Fatalf("frontend must not query example buttons directly")
	}
	if !strings.Contains(string(appJS), `withSubmitterBusy(event, "Loading",`) ||
		!strings.Contains(string(appJS), `withSubmitterBusy(event, "Validating",`) {
		t.Fatalf("frontend must use shared submit busy helper for lookup and token validation")
	}
	if !strings.Contains(string(appJS), `setText(content, "Loading...")`) {
		t.Fatalf("frontend must use shared text helper for loading results")
	}
	if strings.Contains(string(appJS), `content.textContent = "Loading..."`) {
		t.Fatalf("frontend must not write loading results text directly")
	}
	for _, text := range []string{"network-plan-form", "Network Plan", "network-plan/allocate"} {
		if strings.Contains(string(indexHTML)+string(appJS), text) {
			t.Fatalf("frontend must not expose removed network allocation feature %q", text)
		}
	}
	for _, text := range []string{"textarea"} {
		if !strings.Contains(string(styleCSS), text) {
			t.Fatalf("frontend CSS missing %q", text)
		}
	}
	sharedReq := httptest.NewRequest(http.MethodGet, "/app-shell.css", nil)
	sharedRec := httptest.NewRecorder()
	appshell.Stylesheet(sharedRec, sharedReq)
	if !strings.Contains(sharedRec.Body.String(), "box-sizing: border-box") {
		t.Fatalf("shared app shell CSS missing global box-sizing reset")
	}
}

func TestNetworkPlanEndpointIsRemoved(t *testing.T) {
	srv := NewServer(Config{AuthMode: "none"}, nil)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/network-plan/allocate", strings.NewReader(`{"parent":"10.0.0.0/24"}`))
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("removed network plan endpoint returned %d: %s", rec.Code, rec.Body.String())
	}
}

func TestFrontendThemeSupportsSystemPreference(t *testing.T) {
	appJS, err := web.ReadFile("web/app.js")
	if err != nil {
		t.Fatal(err)
	}
	indexHTML, err := web.ReadFile("web/index.html")
	if err != nil {
		t.Fatal(err)
	}
	srv := NewServer(Config{RuntimeRole: "frontend"}, nil)
	req := httptest.NewRequest(http.MethodGet, "/signed-out.html", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("signed-out page returned %d: %s", rec.Code, rec.Body.String())
	}
	signedOutHTML := rec.Body.String()

	for _, text := range []string{
		`data-theme="system"`,
		`/app-shell.js`,
		"PlatformAppShell",
		`readRuntimeConfig("SUBNETCALC_RUNTIME_CONFIG")`,
		"initializeThemeSwitcher()",
	} {
		if !strings.Contains(string(indexHTML)+signedOutHTML+string(appJS), text) {
			t.Fatalf("frontend theme support missing %q", text)
		}
	}
	for _, text := range []string{
		"function readThemeCookie",
		"function writeThemeCookie",
		"function themeCookieDomain",
		`document.cookie`,
		`localStorage.setItem("theme"`,
	} {
		if strings.Contains(string(appJS), text) {
			t.Fatalf("theme implementation must live in shared app shell, not app.js %q", text)
		}
	}
	sharedReq := httptest.NewRequest(http.MethodGet, "/app-shell.css", nil)
	sharedRec := httptest.NewRecorder()
	appshell.Stylesheet(sharedRec, sharedReq)
	if !strings.Contains(sharedRec.Body.String(), `:root[data-theme="dark"]`) {
		t.Fatalf("shared app shell CSS must support explicit dark theme")
	}
}

func TestIPv4SubnetInfoPreservesCloudModes(t *testing.T) {
	srv := NewServer(Config{AuthMode: "none"}, nil)

	tests := []struct {
		name        string
		mode        string
		wantUsable  int64
		wantFirst   string
		wantLast    string
		wantNetwork string
	}{
		{"azure", "Azure", 251, "192.168.1.4", "192.168.1.254", "192.168.1.0"},
		{"aws", "AWS", 251, "192.168.1.4", "192.168.1.254", "192.168.1.0"},
		{"oci", "OCI", 253, "192.168.1.2", "192.168.1.254", "192.168.1.0"},
		{"standard", "Standard", 254, "192.168.1.1", "192.168.1.254", "192.168.1.0"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			body := strings.NewReader(`{"network":"192.168.1.0/24","mode":"` + tt.mode + `"}`)
			req := httptest.NewRequest(http.MethodPost, "/api/v1/ipv4/subnet-info", body)
			rec := httptest.NewRecorder()
			srv.ServeHTTP(rec, req)
			if rec.Code != http.StatusOK {
				t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
			}

			var got map[string]any
			if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
				t.Fatal(err)
			}
			if got["network_address"] != tt.wantNetwork || got["first_usable_ip"] != tt.wantFirst || got["last_usable_ip"] != tt.wantLast {
				t.Fatalf("unexpected range: %#v", got)
			}
			if got["netmask"] != "255.255.255.0" || got["wildcard_mask"] != "0.0.0.255" {
				t.Fatalf("unexpected masks: %#v", got)
			}
			if int64(got["usable_addresses"].(float64)) != tt.wantUsable {
				t.Fatalf("usable_addresses=%v, want %d", got["usable_addresses"], tt.wantUsable)
			}
		})
	}
}

func TestIPv4SpecialSubnetsAndValidation(t *testing.T) {
	srv := NewServer(Config{AuthMode: "none"}, nil)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/ipv4/subnet-info", strings.NewReader(`{"network":"10.0.0.0/31","mode":"Standard"}`))
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("/31 returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "RFC 3021") {
		t.Fatalf("/31 note missing: %s", rec.Body.String())
	}

	req = httptest.NewRequest(http.MethodPost, "/api/v1/ipv4/subnet-info", strings.NewReader(`{"network":"2001:db8::/64","mode":"Azure"}`))
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("IPv6 on IPv4 endpoint returned %d", rec.Code)
	}

	req = httptest.NewRequest(http.MethodPost, "/api/v1/ipv4/subnet-info", strings.NewReader(`{"network":"10.0.0.0/24","mode":"InvalidMode"}`))
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("invalid mode returned %d", rec.Code)
	}
}

func TestIPv4SubnetInfoRejectsTrailingJSON(t *testing.T) {
	srv := NewServer(Config{AuthMode: "none"}, nil)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/ipv4/subnet-info", strings.NewReader(`{"network":"10.0.0.0/24","mode":"Standard"} {}`))
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("trailing JSON returned %d: %s", rec.Code, rec.Body.String())
	}
	if strings.TrimSpace(rec.Body.String()) != `{"error":"Invalid JSON body"}` {
		t.Fatalf("unexpected trailing JSON body: %s", rec.Body.String())
	}
}

func TestValidationPrivateCloudflareAndIPv6(t *testing.T) {
	srv := NewServer(Config{AuthMode: "none"}, nil)

	cases := []struct {
		path string
		body string
		want string
	}{
		{"/api/v1/ipv4/validate", `{"address":"192.168.1.0/24"}`, `"type":"network"`},
		{"/api/v1/ipv4/check-private", `{"address":"100.65.1.1"}`, `"matched_rfc6598_range":"100.64.0.0/10"`},
		{"/api/v1/ipv4/check-cloudflare", `{"address":"104.16.0.1"}`, `"is_cloudflare":true`},
		{"/api/v1/ipv6/subnet-info", `{"network":"2001:db8::/64"}`, `"network_address":"2001:db8::"`},
	}

	for _, tc := range cases {
		req := httptest.NewRequest(http.MethodPost, tc.path, strings.NewReader(tc.body))
		rec := httptest.NewRecorder()
		srv.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s returned %d: %s", tc.path, rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), tc.want) {
			t.Fatalf("%s missing %s in %s", tc.path, tc.want, rec.Body.String())
		}
	}
}

func TestIPv6SubnetInfoUsesNetworkPrefixForTotalAddresses(t *testing.T) {
	srv := NewServer(Config{AuthMode: "none"}, nil)

	tests := []struct {
		network string
		want    string
	}{
		{"2001:db8::/64", "18446744073709551616"},
		{"2001:db8::/112", "65536"},
	}

	for _, tt := range tests {
		t.Run(tt.network, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/api/v1/ipv6/subnet-info", strings.NewReader(`{"network":"`+tt.network+`"}`))
			rec := httptest.NewRecorder()
			srv.ServeHTTP(rec, req)
			if rec.Code != http.StatusOK {
				t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
			}

			var got map[string]any
			if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
				t.Fatal(err)
			}
			if got["total_addresses"] != tt.want {
				t.Fatalf("total_addresses=%v, want %s", got["total_addresses"], tt.want)
			}
		})
	}
}

func TestCloudflareCheckIdentifiesTheProviderRange(t *testing.T) {
	srv := NewServer(Config{AuthMode: "none"}, nil)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/ipv4/check-cloudflare", strings.NewReader(`{"address":"104.16.0.1"}`))
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}

	var got map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got["provider"] != "cloudflare" {
		t.Fatalf("provider=%v, want cloudflare", got["provider"])
	}
	if got["is_provider_range"] != true {
		t.Fatalf("is_provider_range=%v, want true", got["is_provider_range"])
	}
}

func TestProviderRangeCheckSupportsKnownProviders(t *testing.T) {
	srv := NewServer(Config{AuthMode: "none"}, nil)

	tests := []struct {
		name     string
		provider string
		address  string
		want     bool
	}{
		{"aws", "aws", "3.5.140.1", true},
		{"azure", "azure", "20.33.1.1", true},
		{"stripe", "stripe", "3.18.12.63", true},
		{"openai has no published ranges", "openai", "3.18.12.63", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			body := `{"provider":"` + tt.provider + `","address":"` + tt.address + `"}`
			req := httptest.NewRequest(http.MethodPost, "/api/v1/provider-ranges/check", strings.NewReader(body))
			rec := httptest.NewRecorder()
			srv.ServeHTTP(rec, req)
			if rec.Code != http.StatusOK {
				t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
			}

			var got map[string]any
			if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
				t.Fatal(err)
			}
			if got["provider"] != tt.provider {
				t.Fatalf("provider=%v, want %s", got["provider"], tt.provider)
			}
			if got["is_provider_range"] != tt.want {
				t.Fatalf("is_provider_range=%v, want %v: %#v", got["is_provider_range"], tt.want, got)
			}
		})
	}
}

func TestProviderRangeCheckRejectsUnsupportedProviderExplicitly(t *testing.T) {
	srv := NewServer(Config{AuthMode: "none"}, nil)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/provider-ranges/check", strings.NewReader(`{"provider":"example","address":"203.0.113.1"}`))
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}

	var got map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got["error"] != "Unsupported provider" {
		t.Fatalf("error=%q", got["error"])
	}
}

func TestProviderRangeCacheCanBeInvalidated(t *testing.T) {
	srv := NewServer(Config{AuthMode: "none"}, nil)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/provider-ranges/cache/invalidate", strings.NewReader(`{"provider":"aws"}`))
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}

	var got map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got["provider"] != "aws" || got["cache_status"] != "invalidated" {
		t.Fatalf("unexpected invalidation response: %#v", got)
	}
}

func TestProviderRangeRefreshUsesConfiguredSourceAndCacheInvalidation(t *testing.T) {
	source := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"prefixes":[{"ip_prefix":"203.0.113.0/24"}],"ipv6_prefixes":[]}`))
	}))
	defer source.Close()

	srv := NewServer(Config{
		AuthMode:             "none",
		ProviderRangeSources: map[string]string{"aws": source.URL},
	}, nil)

	assertProviderMatch := func(want bool) {
		t.Helper()
		req := httptest.NewRequest(http.MethodPost, "/api/v1/provider-ranges/check", strings.NewReader(`{"provider":"aws","address":"203.0.113.1"}`))
		rec := httptest.NewRecorder()
		srv.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("check status %d: %s", rec.Code, rec.Body.String())
		}
		var got map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
			t.Fatal(err)
		}
		if got["is_provider_range"] != want {
			t.Fatalf("is_provider_range=%v, want %v: %#v", got["is_provider_range"], want, got)
		}
	}

	assertProviderMatch(false)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/provider-ranges/cache/refresh", strings.NewReader(`{"provider":"aws"}`))
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("refresh status %d: %s", rec.Code, rec.Body.String())
	}
	assertProviderMatch(true)

	req = httptest.NewRequest(http.MethodPost, "/api/v1/provider-ranges/cache/invalidate", strings.NewReader(`{"provider":"aws"}`))
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("invalidate status %d: %s", rec.Code, rec.Body.String())
	}
	assertProviderMatch(false)
}

func TestProviderRangeRefreshParsesStripeAndAzureFeeds(t *testing.T) {
	tests := []struct {
		name     string
		provider string
		payload  string
		address  string
	}{
		{
			name:     "stripe",
			provider: "stripe",
			payload:  `{"WEBHOOKS":["198.51.100.25"]}`,
			address:  "198.51.100.25",
		},
		{
			name:     "azure",
			provider: "azure",
			payload:  `{"values":[{"properties":{"addressPrefixes":["198.51.100.0/24","2001:db8:51::/48"]}}]}`,
			address:  "2001:db8:51::1",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			source := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(tt.payload))
			}))
			defer source.Close()

			srv := NewServer(Config{
				AuthMode:             "none",
				ProviderRangeSources: map[string]string{tt.provider: source.URL},
			}, nil)

			req := httptest.NewRequest(http.MethodPost, "/api/v1/provider-ranges/cache/refresh", strings.NewReader(`{"provider":"`+tt.provider+`"}`))
			rec := httptest.NewRecorder()
			srv.ServeHTTP(rec, req)
			if rec.Code != http.StatusOK {
				t.Fatalf("refresh status %d: %s", rec.Code, rec.Body.String())
			}

			req = httptest.NewRequest(http.MethodPost, "/api/v1/provider-ranges/check", strings.NewReader(`{"provider":"`+tt.provider+`","address":"`+tt.address+`"}`))
			rec = httptest.NewRecorder()
			srv.ServeHTTP(rec, req)
			if rec.Code != http.StatusOK {
				t.Fatalf("check status %d: %s", rec.Code, rec.Body.String())
			}
			var got map[string]any
			if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
				t.Fatal(err)
			}
			if got["is_provider_range"] != true || got["range_source"] != "live-cache" {
				t.Fatalf("unexpected provider match: %#v", got)
			}
		})
	}
}

func TestWhoamiRequiresValidBearerToken(t *testing.T) {
	verifier := fakeVerifier{claims: idpauth.UserClaims{
		Subject:           "user-123",
		PreferredUsername: "demo",
		Email:             "demo@example.test",
		Groups:            []string{"platform"},
	}}
	srv := NewServer(Config{AuthMode: "oidc"}, verifier)

	req := httptest.NewRequest(http.MethodGet, "/api/whoami", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("missing token returned %d", rec.Code)
	}

	req = httptest.NewRequest(http.MethodGet, "/api/whoami", nil)
	req.Header.Set("Authorization", "Bearer valid-token")
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("valid token returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"preferred_username":"demo"`) {
		t.Fatalf("safe claims missing: %s", rec.Body.String())
	}
}

func TestRuntimeConfigExposesOIDCSettingsForVanillaFrontend(t *testing.T) {
	srv := NewServer(Config{
		AuthMode:     "oidc",
		APIAuthMode:  "oidc",
		OIDCIssuer:   "http://keycloak.example.test/realms/subnetcalc///",
		OIDCClientID: "frontend-app",
		OIDCAudience: "api-app",
		OIDCJWKSURI:  "http://keycloak:8080/realms/subnetcalc/protocol/openid-connect/certs",
		OIDCRedirect: "http://localhost:8003/",
		NetworkHops:  `[{"label":"Browser","detail":"localhost","role":"client"}]`,
	}, nil)

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
		`window.SUBNETCALC_RUNTIME_CONFIG`,
		`"authMethod":"oidc"`,
		`"apiAuthMethod":"oidc"`,
		`"oidcAuthority":"http://keycloak.example.test/realms/subnetcalc"`,
		`"oidcClientId":"frontend-app"`,
		`"oidcRedirect":"http://localhost:8003/"`,
		`"showNetworkPath":true`,
		`"networkHops":[{"detail":"localhost","label":"Browser","role":"client"}]`,
	} {
		if !strings.Contains(body, text) {
			t.Fatalf("runtime config missing %q in %s", text, body)
		}
	}
}

func TestRuntimeConfigUsesSharedURLNormalization(t *testing.T) {
	source, err := os.ReadFile("server.go")
	if err != nil {
		t.Fatal(err)
	}
	for _, text := range []string{
		`"oidcAuthority": appconfig.NormalizeURL(s.cfg.OIDCIssuer)`,
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

func TestRuntimeConfigCanDisableNetworkPath(t *testing.T) {
	srv := NewServer(Config{AuthMode: "none", ShowNetworkPath: "false"}, nil)

	req := httptest.NewRequest(http.MethodGet, "/runtime-config.js", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("runtime config returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"showNetworkPath":false`) {
		t.Fatalf("runtime config did not disable network path: %s", rec.Body.String())
	}
}

func TestRuntimeConfigDefaultsAPIAuthMethodToFrontendAuthMethod(t *testing.T) {
	srv := NewServer(Config{AuthMode: "gateway"}, nil)

	req := httptest.NewRequest(http.MethodGet, "/runtime-config.js", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("runtime config returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"apiAuthMethod":"gateway"`) {
		t.Fatalf("runtime config did not default API auth method: %s", rec.Body.String())
	}
}

func TestOIDCVerifierCanUseSeparateJWKSURI(t *testing.T) {
	verifier, err := idpauth.NewOIDCVerifier(
		t.Context(),
		"http://localhost:8300/realms/subnetcalc",
		"api-app",
		"http://keycloak:8080/realms/subnetcalc/protocol/openid-connect/certs",
	)
	if err != nil {
		t.Fatal(err)
	}
	if verifier == nil {
		t.Fatal("verifier is nil")
	}
}

func TestSubnetAPIsRequireValidBearerTokenWhenOIDCEnabled(t *testing.T) {
	verifier := fakeVerifier{claims: idpauth.UserClaims{Subject: "user-123", Groups: []string{"platform"}}}
	srv := NewServer(Config{AuthMode: "oidc"}, verifier)
	body := `{"address":"192.168.1.0/24"}`

	req := httptest.NewRequest(http.MethodPost, "/api/v1/ipv4/validate", strings.NewReader(body))
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("missing API token returned %d: %s", rec.Code, rec.Body.String())
	}

	req = httptest.NewRequest(http.MethodPost, "/api/v1/ipv4/validate", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer invalid-token")
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("invalid API token returned %d: %s", rec.Code, rec.Body.String())
	}

	req = httptest.NewRequest(http.MethodPost, "/api/v1/ipv4/validate", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer valid-token")
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("valid API token returned %d: %s", rec.Code, rec.Body.String())
	}
}

func TestFrontendKeepsThemeSwitcherAndSendsBearerTokenToAPIs(t *testing.T) {
	indexHTML, err := web.ReadFile("web/index.html")
	if err != nil {
		t.Fatal(err)
	}
	appJS, err := web.ReadFile("web/app.js")
	if err != nil {
		t.Fatal(err)
	}

	for _, text := range []string{
		`class="skip-link" href="#main"`,
		`<main id="main" tabindex="-1">`,
		`<header>`,
		`/app-shell.css`,
		`/app-shell.js`,
		`class="header-actions"`,
		`id="theme-switcher"`,
		`class="theme-toggle"`,
		`data-theme="system"`,
		`/runtime-config.js`,
		`/idpauth.js`,
		`id="auth-state"`,
		`id="logout-btn" class="sign-in-link"`,
		`>Sign Out<`,
		`id="api-status" class="app-panel notice" role="status" aria-live="polite"`,
		`id="results" class="app-panel" tabindex="-1" aria-live="polite"`,
	} {
		if !strings.Contains(string(indexHTML), text) {
			t.Fatalf("frontend index missing %q", text)
		}
	}
	html := string(indexHTML)
	if strings.Contains(html, `<main class="shell">`) {
		t.Fatalf("frontend shell must use the shared bare main container: %s", html)
	}
	for _, text := range []string{`id="login-btn"`, `>Sign In<`} {
		if strings.Contains(html, text) {
			t.Fatalf("protected frontend index must not render login control %q: %s", text, html)
		}
	}
	if strings.Index(html, `<header>`) > strings.Index(html, `<section`) &&
		strings.Index(html, `<header>`) > strings.Index(html, `<form`) {
		t.Fatalf("frontend shell header must be the first app section before content: %s", html)
	}
	if strings.Index(html, `id="logout-btn"`) > strings.Index(html, `id="theme-switcher"`) {
		t.Fatalf("frontend shell actions must be ordered auth, sign out, theme: %s", html)
	}
	for _, text := range []string{
		"PlatformAppShell",
		"initializeThemeSwitcher()",
		"requireElement",
		"inputElement",
		"selectElement",
		"fetchJSON",
		"fetchJSONWithTiming",
		"errorMessage",
		"renderNetworkPathInto",
		"resolveNetworkHops",
		"apiAuthHeaders()",
		"apiRequiresOIDCToken(runtimeConfig())",
		"apiReadyForUserAction()",
		"apiActionReady(runtimeConfig(), inputElement(\"token-input\").value)",
		"authRequiredMessage()",
		`apiAuthRequiredMessage("running API calls", "the calculator")`,
		"apiErrorMessage(runtimeConfig(), error",
		"apiJSONHeaders(runtimeConfig(), apiAuthHeaders())",
		"Authorization: `Bearer ${token}`",
		"usesGatewayAuth(runtimeConfig())",
		"refreshGatewayIdentity()",
		"const showAuthPanel = showOidc || gateway",
		`authPanel.hidden = !showOidc`,
		`authState.hidden = !showAuthPanel`,
		"tokenInput.hidden = gateway",
		"whoamiButton.hidden = gateway",
		"prepareResults()",
		"focusResults()",
		`resultsPanel.focus()`,
		"decodeAPIMTrace",
		"PlatformIdpAuth",
		"initializeGatewayAuthState(authState, logoutButton",
		"errorMessage: (error) =>",
		"fetchOIDCProviderMetadata(config)",
		"gatewayLogoutURL()",
		"formatAPIHealthStatus(data, runtimeConfig())",
		"renderStatusInto(authState",
		"renderNetworkPathInto(",
		"const backendURL = config.backendURL || \"same process\"",
		"const backendRole =",
		"config.apiAuthMethod === \"oidc\"",
		"Static UI and same-origin API proxy",
		"apiTimingElement",
		"keyValueArticleElement",
		"renderElementsInto(",
		`@typedef {import("./api-types.d.ts").KeyValueTableRow} KeyValueTableRow`,
		"@type {KeyValueTableRow[]}",
	} {
		if !strings.Contains(string(appJS), text) {
			t.Fatalf("frontend app.js missing %q", text)
		}
	}
	for _, text := range []string{
		"function normalizeGatewaySession",
		"function gatewayDisplayName",
		"function gatewayLogoutURL",
		"function readThemeCookie",
		"function writeThemeCookie",
		"function themeCookieDomain",
		"function requireElement",
		"function inputElement",
		"function selectElement",
		"async function parseJSONResponse",
		"parseJSONResponse(response)",
		"const response = await fetch(path",
		"function isNetworkHop",
		"traceId: response.headers.get",
		"correlationId: response.headers.get",
		"<summary>Network Path",
		"fetchGatewaySession()",
		"writeGatewayAuthState(authState, logoutButton, session)",
		"function apiRequiresOidcToken",
		"function usesGatewayAuth",
		"function expiredSessionMessage",
		"function authSessionExpired",
		"function escapeHTML",
		"content.innerHTML",
		"insertAdjacentHTML",
		"renderAPITiming",
		"error.message",
		`Array<[string, string | number | boolean | null | undefined]>`,
		"authState.textContent",
		"/protocol/openid-connect/token",
		"/protocol/openid-connect/logout",
		"window.SUBNETCALC_RUNTIME_CONFIG",
		"The backend validates JWT/OIDC tokens, so the calculator",
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
}

type fakeVerifier struct {
	claims idpauth.UserClaims
	err    error
}

func (f fakeVerifier) Verify(_ context.Context, token string) (idpauth.UserClaims, error) {
	if token != "valid-token" {
		return idpauth.UserClaims{}, idpauth.ErrInvalidToken
	}
	return f.claims, f.err
}
