package app

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
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
}

func TestFrontendRendersE2ESubnetcalcResultSections(t *testing.T) {
	appJS, err := web.ReadFile("web/app.js")
	if err != nil {
		t.Fatal(err)
	}

	required := []string{
		"Validation",
		"Private Address Check",
		"Cloudflare Check",
		"Subnet Information",
		"Performance Timing",
		"API Call Timing",
		"Request (UTC)",
		"Response (UTC)",
		"Total Response Time",
	}
	for _, text := range required {
		if !strings.Contains(string(appJS), text) {
			t.Fatalf("frontend app.js missing %q", text)
		}
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

func TestWhoamiRequiresValidBearerToken(t *testing.T) {
	verifier := fakeVerifier{claims: UserClaims{
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

type fakeVerifier struct {
	claims UserClaims
	err    error
}

func (f fakeVerifier) Verify(_ *http.Request, token string) (UserClaims, error) {
	if token != "valid-token" {
		return UserClaims{}, ErrInvalidToken
	}
	return f.claims, f.err
}
