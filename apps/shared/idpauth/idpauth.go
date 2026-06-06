// Package idpauth provides shared identity and authentication primitives
// used across platform apps: token verification, user claims, and bearer
// token extraction.
package idpauth

import (
	"context"
	"embed"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/coreos/go-oidc/v3/oidc"
	"platform.local/appconfig"
	"platform.local/apphttp"
)

//go:embed web/idpauth.js
var browserAssets embed.FS

// ErrInvalidToken is returned by TokenVerifier.Verify when the supplied
// token is present but cannot be validated (expired, bad signature, etc.).
var ErrInvalidToken = errors.New("invalid bearer token")

// UserClaims holds the identity claims extracted from a verified token.
type UserClaims struct {
	Subject           string   `json:"sub"`
	PreferredUsername string   `json:"preferred_username,omitempty"`
	Email             string   `json:"email,omitempty"`
	Groups            []string `json:"groups"`
	Roles             []string `json:"roles,omitempty"`
}

// GatewayClaim is the browser-facing claim shape used by /.auth/me endpoints.
type GatewayClaim struct {
	Type  string `json:"typ"`
	Value string `json:"val"`
}

// GatewaySession is the browser-facing identity shape shared by platform apps.
type GatewaySession struct {
	ProviderName string         `json:"provider_name,omitempty"`
	UserID       string         `json:"user_id,omitempty"`
	UserDetails  string         `json:"userDetails"`
	Claims       []GatewayClaim `json:"claims"`
}

type clientPrincipal struct {
	IdentityProvider string         `json:"auth_typ"`
	NameClaimType    string         `json:"name_typ"`
	RoleClaimType    string         `json:"role_typ"`
	Claims           []GatewayClaim `json:"claims"`
}

// TokenVerifier verifies a raw bearer token string and returns the claims
// if valid. Implementations must be safe for concurrent use.
type TokenVerifier interface {
	Verify(ctx context.Context, token string) (UserClaims, error)
}

// Authenticator centralizes the common platform app bearer-token decision.
// Apps keep their own response shape, but share auth mode, verifier, status,
// and anonymous-user semantics through this module.
type Authenticator struct {
	Mode     string
	Verifier TokenVerifier
}

// RuntimeAuthConfig is the shared auth-related environment contract used by
// the lightweight Go apps. It keeps provider-neutral auth mode and OIDC
// settings in one place while apps retain their local non-auth config.
type RuntimeAuthConfig struct {
	AuthMode     string
	APIAuthMode  string
	RuntimeRole  string
	OIDCIssuer   string
	OIDCAudience string
	OIDCClientID string
	OIDCJWKSURI  string
	OIDCRedirect string
}

// RuntimeAuthConfigFromEnv reads the common platform app auth environment.
func RuntimeAuthConfigFromEnv(defaultRuntimeRole string) RuntimeAuthConfig {
	authMode := strings.ToLower(appconfig.Env("AUTH_METHOD", "none"))
	apiAuthMode := strings.ToLower(appconfig.Env("API_AUTH_METHOD", ""))
	if apiAuthMode == "" {
		apiAuthMode = authMode
	}
	return RuntimeAuthConfig{
		AuthMode:     authMode,
		APIAuthMode:  apiAuthMode,
		RuntimeRole:  strings.ToLower(appconfig.Env("RUNTIME_ROLE", defaultRuntimeRole)),
		OIDCIssuer:   appconfig.FirstEnv("OIDC_ISSUER_URL", "OIDC_AUTHORITY"),
		OIDCAudience: appconfig.Env("OIDC_AUDIENCE", ""),
		OIDCClientID: appconfig.Env("OIDC_CLIENT_ID", ""),
		OIDCJWKSURI:  appconfig.Env("OIDC_JWKS_URI", ""),
		OIDCRedirect: appconfig.Env("OIDC_REDIRECT_URI", ""),
	}
}

// VerifierAudience returns the audience used by server-side OIDC token
// verification, falling back to the browser client ID for apps that share one
// OIDC client between browser login and API verification.
func (c RuntimeAuthConfig) VerifierAudience() string {
	if strings.TrimSpace(c.OIDCAudience) != "" {
		return c.OIDCAudience
	}
	return c.OIDCClientID
}

// ShouldVerifyOIDC reports whether this process should configure an in-process
// OIDC verifier. Browser-only frontend roles normally rely on the gateway.
func (c RuntimeAuthConfig) ShouldVerifyOIDC(frontendRole string) bool {
	return c.AuthMode == "oidc" && c.RuntimeRole != strings.ToLower(frontendRole)
}

// AuthFailure describes the HTTP-relevant reason an authentication attempt
// failed. Message is safe to expose to browser/API callers.
type AuthFailure struct {
	StatusCode int
	Message    string
	Err        error
}

// AuthFailureMessages lets apps keep local public wording while relying on
// idpauth's canonical failure decisions.
type AuthFailureMessages struct {
	MissingBearerToken string
	InvalidToken       string
}

// MessageFor returns failure text rendered with optional app-specific labels.
func (f *AuthFailure) MessageFor(messages AuthFailureMessages) string {
	if f == nil {
		return ""
	}
	switch f.Message {
	case "missing bearer token":
		if messages.MissingBearerToken != "" {
			return messages.MissingBearerToken
		}
	case "invalid token":
		if messages.InvalidToken != "" {
			return messages.InvalidToken
		}
	}
	return f.Message
}

// BootstrapVerifier constructs an OIDC TokenVerifier when shouldVerify is
// true and the required fields are present. Returns nil, nil when
// shouldVerify is false so callers can skip the conditional and treat a nil
// verifier as the no-auth case. Uses context.Background() because verifier
// construction is a startup operation with no caller-imposed deadline.
func BootstrapVerifier(issuer, audience, jwksURI string, shouldVerify bool) (TokenVerifier, error) {
	if !shouldVerify {
		return nil, nil
	}
	v, err := NewOIDCVerifier(context.Background(), issuer, audience, jwksURI)
	if err != nil {
		return nil, err // explicit nil interface — avoids the typed-nil-in-interface trap
	}
	return v, nil
}

// Middleware returns an HTTP middleware that gates handlers on successful
// authentication. On failure it writes an error response using the optional
// custom messages and returns without calling next.
//
// Note: this middleware belongs in idpauth, not apphttp. idpauth already
// imports apphttp; placing RequireAuth in apphttp would create a circular
// import. Future explorers: do not re-suggest apphttp.RequireAuth.
func (a Authenticator) Middleware(msgs AuthFailureMessages) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if _, ok := a.CurrentUserOrWriteError(w, r, msgs); !ok {
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// CurrentUserOrWriteError returns the authenticated user or writes the
// canonical app error response for the failure. It belongs in idpauth because
// this package is the auth+HTTP integration layer; apphttp remains auth-free.
func (a Authenticator) CurrentUserOrWriteError(w http.ResponseWriter, r *http.Request, msgs AuthFailureMessages) (UserClaims, bool) {
	claims, failure := a.CurrentUser(r)
	if failure != nil {
		apphttp.WriteError(w, failure.StatusCode, failure.MessageFor(msgs))
		return UserClaims{}, false
	}
	return claims, true
}

// CurrentUser returns the authenticated user for the request, or a failure
// that the caller can render in its local error response shape.
func (a Authenticator) CurrentUser(r *http.Request) (UserClaims, *AuthFailure) {
	if strings.EqualFold(a.Mode, "none") || strings.TrimSpace(a.Mode) == "" {
		return UserClaims{Subject: "anonymous", Groups: []string{}}, nil
	}
	if a.Verifier == nil {
		return UserClaims{}, &AuthFailure{
			StatusCode: http.StatusServiceUnavailable,
			Message:    "OIDC verifier is not configured",
		}
	}
	token := BearerToken(r)
	if token == "" {
		return UserClaims{}, &AuthFailure{
			StatusCode: http.StatusUnauthorized,
			Message:    "missing bearer token",
		}
	}
	claims, err := a.Verifier.Verify(r.Context(), token)
	if err != nil {
		status := http.StatusUnauthorized
		if !errors.Is(err, ErrInvalidToken) {
			status = http.StatusBadGateway
		}
		return UserClaims{}, &AuthFailure{
			StatusCode: status,
			Message:    "invalid token",
			Err:        err,
		}
	}
	if claims.Groups == nil {
		claims.Groups = []string{}
	}
	if claims.Roles == nil {
		claims.Roles = []string{}
	}
	return claims, nil
}

// AccessPolicy describes simple provider-neutral authorization checks over the
// normalized user claims exposed by Authenticator.
type AccessPolicy struct {
	RequiredGroups []string
	RequiredRoles  []string
	RequiredClaims map[string]string
}

// Evaluate returns nil when claims satisfy every configured access requirement.
func (p AccessPolicy) Evaluate(claims UserClaims) *AuthFailure {
	if missing := missingRequiredValue(p.RequiredGroups, claims.Groups); missing != "" {
		return &AuthFailure{
			StatusCode: http.StatusForbidden,
			Message:    "missing required group",
		}
	}
	if missing := missingRequiredValue(p.RequiredRoles, claims.Roles); missing != "" {
		return &AuthFailure{
			StatusCode: http.StatusForbidden,
			Message:    "missing required role",
		}
	}
	for name, want := range p.RequiredClaims {
		if !containsString(claimValues(claims, name), want) {
			return &AuthFailure{
				StatusCode: http.StatusForbidden,
				Message:    "missing required claim",
			}
		}
	}
	return nil
}

func missingRequiredValue(required, actual []string) string {
	for _, value := range required {
		if trimmed := strings.TrimSpace(value); trimmed != "" && !containsString(actual, trimmed) {
			return trimmed
		}
	}
	return ""
}

func containsString(values []string, want string) bool {
	want = strings.TrimSpace(want)
	if want == "" {
		return true
	}
	for _, value := range values {
		if strings.EqualFold(strings.TrimSpace(value), want) {
			return true
		}
	}
	return false
}

func claimValues(claims UserClaims, name string) []string {
	switch canonicalClaimType(name) {
	case "sub":
		return []string{claims.Subject}
	case "email":
		return []string{claims.Email}
	case "preferred_username":
		return []string{claims.PreferredUsername}
	case "groups":
		return claims.Groups
	case "roles":
		return claims.Roles
	default:
		return nil
	}
}

// OIDCVerifier implements TokenVerifier using the coreos/go-oidc library.
// It validates tokens against a remote JWKS endpoint and extracts claims.
type OIDCVerifier struct {
	verifier *oidc.IDTokenVerifier
}

// NewOIDCVerifier constructs an OIDCVerifier. When jwksURI is non-empty the
// key set is fetched directly from that URI; otherwise OIDC discovery is used
// to locate it from the issuer URL.
func NewOIDCVerifier(ctx context.Context, issuer, audience, jwksURI string) (*OIDCVerifier, error) {
	if issuer == "" || audience == "" {
		return nil, fmt.Errorf("OIDC_ISSUER_URL and OIDC_AUDIENCE are required when AUTH_METHOD=oidc")
	}
	config := &oidc.Config{ClientID: audience}
	if jwksURI != "" {
		keySet := oidc.NewRemoteKeySet(ctx, jwksURI)
		return &OIDCVerifier{verifier: oidc.NewVerifier(issuer, keySet, config)}, nil
	}
	provider, err := oidc.NewProvider(ctx, issuer)
	if err != nil {
		return nil, err
	}
	return &OIDCVerifier{verifier: provider.Verifier(config)}, nil
}

// Verify validates the raw JWT and returns the extracted UserClaims.
// Returns ErrInvalidToken when the token is present but invalid.
func (v *OIDCVerifier) Verify(ctx context.Context, token string) (UserClaims, error) {
	idToken, err := v.verifier.Verify(ctx, token)
	if err != nil {
		return UserClaims{}, ErrInvalidToken
	}
	var claims UserClaims
	if err := idToken.Claims(&claims); err != nil {
		return UserClaims{}, err
	}
	if claims.Subject == "" {
		claims.Subject = idToken.Subject
	}
	return claims, nil
}

// BearerToken extracts the bearer token value from the Authorization header.
// Returns an empty string if the header is absent or not in Bearer format.
func BearerToken(r *http.Request) string {
	fields := strings.Fields(r.Header.Get("Authorization"))
	if len(fields) != 2 || !strings.EqualFold(fields[0], "Bearer") {
		return ""
	}
	return fields[1]
}

// GatewaySessionFromHeaders normalizes common gateway identity headers into the
// browser-facing session shape used by platform apps. It accepts oauth2-proxy
// auth-request headers and Azure App Service/EasyAuth client-principal headers.
// It prefers human-readable identity values for display because forwarded user
// IDs are often opaque OIDC subject UUIDs.
func GatewaySessionFromHeaders(header http.Header) (GatewaySession, bool) {
	if session, ok := azureClientPrincipalSession(header); ok {
		return session, true
	}

	email := appconfig.FirstNonEmpty(
		header.Get("X-Auth-Request-Email"),
		header.Get("X-Forwarded-Email"),
	)
	preferredUsername := appconfig.FirstNonEmpty(
		header.Get("X-Auth-Request-Preferred-Username"),
		header.Get("X-Forwarded-Preferred-Username"),
	)
	subject := appconfig.FirstNonEmpty(
		header.Get("X-Auth-Request-Subject"),
		header.Get("X-Forwarded-Subject"),
		header.Get("X-Auth-Request-User"),
		header.Get("X-Forwarded-User"),
	)
	displayName := appconfig.FirstNonEmpty(email, preferredUsername, subject)
	if displayName == "" {
		return GatewaySession{}, false
	}

	claims := make([]GatewayClaim, 0, 4)
	addClaim := func(kind, value string) {
		if value != "" {
			claims = append(claims, GatewayClaim{Type: kind, Value: value})
		}
	}
	addClaim("sub", subject)
	addClaim("email", email)
	addClaim("name", appconfig.FirstNonEmpty(email, preferredUsername, subject))
	addClaim("preferred_username", preferredUsername)
	for _, group := range splitHeaderValues(headerValues(header, "X-Auth-Request-Groups", "X-Forwarded-Groups")) {
		addClaim("groups", group)
	}
	for _, role := range splitHeaderValues(headerValues(header, "X-Auth-Request-Roles", "X-Forwarded-Roles")) {
		addClaim("roles", role)
	}

	return GatewaySession{
		ProviderName: "oauth2-proxy",
		UserID:       appconfig.FirstNonEmpty(email, preferredUsername, subject),
		UserDetails:  displayName,
		Claims:       claims,
	}, true
}

func azureClientPrincipalSession(header http.Header) (GatewaySession, bool) {
	encoded := appconfig.FirstNonEmpty(header.Get("X-MS-CLIENT-PRINCIPAL"))
	if encoded == "" {
		return GatewaySession{}, false
	}
	payload, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return GatewaySession{}, false
	}
	var principal clientPrincipal
	if err := json.Unmarshal(payload, &principal); err != nil {
		return GatewaySession{}, false
	}
	displayName := appconfig.FirstNonEmpty(
		claimValue(principal.Claims, "emailaddress", "email"),
		claimValue(principal.Claims, "upn", "preferred_username", "unique_name"),
		claimValue(principal.Claims, "name"),
		header.Get("X-MS-CLIENT-PRINCIPAL-NAME"),
		header.Get("X-MS-CLIENT-PRINCIPAL-ID"),
	)
	if displayName == "" {
		return GatewaySession{}, false
	}
	claims := canonicalGatewayClaims(principal.Claims)
	return GatewaySession{
		ProviderName: appconfig.FirstNonEmpty(header.Get("X-MS-CLIENT-PRINCIPAL-IDP"), principal.IdentityProvider),
		UserID: appconfig.FirstNonEmpty(
			claimValue(claims, "email"),
			claimValue(claims, "preferred_username"),
			claimValue(claims, "oid"),
			header.Get("X-MS-CLIENT-PRINCIPAL-ID"),
			displayName,
		),
		UserDetails: displayName,
		Claims:      claims,
	}, true
}

func canonicalGatewayClaims(claims []GatewayClaim) []GatewayClaim {
	out := make([]GatewayClaim, 0, len(claims))
	for _, claim := range claims {
		kind := canonicalClaimType(claim.Type)
		value := strings.TrimSpace(claim.Value)
		if kind != "" && value != "" {
			out = append(out, GatewayClaim{Type: kind, Value: value})
		}
	}
	return out
}

func canonicalClaimType(kind string) string {
	normalized := strings.ToLower(strings.TrimSpace(kind))
	if normalized == "" {
		return ""
	}
	switch {
	case strings.HasSuffix(normalized, "/emailaddress"):
		return "email"
	case strings.HasSuffix(normalized, "/name"):
		return "name"
	case strings.HasSuffix(normalized, "/upn"):
		return "preferred_username"
	case strings.HasSuffix(normalized, "/role"):
		return "roles"
	}
	switch normalized {
	case "emailaddress":
		return "email"
	case "upn", "unique_name":
		return "preferred_username"
	case "role":
		return "roles"
	default:
		return normalized
	}
}

func claimValue(claims []GatewayClaim, names ...string) string {
	for _, name := range names {
		for _, claim := range claims {
			if canonicalClaimType(claim.Type) == name && strings.TrimSpace(claim.Value) != "" {
				return strings.TrimSpace(claim.Value)
			}
		}
	}
	return ""
}

// WriteClientPrincipalSession writes the object-shaped /.auth/me response used
// by simple static apps.
func WriteClientPrincipalSession(w http.ResponseWriter, r *http.Request) {
	session, ok := GatewaySessionFromHeaders(r.Header)
	if !ok {
		apphttp.WriteNoCacheJSON(w, http.StatusOK, map[string]any{"clientPrincipal": nil})
		return
	}
	apphttp.WriteNoCacheJSON(w, http.StatusOK, map[string]any{"clientPrincipal": session})
}

// WriteSessionArray writes the array-shaped /.auth/me response used by older
// gateway-auth app shells.
func WriteSessionArray(w http.ResponseWriter, r *http.Request) {
	session, ok := GatewaySessionFromHeaders(r.Header)
	if !ok {
		apphttp.WriteNoCacheJSON(w, http.StatusOK, []any{})
		return
	}
	apphttp.WriteNoCacheJSON(w, http.StatusOK, []GatewaySession{session})
}

// BrowserBundle serves the shared browser auth helper bundle.
func BrowserBundle(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		apphttp.MethodNotAllowed(w, http.MethodGet, http.MethodHead)
		return
	}
	b, err := browserAssets.ReadFile("web/idpauth.js")
	if err != nil {
		http.Error(w, "idpauth browser bundle missing", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
	noCacheHeaders(w)
	if r.Method == http.MethodHead {
		return
	}
	_, _ = w.Write(b)
}

func noCacheHeaders(w http.ResponseWriter) {
	apphttp.NoCacheHeaders(w)
}

func headerValues(header http.Header, names ...string) []string {
	var out []string
	for _, name := range names {
		out = append(out, header.Values(name)...)
	}
	return out
}

func splitHeaderValues(values []string) []string {
	var out []string
	for _, value := range values {
		for _, part := range strings.Split(value, ",") {
			if trimmed := strings.TrimSpace(part); trimmed != "" {
				out = append(out, trimmed)
			}
		}
	}
	return out
}
