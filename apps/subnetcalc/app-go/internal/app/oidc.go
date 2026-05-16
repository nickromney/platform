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

func NewOIDCVerifier(ctx context.Context, issuer, clientID string) (*OIDCVerifier, error) {
	if issuer == "" || clientID == "" {
		return nil, fmt.Errorf("OIDC_ISSUER_URL and OIDC_CLIENT_ID are required when AUTH_METHOD=oidc")
	}
	provider, err := oidc.NewProvider(ctx, issuer)
	if err != nil {
		return nil, err
	}
	return &OIDCVerifier{verifier: provider.Verifier(&oidc.Config{ClientID: clientID})}, nil
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
