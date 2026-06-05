package idpauth

import (
	"context"
	"encoding/base64"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
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

func TestSharedFallbackHelperIsUsedForGatewayIdentitySelection(t *testing.T) {
	source, err := os.ReadFile("idpauth.go")
	if err != nil {
		t.Fatal(err)
	}
	text := string(source)
	if !strings.Contains(text, "appconfig.FirstNonEmpty(") {
		t.Fatalf("idpauth should use shared appconfig.FirstNonEmpty helper")
	}
	if strings.Contains(text, "func firstNonEmpty(") {
		t.Fatalf("idpauth should not keep a local firstNonEmpty helper")
	}
}

func TestGatewaySessionFromHeadersAcceptsProviderNeutralOIDCClaims(t *testing.T) {
	header := http.Header{}
	header.Set("X-Auth-Request-User", "8f042987-6556-4fbd-8842-f2cc76ce4d7b")
	header.Set("X-Forwarded-Preferred-Username", "alex@example.com")
	header.Set("X-Forwarded-Groups", "app-platform-admins,app-platform-readers")
	header.Add("X-Forwarded-Roles", "approver")

	session, ok := GatewaySessionFromHeaders(header)
	if !ok {
		t.Fatalf("expected gateway session")
	}
	if session.UserDetails != "alex@example.com" {
		t.Fatalf("expected preferred username display identity, got %+v", session)
	}
	if session.UserID != "alex@example.com" {
		t.Fatalf("expected user id to prefer preferred_username, got %+v", session)
	}
	for _, want := range []GatewayClaim{
		{Type: "sub", Value: "8f042987-6556-4fbd-8842-f2cc76ce4d7b"},
		{Type: "preferred_username", Value: "alex@example.com"},
		{Type: "groups", Value: "app-platform-admins"},
		{Type: "groups", Value: "app-platform-readers"},
		{Type: "roles", Value: "approver"},
	} {
		if !hasGatewayClaim(session.Claims, want) {
			t.Fatalf("session claims missing %+v in %+v", want, session.Claims)
		}
	}
}

func TestGatewaySessionFromHeadersAcceptsAzureClientPrincipal(t *testing.T) {
	header := http.Header{}
	header.Set("X-MS-CLIENT-PRINCIPAL-IDP", "aad")
	header.Set("X-MS-CLIENT-PRINCIPAL-ID", "aaaaaaaa-0000-1111-2222-bbbbbbbbbbbb")
	header.Set("X-MS-CLIENT-PRINCIPAL-NAME", "alex@example.com")
	header.Set("X-MS-CLIENT-PRINCIPAL", base64.StdEncoding.EncodeToString([]byte(`{
		"auth_typ": "aad",
		"name_typ": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name",
		"role_typ": "http://schemas.microsoft.com/ws/2008/06/identity/claims/role",
		"claims": [
			{"typ": "name", "val": "Alex Morgan"},
			{"typ": "preferred_username", "val": "alex@example.com"},
			{"typ": "oid", "val": "aaaaaaaa-0000-1111-2222-bbbbbbbbbbbb"},
			{"typ": "tid", "val": "cccccccc-3333-4444-5555-dddddddddddd"},
			{"typ": "roles", "val": "approver"}
		]
	}`)))

	session, ok := GatewaySessionFromHeaders(header)
	if !ok {
		t.Fatalf("expected gateway session")
	}
	if session.ProviderName != "aad" {
		t.Fatalf("expected provider name from EasyAuth, got %+v", session)
	}
	if session.UserDetails != "alex@example.com" {
		t.Fatalf("expected Entra preferred username display identity, got %+v", session)
	}
	for _, want := range []GatewayClaim{
		{Type: "preferred_username", Value: "alex@example.com"},
		{Type: "oid", Value: "aaaaaaaa-0000-1111-2222-bbbbbbbbbbbb"},
		{Type: "roles", Value: "approver"},
	} {
		if !hasGatewayClaim(session.Claims, want) {
			t.Fatalf("session claims missing %+v in %+v", want, session.Claims)
		}
	}
}

func TestSessionWritersUseNoCacheJSONPolicy(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/.auth/me", nil)
	req.Header.Set("X-Forwarded-Email", "demo@example.test")

	for name, writer := range map[string]http.HandlerFunc{
		"client-principal": WriteClientPrincipalSession,
		"session-array":    WriteSessionArray,
	} {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			writer(rec, req)

			if got := rec.Header().Get("Content-Type"); got != "application/json" {
				t.Fatalf("Content-Type=%q", got)
			}
			if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
				t.Fatalf("Cache-Control=%q", got)
			}
			if got := rec.Header().Get("Pragma"); got != "no-cache" {
				t.Fatalf("Pragma=%q", got)
			}
			if got := rec.Header().Get("Expires"); got != "0" {
				t.Fatalf("Expires=%q", got)
			}
		})
	}
}

func TestBrowserBundleExportsGatewayIdentityHelpers(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/idpauth.js", nil)
	rec := httptest.NewRecorder()
	BrowserBundle(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("bundle returned %d: %s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("Cache-Control=%q", got)
	}
	body := rec.Body.String()
	for _, text := range []string{"PlatformIdpAuth", "normalizeGatewaySession", "gatewayDisplayName", `claimValue("emailaddress", "email")`, `claimValue("upn", "preferred_username", "unique_name")`, "gatewayLogoutURL", "bindGatewayLogout", "writeGatewayAuthState", "initializeGatewayAuthState", "ignoreErrors", "usesGatewayAuth", "apiRequiresOIDCToken", "apiActionReady", "apiAuthRequiredMessage", "gatewaySessionExpired", "expiredSessionMessage", "PlatformIdpAuthConfig", "post_logout_redirect_uri", "oidcDiscoveryURL", "fetchOIDCProviderMetadata", "token_endpoint", "end_session_endpoint"} {
		if !strings.Contains(body, text) {
			t.Fatalf("shared idpauth bundle missing %q: %s", text, body)
		}
	}
	if strings.Contains(body, "/protocol/openid-connect/token") {
		t.Fatalf("shared idpauth browser helpers must not hardcode Keycloak token paths: %s", body)
	}
}

func TestBrowserBundleRejectsUnsupportedMethodsWithAllowHeader(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/idpauth.js", nil)
	rec := httptest.NewRecorder()

	BrowserBundle(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Allow"); got != "GET, HEAD" {
		t.Fatalf("Allow=%q", got)
	}
}

func TestBootstrapVerifierReturnsNilWhenShouldVerifyIsFalse(t *testing.T) {
	v, err := BootstrapVerifier("", "", "", false)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if v != nil {
		t.Fatalf("expected nil verifier, got %v", v)
	}
}

func TestBootstrapVerifierReturnsErrorWhenIssuerMissing(t *testing.T) {
	// NewOIDCVerifier requires issuer and audience; passing empty values must error.
	v, err := BootstrapVerifier("", "audience", "", true)
	if err == nil {
		t.Fatalf("expected error for missing issuer, got verifier %v", v)
	}
	if v != nil {
		t.Fatalf("expected nil verifier on error, got %v", v)
	}
}

func TestAuthenticatorMiddlewareCallsNextOnSuccess(t *testing.T) {
	auth := Authenticator{
		Mode:     "oidc",
		Verifier: staticVerifier{claims: UserClaims{Subject: "user-123"}},
	}
	middleware := auth.Middleware(AuthFailureMessages{})

	nextCalled := false
	handler := middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		nextCalled = true
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/api/protected", nil)
	req.Header.Set("Authorization", "Bearer valid-token")
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if !nextCalled {
		t.Fatal("expected next handler to be called")
	}
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestAuthenticatorMiddlewareBlocksOnFailure(t *testing.T) {
	auth := Authenticator{Mode: "oidc", Verifier: nil}
	middleware := auth.Middleware(AuthFailureMessages{})

	nextCalled := false
	handler := middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		nextCalled = true
	}))

	req := httptest.NewRequest(http.MethodGet, "/api/protected", nil)
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if nextCalled {
		t.Fatal("expected next handler NOT to be called when auth fails")
	}
}

func TestAuthenticatorMiddlewareUsesCustomMessages(t *testing.T) {
	// Supply a verifier so CurrentUser reaches the token check.
	// With no Authorization header the "missing bearer token" failure fires,
	// and the custom MissingBearerToken message should be used.
	auth := Authenticator{
		Mode:     "oidc",
		Verifier: staticVerifier{claims: UserClaims{Subject: "user-123"}},
	}
	msgs := AuthFailureMessages{
		MissingBearerToken: "Custom: token required",
	}
	handler := auth.Middleware(msgs)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))

	req := httptest.NewRequest(http.MethodGet, "/api/protected", nil) // no Authorization header
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if !strings.Contains(rec.Body.String(), "Custom: token required") {
		t.Fatalf("expected custom message, got %q", rec.Body.String())
	}
}

func TestAuthenticatorCurrentUserOrWriteErrorUsesCustomMessages(t *testing.T) {
	auth := Authenticator{
		Mode:     "oidc",
		Verifier: staticVerifier{claims: UserClaims{Subject: "user-123"}},
	}
	req := httptest.NewRequest(http.MethodGet, "/api/whoami", nil)
	rec := httptest.NewRecorder()

	claims, ok := auth.CurrentUserOrWriteError(rec, req, AuthFailureMessages{
		MissingBearerToken: "Custom: token required",
	})
	if ok {
		t.Fatalf("expected auth failure, got claims %#v", claims)
	}
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "Custom: token required") {
		t.Fatalf("expected custom message, got %q", rec.Body.String())
	}

	req.Header.Set("Authorization", "Bearer valid-token")
	rec = httptest.NewRecorder()
	claims, ok = auth.CurrentUserOrWriteError(rec, req, AuthFailureMessages{})
	if !ok || claims.Subject != "user-123" {
		t.Fatalf("expected authenticated user, ok=%v claims=%#v", ok, claims)
	}
	if rec.Code != http.StatusOK || rec.Body.Len() != 0 {
		t.Fatalf("successful auth should not write response: status=%d body=%q", rec.Code, rec.Body.String())
	}
}

func TestAuthenticatorNormalizesBearerTokenDecisions(t *testing.T) {
	auth := Authenticator{
		Mode:     "oidc",
		Verifier: staticVerifier{claims: UserClaims{Subject: "user-123"}},
	}

	req := httptest.NewRequest(http.MethodGet, "/api/whoami", nil)
	_, failure := auth.CurrentUser(req)
	if failure == nil || failure.StatusCode != http.StatusUnauthorized || failure.Message != "missing bearer token" {
		t.Fatalf("missing token failure = %#v", failure)
	}

	req.Header.Set("Authorization", "Bearer valid-token")
	claims, failure := auth.CurrentUser(req)
	if failure != nil {
		t.Fatalf("valid token failure = %#v", failure)
	}
	if claims.Subject != "user-123" {
		t.Fatalf("claims = %#v", claims)
	}
	if claims.Groups == nil {
		t.Fatalf("groups should be normalized to an empty slice")
	}
}

func TestAuthenticatorMapsVerifierFailures(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/whoami", nil)
	req.Header.Set("Authorization", "Bearer any-token")

	auth := Authenticator{Mode: "oidc"}
	_, failure := auth.CurrentUser(req)
	if failure == nil || failure.StatusCode != http.StatusServiceUnavailable || failure.Message != "OIDC verifier is not configured" {
		t.Fatalf("missing verifier failure = %#v", failure)
	}

	auth.Verifier = staticVerifier{err: ErrInvalidToken}
	_, failure = auth.CurrentUser(req)
	if failure == nil || failure.StatusCode != http.StatusUnauthorized || failure.Message != "invalid token" {
		t.Fatalf("invalid token failure = %#v", failure)
	}

	auth.Verifier = staticVerifier{err: errors.New("jwks unavailable")}
	_, failure = auth.CurrentUser(req)
	if failure == nil || failure.StatusCode != http.StatusBadGateway || failure.Message != "invalid token" {
		t.Fatalf("upstream verifier failure = %#v", failure)
	}
}

func TestAuthFailureMessageSupportsAppSpecificBearerText(t *testing.T) {
	missingToken := AuthFailure{Message: "missing bearer token"}
	invalidToken := AuthFailure{Message: "invalid token"}
	upstream := AuthFailure{Message: "OIDC verifier is not configured"}

	messages := AuthFailureMessages{
		MissingBearerToken: "Missing or invalid bearer token",
		InvalidToken:       "Invalid token",
	}

	if got := missingToken.MessageFor(messages); got != "Missing or invalid bearer token" {
		t.Fatalf("missing token message = %q", got)
	}
	if got := invalidToken.MessageFor(messages); got != "Invalid token" {
		t.Fatalf("invalid token message = %q", got)
	}
	if got := upstream.MessageFor(messages); got != "OIDC verifier is not configured" {
		t.Fatalf("upstream message = %q", got)
	}
	if got := invalidToken.MessageFor(AuthFailureMessages{}); got != "invalid token" {
		t.Fatalf("default invalid token message = %q", got)
	}
	if got := (*AuthFailure)(nil).MessageFor(messages); got != "" {
		t.Fatalf("nil failure message = %q", got)
	}
}

func TestAuthenticatorAllowsAnonymousMode(t *testing.T) {
	claims, failure := (Authenticator{Mode: "none"}).CurrentUser(httptest.NewRequest(http.MethodGet, "/", nil))
	if failure != nil {
		t.Fatalf("anonymous mode failure = %#v", failure)
	}
	if claims.Subject != "anonymous" || len(claims.Groups) != 0 {
		t.Fatalf("anonymous claims = %#v", claims)
	}
}

func TestRuntimeAuthConfigFromEnvNormalizesCommonAppAuthSettings(t *testing.T) {
	for _, key := range []string{
		"AUTH_METHOD",
		"API_AUTH_METHOD",
		"RUNTIME_ROLE",
		"OIDC_ISSUER_URL",
		"OIDC_AUTHORITY",
		"OIDC_AUDIENCE",
		"OIDC_CLIENT_ID",
		"OIDC_JWKS_URI",
		"OIDC_REDIRECT_URI",
	} {
		t.Setenv(key, "")
	}
	t.Setenv("AUTH_METHOD", "OIDC")
	t.Setenv("RUNTIME_ROLE", "Frontend")
	t.Setenv("OIDC_AUTHORITY", "https://issuer.example.test")
	t.Setenv("OIDC_AUDIENCE", "")
	t.Setenv("OIDC_CLIENT_ID", "browser-client")
	t.Setenv("OIDC_JWKS_URI", "https://issuer.example.test/certs")
	t.Setenv("OIDC_REDIRECT_URI", "https://app.example.test/callback")

	cfg := RuntimeAuthConfigFromEnv("all")
	if cfg.AuthMode != "oidc" {
		t.Fatalf("AuthMode=%q", cfg.AuthMode)
	}
	if cfg.APIAuthMode != "oidc" {
		t.Fatalf("APIAuthMode should fall back to auth mode, got %q", cfg.APIAuthMode)
	}
	if cfg.RuntimeRole != "frontend" {
		t.Fatalf("RuntimeRole=%q", cfg.RuntimeRole)
	}
	if cfg.OIDCIssuer != "https://issuer.example.test" {
		t.Fatalf("OIDCIssuer=%q", cfg.OIDCIssuer)
	}
	if cfg.VerifierAudience() != "browser-client" {
		t.Fatalf("VerifierAudience=%q", cfg.VerifierAudience())
	}
	if cfg.ShouldVerifyOIDC("frontend") {
		t.Fatalf("frontend role should not configure an in-process OIDC verifier")
	}

	t.Setenv("API_AUTH_METHOD", "Gateway")
	t.Setenv("RUNTIME_ROLE", "Backend")
	t.Setenv("OIDC_AUDIENCE", "api-audience")
	cfg = RuntimeAuthConfigFromEnv("all")
	if cfg.APIAuthMode != "gateway" {
		t.Fatalf("APIAuthMode=%q", cfg.APIAuthMode)
	}
	if !cfg.ShouldVerifyOIDC("frontend") {
		t.Fatalf("backend role should configure an in-process OIDC verifier")
	}
	if cfg.VerifierAudience() != "api-audience" {
		t.Fatalf("VerifierAudience=%q", cfg.VerifierAudience())
	}
}

func TestAccessPolicyAcceptsGroupsRolesAndClaims(t *testing.T) {
	claims := UserClaims{
		Subject:           "user-123",
		PreferredUsername: "alex@example.test",
		Email:             "alex@example.test",
		Groups:            []string{"platform-admins"},
		Roles:             []string{"approver"},
	}

	policy := AccessPolicy{
		RequiredGroups: []string{"platform-admins"},
		RequiredRoles:  []string{"approver"},
		RequiredClaims: map[string]string{"email": "alex@example.test"},
	}
	if failure := policy.Evaluate(claims); failure != nil {
		t.Fatalf("expected access to be allowed, got %#v", failure)
	}

	policy.RequiredRoles = []string{"operator"}
	failure := policy.Evaluate(claims)
	if failure == nil || failure.StatusCode != http.StatusForbidden || failure.Message != "missing required role" {
		t.Fatalf("missing role failure = %#v", failure)
	}
}

func hasGatewayClaim(claims []GatewayClaim, want GatewayClaim) bool {
	for _, claim := range claims {
		if claim == want {
			return true
		}
	}
	return false
}

type staticVerifier struct {
	claims UserClaims
	err    error
}

func (v staticVerifier) Verify(_ context.Context, _ string) (UserClaims, error) {
	if v.err != nil {
		return UserClaims{}, v.err
	}
	return v.claims, nil
}
