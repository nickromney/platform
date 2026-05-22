package idpauth

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestGatewaySessionFromHeadersPrefersEmailOverOpaqueSubject(t *testing.T) {
	header := http.Header{}
	header.Set("X-Forwarded-User", "baa3e24f-39c3-4693-8754-ca65d0842572")
	header.Set("X-Forwarded-Email", "demo@dev.test")

	session, ok := GatewaySessionFromHeaders(header)
	if !ok {
		t.Fatalf("expected gateway session")
	}
	if session.UserDetails != "demo@dev.test" {
		t.Fatalf("expected email display identity, got %+v", session)
	}
	if session.UserID != "demo@dev.test" {
		t.Fatalf("expected stable user id to prefer email, got %+v", session)
	}
}

func TestBrowserBundleExportsGatewayIdentityHelpers(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/idpauth.js", nil)
	rec := httptest.NewRecorder()
	BrowserBundle(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("bundle returned %d: %s", rec.Code, rec.Body.String())
	}
	body := rec.Body.String()
	for _, text := range []string{"window.PlatformIdpAuth", "normalizeGatewaySession", "gatewayDisplayName", `claimValue("email")`, "gatewayLogoutURL"} {
		if !strings.Contains(body, text) {
			t.Fatalf("shared idpauth bundle missing %q: %s", text, body)
		}
	}
}
