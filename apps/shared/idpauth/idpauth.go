// Package idpauth provides shared identity and authentication primitives
// used across platform apps: token verification, user claims, and bearer
// token extraction.
package idpauth

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/coreos/go-oidc/v3/oidc"
)

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
