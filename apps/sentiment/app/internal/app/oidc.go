package app

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"github.com/coreos/go-oidc/v3/oidc"
)

type OIDCVerifier struct {
	verifier *oidc.IDTokenVerifier
}

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

type TokenVerifier interface {
	Verify(ctx context.Context, token string) (UserClaims, error)
}

func bearerToken(r *http.Request) string {
	fields := strings.Fields(r.Header.Get("Authorization"))
	if len(fields) != 2 || !strings.EqualFold(fields[0], "Bearer") {
		return ""
	}
	return fields[1]
}
