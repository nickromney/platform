// Package idpauth provides shared identity and authentication primitives
// used across platform apps: token verification, user claims, and bearer
// token extraction.
package idpauth

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/coreos/go-oidc/v3/oidc"
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

// TokenVerifier verifies a raw bearer token string and returns the claims
// if valid. Implementations must be safe for concurrent use.
type TokenVerifier interface {
	Verify(ctx context.Context, token string) (UserClaims, error)
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

// GatewaySessionFromHeaders normalizes oauth2-proxy identity headers into the
// browser-facing session shape used by platform apps. It prefers email for
// display and stable user id because X-Forwarded-User is often an opaque OIDC
// subject UUID.
func GatewaySessionFromHeaders(header http.Header) (GatewaySession, bool) {
	email := firstNonEmpty(
		header.Get("X-Auth-Request-Email"),
		header.Get("X-Forwarded-Email"),
	)
	preferredUsername := firstNonEmpty(
		header.Get("X-Auth-Request-Preferred-Username"),
		header.Get("X-Forwarded-Preferred-Username"),
	)
	subject := firstNonEmpty(
		header.Get("X-Auth-Request-Subject"),
		header.Get("X-Forwarded-Subject"),
		header.Get("X-Auth-Request-User"),
		header.Get("X-Forwarded-User"),
	)
	displayName := firstNonEmpty(email, preferredUsername, subject)
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
	addClaim("name", firstNonEmpty(email, preferredUsername, subject))
	addClaim("preferred_username", preferredUsername)
	for _, group := range splitHeaderValues(header.Values("X-Auth-Request-Groups")) {
		addClaim("groups", group)
	}

	return GatewaySession{
		ProviderName: "oauth2-proxy",
		UserID:       firstNonEmpty(email, preferredUsername, subject),
		UserDetails:  displayName,
		Claims:       claims,
	}, true
}

// WriteClientPrincipalSession writes the object-shaped /.auth/me response used
// by simple static apps.
func WriteClientPrincipalSession(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	session, ok := GatewaySessionFromHeaders(r.Header)
	if !ok {
		_ = json.NewEncoder(w).Encode(map[string]any{"clientPrincipal": nil})
		return
	}
	_ = json.NewEncoder(w).Encode(map[string]any{"clientPrincipal": session})
}

// WriteSessionArray writes the array-shaped /.auth/me response used by older
// gateway-auth app shells.
func WriteSessionArray(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	session, ok := GatewaySessionFromHeaders(r.Header)
	if !ok {
		_ = json.NewEncoder(w).Encode([]any{})
		return
	}
	_ = json.NewEncoder(w).Encode([]GatewaySession{session})
}

// BrowserBundle serves the shared browser auth helper bundle.
func BrowserBundle(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	b, err := browserAssets.ReadFile("web/idpauth.js")
	if err != nil {
		http.Error(w, "idpauth browser bundle missing", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=3600")
	if r.Method == http.MethodHead {
		return
	}
	_, _ = w.Write(b)
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if trimmed := strings.TrimSpace(value); trimmed != "" {
			return trimmed
		}
	}
	return ""
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
