package app

import (
	"context"
	"fmt"
	"net/http"

	"github.com/coreos/go-oidc/v3/oidc"
)

type OIDCVerifier struct {
	verifier *oidc.IDTokenVerifier
}

func NewOIDCVerifier(ctx context.Context, issuer, audience, jwksURI string) (*OIDCVerifier, error) {
	if issuer == "" || audience == "" {
		return nil, fmt.Errorf("OIDC_ISSUER_URL and OIDC_AUDIENCE are required when AUTH_METHOD=oidc")
	}
	if jwksURI != "" {
		keySet := oidc.NewRemoteKeySet(ctx, jwksURI)
		return &OIDCVerifier{verifier: oidc.NewVerifier(issuer, keySet, &oidc.Config{ClientID: audience})}, nil
	}
	provider, err := oidc.NewProvider(ctx, issuer)
	if err != nil {
		return nil, err
	}
	return &OIDCVerifier{verifier: provider.Verifier(&oidc.Config{ClientID: audience})}, nil
}

func (v *OIDCVerifier) Verify(r *http.Request, token string) (UserClaims, error) {
	idToken, err := v.verifier.Verify(r.Context(), token)
	if err != nil {
		return UserClaims{}, ErrInvalidToken
	}
	var raw struct {
		Subject           string   `json:"sub"`
		PreferredUsername string   `json:"preferred_username"`
		Email             string   `json:"email"`
		Groups            []string `json:"groups"`
	}
	if err := idToken.Claims(&raw); err != nil {
		return UserClaims{}, err
	}
	return UserClaims{
		Subject:           raw.Subject,
		PreferredUsername: raw.PreferredUsername,
		Email:             raw.Email,
		Groups:            raw.Groups,
	}, nil
}
