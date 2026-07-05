package app

import (
	"bytes"
	"context"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"platform.local/apphttp"
	"platform.local/appshell"
	"platform.local/idpauth"
)

//go:embed web/*
var web embed.FS

type HTTPDoer interface {
	Do(*http.Request) (*http.Response, error)
}

type server struct {
	cfg      Config
	client   HTTPDoer
	verifier idpauth.TokenVerifier
}

func NewServer(cfg Config, client HTTPDoer, verifier idpauth.TokenVerifier) http.Handler {
	if client == nil {
		client = http.DefaultClient
	}
	s := &server{cfg: cfg, client: client, verifier: verifier}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.health)
	mux.HandleFunc("GET /auth", s.auth)
	mux.HandleFunc("POST /auth/validate", s.authValidate)
	mux.HandleFunc("POST /chat", s.chat)
	mux.HandleFunc("GET /.auth/me", idpauth.WriteClientPrincipalSession)
	mux.HandleFunc("GET /runtime-config.js", s.runtimeConfig)
	appshell.RegisterSharedAssets(mux, idpauth.BrowserBundle)
	mux.HandleFunc("GET /favicon.ico", appshell.SVGFavicon(authChatFaviconSVG))
	mux.HandleFunc("GET /signed-out.html", appshell.SignedOutPage(appshell.SignedOutPageConfig{
		AppName:     "Auth Chat",
		Tagline:     "Keycloak-authenticated chat route.",
		SessionName: "Auth Chat",
		Favicon:     "/favicon.ico",
		PanelClass:  "auth-chat-signed-out",
	}))
	mux.Handle("/", appshell.StaticFiles(web, "web"))
	return apphttp.RequestLogger("auth-chat", nil, mux)
}

func (s *server) health(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteBrowserAppHealth(w, map[string]any{
		"status":        "ok",
		"service":       "auth-chat",
		"api_auth_mode": s.cfg.APIAuthMode,
		"llm_url":       s.cfg.LLMURL,
		"llm_model":     s.cfg.LLMModel,
	})
}

func (s *server) runtimeConfig(w http.ResponseWriter, r *http.Request) {
	payload := appshell.RuntimeConfigPayload(r, appshell.RuntimeConfigOptions{
		Base: map[string]any{
			"authEndpoint":         "/auth",
			"authValidateEndpoint": "/auth/validate",
			"chatEndpoint":         "/chat",
			"sessionEndpoint":      "/.auth/me",
			"model":                s.cfg.LLMModel,
			"modelProvider":        "openai-compatible",
			"llmUrl":               publicLLMURL(s.cfg.LLMURL),
			"apiAuthMode":          s.cfg.APIAuthMode,
			"publicBaseUrl":        s.cfg.PublicBaseURL,
		},
		ShowNetworkPath: s.cfg.ShowNetworkPath,
		NetworkHopsJSON: s.cfg.NetworkHops,
	})
	appshell.WriteScriptConfigForRequest(w, r, "window.AUTH_CHAT_CONFIG", payload)
}

func (s *server) auth(w http.ResponseWriter, r *http.Request) {
	principal, ok := s.currentPrincipal(w, r)
	if !ok {
		return
	}
	apphttp.WriteNoCacheJSON(w, http.StatusOK, s.authEvidence(r, principal))
}

func (s *server) authValidate(w http.ResponseWriter, r *http.Request) {
	principal, ok := s.currentPrincipal(w, r)
	if !ok {
		return
	}
	apphttp.WriteNoCacheJSON(w, http.StatusOK, map[string]any{
		"valid":    true,
		"evidence": s.authEvidence(r, principal),
	})
}

func (s *server) chat(w http.ResponseWriter, r *http.Request) {
	started := time.Now()
	principal, ok := s.currentPrincipal(w, r)
	if !ok {
		return
	}
	var req chatRequest
	if !apphttp.DecodeJSONError(w, r, &req, "invalid JSON body") {
		return
	}
	req.Message = strings.TrimSpace(req.Message)
	if req.Message == "" {
		apphttp.WriteError(w, http.StatusBadRequest, "message is required")
		return
	}
	if strings.TrimSpace(req.Model) == "" {
		req.Model = s.cfg.LLMModel
	}
	result, err := s.complete(r.Context(), req, principal)
	if err != nil {
		apphttp.WriteJSON(w, http.StatusBadGateway, map[string]any{
			"error":       err.Error(),
			"duration_ms": time.Since(started).Milliseconds(),
			"auth":        s.authEvidence(r, principal),
			"model": map[string]any{
				"provider": "openai-compatible",
				"model":    req.Model,
				"status":   "error",
				"route":    publicLLMURL(s.cfg.LLMURL),
			},
		})
		return
	}
	result.DurationMillis = time.Since(started).Milliseconds()
	result.Auth = s.authEvidence(r, principal)
	apphttp.WriteJSON(w, http.StatusOK, result)
}

func (s *server) currentPrincipal(w http.ResponseWriter, r *http.Request) (principal, bool) {
	switch strings.ToLower(strings.TrimSpace(s.cfg.APIAuthMode)) {
	case "", "none":
		return principal{
			Source: "none",
			Claims: idpauth.UserClaims{
				Subject: "anonymous",
				Groups:  []string{},
			},
		}, true
	case "gateway", "sso", "oauth2-proxy":
		session, ok := idpauth.GatewaySessionFromHeaders(r.Header)
		if !ok {
			apphttp.WriteError(w, http.StatusUnauthorized, "gateway session is required")
			return principal{}, false
		}
		return principal{Source: "gateway", Session: &session, Claims: claimsFromSession(session)}, true
	case "oidc":
		claims, ok := (idpauth.Authenticator{Mode: "oidc", Verifier: s.verifier}).CurrentUserOrWriteError(w, r, idpauth.AuthFailureMessages{
			MissingBearerToken: "missing bearer token",
			InvalidToken:       "invalid bearer token",
		})
		if !ok {
			return principal{}, false
		}
		return principal{Source: "oidc", Claims: claims}, true
	default:
		apphttp.WriteError(w, http.StatusInternalServerError, "unsupported API auth mode")
		return principal{}, false
	}
}

func (s *server) authEvidence(r *http.Request, user principal) map[string]any {
	token := inboundBearerEvidence(r)
	return map[string]any{
		"status":    authStatus(user),
		"source":    user.Source,
		"user":      publicUserClaims(user.Claims),
		"session":   user.Session,
		"token":     token,
		"endpoints": map[string]string{"auth": "/auth", "auth_validate": "/auth/validate", "chat": "/chat", "session": "/.auth/me"},
		"oidc": map[string]string{
			"issuer":   s.cfg.OIDCIssuer,
			"audience": s.cfg.OIDCAudience,
			"client":   s.cfg.OIDCClientID,
		},
	}
}

func authStatus(user principal) string {
	if user.Source == "none" {
		return "anonymous"
	}
	return "authenticated"
}

func claimsFromSession(session idpauth.GatewaySession) idpauth.UserClaims {
	claims := idpauth.UserClaims{Groups: []string{}, Roles: []string{}}
	for _, claim := range session.Claims {
		switch claim.Type {
		case "sub":
			claims.Subject = claim.Value
		case "email":
			claims.Email = claim.Value
		case "preferred_username", "name":
			if claims.PreferredUsername == "" {
				claims.PreferredUsername = claim.Value
			}
		case "groups":
			claims.Groups = append(claims.Groups, claim.Value)
		case "roles":
			claims.Roles = append(claims.Roles, claim.Value)
		}
	}
	if claims.Subject == "" {
		claims.Subject = session.UserID
	}
	if claims.Email == "" && strings.Contains(session.UserID, "@") {
		claims.Email = session.UserID
	}
	if claims.PreferredUsername == "" {
		claims.PreferredUsername = session.UserDetails
	}
	return claims
}

func publicUserClaims(claims idpauth.UserClaims) map[string]any {
	return map[string]any{
		"sub":                claims.Subject,
		"email":              claims.Email,
		"preferred_username": claims.PreferredUsername,
		"groups":             claims.Groups,
		"roles":              claims.Roles,
	}
}

func inboundBearerEvidence(r *http.Request) map[string]any {
	source := ""
	token := idpauth.BearerToken(r)
	if token != "" {
		source = "Authorization"
	}
	if token == "" {
		for _, header := range []string{"X-Auth-Request-Access-Token", "X-Forwarded-Access-Token"} {
			if value := strings.TrimSpace(r.Header.Get(header)); value != "" {
				token = value
				source = header
				break
			}
		}
	}
	evidence := map[string]any{"present": token != "", "source": source}
	if token != "" {
		evidence["length"] = len(token)
		evidence["redacted"] = redactToken(token)
	}
	return evidence
}

func redactToken(token string) string {
	token = strings.TrimSpace(token)
	if len(token) <= 12 {
		return "***"
	}
	return token[:6] + "..." + token[len(token)-4:]
}

func (s *server) complete(ctx context.Context, req chatRequest, user principal) (chatResponse, error) {
	if strings.TrimSpace(s.cfg.LLMURL) == "" {
		return chatResponse{}, errors.New("LLM URL is not configured")
	}
	timeout := s.cfg.LLMTimeout
	if timeout <= 0 {
		timeout = 45 * time.Second
	}
	callCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	messages := completionMessages(req, user)
	payload := map[string]any{
		"model":       req.Model,
		"messages":    messages,
		"max_tokens":  s.cfg.LLMMaxTokens,
		"temperature": s.cfg.LLMTemperature,
		"stream":      false,
	}
	body, _ := json.Marshal(payload)
	outbound, err := http.NewRequestWithContext(callCtx, http.MethodPost, s.cfg.LLMURL, bytes.NewReader(body))
	if err != nil {
		return chatResponse{}, err
	}
	outbound.Header.Set("Content-Type", "application/json")
	outbound.Header.Set("Accept", "application/json")
	if s.cfg.LLMAPIKey != "" {
		outbound.Header.Set("Authorization", "Bearer "+s.cfg.LLMAPIKey)
	}
	started := time.Now()
	resp, err := s.boundedClient(timeout).Do(outbound)
	if err != nil {
		return chatResponse{}, err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return chatResponse{}, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return chatResponse{}, fmt.Errorf("LLM returned %s: %s", resp.Status, truncate(string(raw), 220))
	}
	var completion completionResponse
	if err := json.Unmarshal(raw, &completion); err != nil {
		return chatResponse{}, err
	}
	answer := strings.TrimSpace(completion.firstContent())
	if answer == "" {
		return chatResponse{}, errors.New("LLM returned an empty completion")
	}
	modelName := strings.TrimSpace(completion.Model)
	if modelName == "" {
		modelName = req.Model
	}
	return chatResponse{
		Assistant: answer,
		Model: modelEvidence{
			Provider:       "openai-compatible",
			Model:          modelName,
			Status:         "ok",
			Route:          publicLLMURL(s.cfg.LLMURL),
			UpstreamStatus: resp.StatusCode,
			LatencyMillis:  time.Since(started).Milliseconds(),
		},
		Usage: completion.Usage,
	}, nil
}

func (s *server) boundedClient(timeout time.Duration) HTTPDoer {
	if client, ok := s.client.(*http.Client); ok {
		bounded := *client
		if bounded.Timeout == 0 || bounded.Timeout > timeout {
			bounded.Timeout = timeout
		}
		return &bounded
	}
	return s.client
}

func completionMessages(req chatRequest, user principal) []chatMessage {
	messages := []chatMessage{
		{
			Role:    "system",
			Content: "You are Auth Chat, an internal platform assistant. /no_think Answer concisely and directly. Do not reveal hidden reasoning. If identity context is relevant, use only the supplied non-secret identity fields.",
		},
	}
	for _, item := range req.Messages {
		role := strings.TrimSpace(item.Role)
		content := strings.TrimSpace(item.Content)
		if content == "" || (role != "user" && role != "assistant" && role != "system") {
			continue
		}
		messages = append(messages, chatMessage{Role: role, Content: content})
		if len(messages) >= 9 {
			break
		}
	}
	identity := publicUserClaims(user.Claims)
	identityJSON, _ := json.Marshal(identity)
	messages = append(messages,
		chatMessage{Role: "system", Content: "Authenticated caller evidence: " + string(identityJSON)},
		chatMessage{Role: "user", Content: req.Message},
	)
	return messages
}

func publicLLMURL(raw string) string {
	parsed, err := url.Parse(raw)
	if err != nil {
		return raw
	}
	parsed.User = nil
	parsed.RawQuery = ""
	parsed.Fragment = ""
	return parsed.String()
}

func truncate(value string, limit int) string {
	value = strings.TrimSpace(value)
	if limit <= 0 || len(value) <= limit {
		return value
	}
	return value[:limit] + "..."
}

const authChatFaviconSVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="12" fill="#12343b"/><path d="M18 32a14 14 0 1 1 26.2 6.8L48 47l-8.2-3.6A14 14 0 0 1 18 32Z" fill="#e8f7f1"/><path d="M27 31h10M27 37h6" stroke="#156f78" stroke-width="4" stroke-linecap="round"/></svg>`
