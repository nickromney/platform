package app

import (
	"embed"
	"encoding/json"
	"errors"
	"io/fs"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strconv"
	"strings"
)

//go:embed web/*
var web embed.FS

func NewServer(cfg Config, verifier ...TokenVerifier) http.Handler {
	if cfg.AuthMode == "" {
		cfg.AuthMode = "none"
	}
	if cfg.APIAuthMode == "" {
		cfg.APIAuthMode = cfg.AuthMode
	}
	if cfg.RuntimeRole == "" {
		cfg.RuntimeRole = "all"
	}

	mux := http.NewServeMux()
	var tokenVerifier TokenVerifier
	if len(verifier) > 0 {
		tokenVerifier = verifier[0]
	}
	srv := &server{cfg: cfg, store: newStore(cfg), verifier: tokenVerifier}
	if cfg.RuntimeRole == "backend" || cfg.RuntimeRole == "frontend" || cfg.RuntimeRole == "all" {
		mux.HandleFunc("GET /health", srv.frontendHealth)
		mux.HandleFunc("GET /health/ready", srv.frontendReady)
		mux.HandleFunc("GET /health/live", srv.frontendLive)
	}
	if cfg.RuntimeRole == "backend" || cfg.RuntimeRole == "all" {
		mux.HandleFunc("GET /api/v1/health", srv.health)
		mux.HandleFunc("GET /api/v1/health/ready", srv.ready)
		mux.HandleFunc("GET /api/v1/health/live", srv.live)
		mux.HandleFunc("GET /api/whoami", srv.whoami)
		mux.HandleFunc("GET /api/v1/whoami", srv.whoami)
		mux.Handle("GET /api/v1/comments", srv.requireAuth(http.HandlerFunc(srv.listComments)))
		mux.Handle("POST /api/v1/comments", srv.requireAuth(http.HandlerFunc(srv.createComment)))
		mux.Handle("POST /api/v1/sentiment/classify", srv.requireAuth(http.HandlerFunc(srv.classifyOnly)))
	}
	if cfg.RuntimeRole == "frontend" {
		mux.Handle("/api/", srv.apiProxy())
	}
	if cfg.RuntimeRole == "frontend" || cfg.RuntimeRole == "all" {
		mux.HandleFunc("GET /runtime-config.js", srv.runtimeConfig)
		mux.HandleFunc("GET /favicon.ico", srv.favicon)
		mux.HandleFunc("/", srv.static)
	}
	return mux
}

type server struct {
	cfg      Config
	store    store
	verifier TokenVerifier
}

func (s *server) health(w http.ResponseWriter, _ *http.Request) {
	if err := s.store.ensure(); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status":                       "ok",
		"role":                         "backend",
		"service":                      "sentiment-api",
		"server_side_token_validation": s.cfg.AuthMode == "oidc",
	})
}

func (s *server) ready(w http.ResponseWriter, _ *http.Request) {
	if err := s.store.ensure(); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready", "role": "backend"})
}

func (s *server) live(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "alive", "role": "backend"})
}

func (s *server) frontendHealth(w http.ResponseWriter, _ *http.Request) {
	role := s.cfg.RuntimeRole
	if role == "" {
		role = "all"
	}
	service := "sentiment-auth-ui"
	if role == "backend" {
		service = "sentiment-api"
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"status":  "ok",
		"role":    role,
		"service": service,
	})
}

func (s *server) frontendReady(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready", "role": s.cfg.RuntimeRole})
}

func (s *server) frontendLive(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "alive", "role": s.cfg.RuntimeRole})
}

func (s *server) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, ok := s.currentUser(w, r); !ok {
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *server) whoami(w http.ResponseWriter, r *http.Request) {
	claims, ok := s.currentUser(w, r)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, claims)
}

func (s *server) currentUser(w http.ResponseWriter, r *http.Request) (UserClaims, bool) {
	if strings.EqualFold(s.cfg.AuthMode, "none") {
		return UserClaims{Subject: "anonymous", Groups: []string{}}, true
	}
	if s.verifier == nil {
		writeJSON(w, http.StatusServiceUnavailable, errorResponse{Error: "OIDC verifier is not configured"})
		return UserClaims{}, false
	}
	token := bearerToken(r)
	if token == "" {
		writeJSON(w, http.StatusUnauthorized, errorResponse{Error: "missing bearer token"})
		return UserClaims{}, false
	}
	claims, err := s.verifier.Verify(r.Context(), token)
	if err != nil {
		status := http.StatusUnauthorized
		if !errors.Is(err, ErrInvalidToken) {
			status = http.StatusBadGateway
		}
		writeJSON(w, status, errorResponse{Error: "invalid token"})
		return UserClaims{}, false
	}
	if claims.Groups == nil {
		claims.Groups = []string{}
	}
	return claims, true
}

func (s *server) listComments(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 {
		limit = 25
	}
	comments, err := s.store.list(limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string][]Comment{"items": comments})
}

func (s *server) createComment(w http.ResponseWriter, r *http.Request) {
	var req classifyRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	text := strings.TrimSpace(req.Text)
	if text == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "text is required"})
		return
	}
	result := classify(text)
	comment := newComment(text, result)
	if err := s.store.append(comment); err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, comment)
}

func (s *server) classifyOnly(w http.ResponseWriter, r *http.Request) {
	var req classifyRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	text := strings.TrimSpace(req.Text)
	if text == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "text is required"})
		return
	}
	writeJSON(w, http.StatusOK, classify(text))
}

func (s *server) static(w http.ResponseWriter, r *http.Request) {
	sub, err := fs.Sub(web, "web")
	if err != nil {
		http.Error(w, "static assets unavailable", http.StatusInternalServerError)
		return
	}
	setFrontendCacheHeaders(w)
	http.FileServer(http.FS(sub)).ServeHTTP(w, r)
}

func (s *server) favicon(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) runtimeConfig(w http.ResponseWriter, _ *http.Request) {
	payload := map[string]any{
		"authMethod":      s.cfg.AuthMode,
		"apiAuthMethod":   s.cfg.APIAuthMode,
		"apiBasePath":     defaultString(s.cfg.APIBasePath, "/api/v1"),
		"backendURL":      s.cfg.BackendURL,
		"showNetworkPath": parseBoolDefault(s.cfg.ShowNetworkPath, true),
	}
	if s.cfg.NetworkHops != "" {
		var hops any
		if err := json.Unmarshal([]byte(s.cfg.NetworkHops), &hops); err == nil {
			payload["networkHops"] = hops
		}
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		http.Error(w, "runtime config unavailable", http.StatusInternalServerError)
		return
	}
	setFrontendCacheHeaders(w)
	w.Header().Set("Content-Type", "application/javascript")
	_, _ = w.Write([]byte("window.SENTIMENT_RUNTIME_CONFIG = "))
	_, _ = w.Write(encoded)
	_, _ = w.Write([]byte(";\n"))
}

func parseBoolDefault(value string, fallback bool) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "":
		return fallback
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}

func defaultString(value, fallback string) string {
	if value != "" {
		return value
	}
	return fallback
}

func setFrontendCacheHeaders(w http.ResponseWriter) {
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate, max-age=0")
	w.Header().Set("Pragma", "no-cache")
	w.Header().Set("Expires", "0")
}

func (s *server) apiProxy() http.Handler {
	if s.cfg.BackendURL == "" {
		return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			writeJSON(w, http.StatusBadGateway, errorResponse{Error: "BACKEND_URL is not configured"})
		})
	}
	target, err := url.Parse(s.cfg.BackendURL)
	if err != nil {
		return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			writeJSON(w, http.StatusBadGateway, errorResponse{Error: "BACKEND_URL is invalid"})
		})
	}
	proxy := httputil.NewSingleHostReverseProxy(target)
	proxy.ErrorHandler = func(w http.ResponseWriter, _ *http.Request, _ error) {
		writeJSON(w, http.StatusBadGateway, errorResponse{Error: "Backend API unavailable"})
	}
	return proxy
}

func decodeJSON(w http.ResponseWriter, r *http.Request, out any) bool {
	defer r.Body.Close()
	if err := json.NewDecoder(r.Body).Decode(out); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid JSON body"})
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		slog.Error("write response", "error", err)
	}
}
