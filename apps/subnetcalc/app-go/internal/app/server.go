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
	"strings"
)

//go:embed web/*
var web embed.FS

type TokenVerifier interface {
	Verify(r *http.Request, token string) (UserClaims, error)
}

func NewServer(cfg Config, verifier TokenVerifier) http.Handler {
	if cfg.AuthMode == "" {
		cfg.AuthMode = "none"
	}
	if cfg.RuntimeRole == "" {
		cfg.RuntimeRole = "all"
	}

	mux := http.NewServeMux()
	server := &server{cfg: cfg, verifier: verifier}
	if cfg.RuntimeRole == "backend" || cfg.RuntimeRole == "all" {
		mux.HandleFunc("GET /api/v1/health", server.health)
		mux.HandleFunc("GET /api/v1/health/ready", server.ready)
		mux.HandleFunc("GET /api/v1/health/live", server.live)
		mux.HandleFunc("POST /api/v1/ipv4/validate", server.validateAddress)
		mux.HandleFunc("POST /api/v1/ipv4/check-private", server.checkPrivate)
		mux.HandleFunc("POST /api/v1/ipv4/check-cloudflare", server.checkCloudflare)
		mux.HandleFunc("POST /api/v1/ipv4/subnet-info", server.subnetInfoIPv4)
		mux.HandleFunc("POST /api/v1/ipv6/subnet-info", server.subnetInfoIPv6)
		mux.HandleFunc("GET /api/whoami", server.whoami)
		mux.HandleFunc("GET /api/v1/whoami", server.whoami)
	}
	if cfg.RuntimeRole == "frontend" {
		mux.Handle("/api/", server.apiProxy())
	}
	if cfg.RuntimeRole == "frontend" || cfg.RuntimeRole == "all" {
		mux.HandleFunc("GET /favicon.ico", server.favicon)
		mux.HandleFunc("/", server.static)
	}
	return logMiddleware(mux)
}

type server struct {
	cfg      Config
	verifier TokenVerifier
}

func (s *server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":                          "healthy",
		"service":                         "Subnet Calculator API (Go)",
		"version":                         "1.0.0",
		"using_live_cloudflare_ranges":    false,
		"dependency_footprint":            "go-stdlib-plus-oidc",
		"frontend_dependency_footprint":   "vanilla",
		"server_side_token_validation":    s.cfg.AuthMode == "oidc",
		"transitive_javascript_packages":  0,
		"transitive_python_packages":      0,
		"intentional_backend_dependency":  "github.com/coreos/go-oidc/v3/oidc",
		"intentional_frontend_dependency": "none",
	})
}

func (s *server) ready(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (s *server) live(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "alive"})
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
		writeJSON(w, http.StatusServiceUnavailable, errorResponse{Detail: "OIDC verifier is not configured"})
		return UserClaims{}, false
	}

	auth := strings.TrimSpace(r.Header.Get("Authorization"))
	parts := strings.Fields(auth)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		writeJSON(w, http.StatusUnauthorized, errorResponse{Detail: "Missing or invalid bearer token"})
		return UserClaims{}, false
	}

	claims, err := s.verifier.Verify(r, parts[1])
	if err != nil {
		status := http.StatusUnauthorized
		if !errors.Is(err, ErrInvalidToken) {
			status = http.StatusBadGateway
		}
		writeJSON(w, status, errorResponse{Detail: "Invalid token"})
		return UserClaims{}, false
	}
	if claims.Groups == nil {
		claims.Groups = []string{}
	}
	return claims, true
}

func (s *server) static(w http.ResponseWriter, r *http.Request) {
	sub, err := fs.Sub(web, "web")
	if err != nil {
		http.Error(w, "static assets unavailable", http.StatusInternalServerError)
		return
	}
	http.FileServer(http.FS(sub)).ServeHTTP(w, r)
}

func (s *server) apiProxy() http.Handler {
	if s.cfg.BackendURL == "" {
		return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			writeJSON(w, http.StatusBadGateway, errorResponse{Detail: "BACKEND_URL is not configured"})
		})
	}
	target, err := url.Parse(s.cfg.BackendURL)
	if err != nil {
		return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			writeJSON(w, http.StatusBadGateway, errorResponse{Detail: "BACKEND_URL is invalid"})
		})
	}
	proxy := httputil.NewSingleHostReverseProxy(target)
	proxy.ErrorHandler = func(w http.ResponseWriter, _ *http.Request, _ error) {
		writeJSON(w, http.StatusBadGateway, errorResponse{Detail: "Backend API unavailable"})
	}
	return proxy
}

func (s *server) favicon(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "image/svg+xml")
	_, _ = w.Write([]byte(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="12" fill="#151b21"/><path d="M12 18h40v8H12zm0 20h40v8H12z" fill="#2d6cdf"/><path d="M18 12v40m28-40v40" stroke="#e8eef4" stroke-width="4"/></svg>`))
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	writeJSONHeader(w, status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		slog.Error("write response", "error", err)
	}
}

func writeJSONHeader(w http.ResponseWriter, status int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
}

func logMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		next.ServeHTTP(w, r)
	})
}
