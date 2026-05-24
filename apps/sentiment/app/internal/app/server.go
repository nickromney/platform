package app

import (
	"embed"
	"net/http"
	"strings"

	"platform.local/appconfig"
	"platform.local/apphttp"
	"platform.local/appshell"
	"platform.local/idpauth"
)

//go:embed web/*
var web embed.FS

func NewServer(cfg Config, verifier ...idpauth.TokenVerifier) http.Handler {
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
	var tokenVerifier idpauth.TokenVerifier
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
		appshell.RegisterSharedAssets(mux, idpauth.BrowserBundle)
		mux.HandleFunc("GET /favicon.ico", appshell.SVGFavicon(sentimentFaviconSVG))
		mux.HandleFunc("GET /signed-out.html", appshell.SignedOutPage(appshell.SignedOutPageConfig{
			AppName:     "Sentiment",
			Tagline:     "Classify comments with a minimal vanilla UI and Go API.",
			SessionName: "sentiment",
			Stylesheet:  "/style.css",
		}))
		mux.Handle("/", appshell.StaticFiles(web, "web"))
	}
	return mux
}

type server struct {
	cfg      Config
	store    store
	verifier idpauth.TokenVerifier
}

func (s *server) health(w http.ResponseWriter, _ *http.Request) {
	if err := s.store.ensure(); err != nil {
		apphttp.WriteError(w, http.StatusInternalServerError, err.Error())
		return
	}
	apphttp.WriteBrowserAppHealth(w, map[string]any{
		"status":                       "ok",
		"role":                         "backend",
		"service":                      "Sentiment API (Go)",
		"version":                      "1.0.0",
		"server_side_token_validation": s.cfg.AuthMode == "oidc",
	})
}

func (s *server) ready(w http.ResponseWriter, _ *http.Request) {
	if err := s.store.ensure(); err != nil {
		apphttp.WriteError(w, http.StatusInternalServerError, err.Error())
		return
	}
	apphttp.WriteRoleStatus(w, http.StatusOK, "ready", "backend")
}

func (s *server) live(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteRoleStatus(w, http.StatusOK, "alive", "backend")
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
	apphttp.WriteBrowserAppHealth(w, map[string]any{
		"status":  "ok",
		"role":    role,
		"service": service,
	})
}

func (s *server) frontendReady(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteRoleStatus(w, http.StatusOK, "ready", s.cfg.RuntimeRole)
}

func (s *server) frontendLive(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteRoleStatus(w, http.StatusOK, "alive", s.cfg.RuntimeRole)
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
	apphttp.WriteJSON(w, http.StatusOK, claims)
}

func (s *server) currentUser(w http.ResponseWriter, r *http.Request) (idpauth.UserClaims, bool) {
	claims, failure := (idpauth.Authenticator{Mode: s.cfg.AuthMode, Verifier: s.verifier}).CurrentUser(r)
	if failure != nil {
		apphttp.WriteError(w, failure.StatusCode, failure.Message)
		return idpauth.UserClaims{}, false
	}
	return claims, true
}

func (s *server) listComments(w http.ResponseWriter, r *http.Request) {
	limit := apphttp.QueryInt(r, "limit", 25)
	comments, err := s.store.list(limit)
	if err != nil {
		apphttp.WriteError(w, http.StatusInternalServerError, err.Error())
		return
	}
	apphttp.WriteJSON(w, http.StatusOK, map[string][]Comment{"items": comments})
}

func (s *server) createComment(w http.ResponseWriter, r *http.Request) {
	var req classifyRequest
	if !apphttp.DecodeJSONError(w, r, &req, "invalid JSON body") {
		return
	}
	text := strings.TrimSpace(req.Text)
	if text == "" {
		apphttp.WriteError(w, http.StatusBadRequest, "text is required")
		return
	}
	result := classify(text)
	comment := newComment(text, result)
	if err := s.store.append(comment); err != nil {
		apphttp.WriteError(w, http.StatusInternalServerError, err.Error())
		return
	}
	apphttp.WriteJSON(w, http.StatusOK, comment)
}

func (s *server) classifyOnly(w http.ResponseWriter, r *http.Request) {
	var req classifyRequest
	if !apphttp.DecodeJSONError(w, r, &req, "invalid JSON body") {
		return
	}
	text := strings.TrimSpace(req.Text)
	if text == "" {
		apphttp.WriteError(w, http.StatusBadRequest, "text is required")
		return
	}
	apphttp.WriteJSON(w, http.StatusOK, classify(text))
}

func (s *server) runtimeConfig(w http.ResponseWriter, r *http.Request) {
	payload := appshell.RuntimeConfigPayload(r, appshell.RuntimeConfigOptions{
		Base: map[string]any{
			"authMethod":    s.cfg.AuthMode,
			"apiAuthMethod": s.cfg.APIAuthMode,
			"apiBasePath":   appconfig.StringDefault(s.cfg.APIBasePath, "/api/v1"),
			"backendURL":    s.cfg.BackendURL,
		},
		ShowNetworkPath: s.cfg.ShowNetworkPath,
		NetworkHopsJSON: s.cfg.NetworkHops,
	})
	appshell.WriteScriptConfigForRequest(w, r, "window.SENTIMENT_RUNTIME_CONFIG", payload)
}

const sentimentFaviconSVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="12" fill="#17202a"/><path d="M18 24c6-10 22-10 28 0M18 40c6 10 22 10 28 0" fill="none" stroke="#4f9d7e" stroke-width="6" stroke-linecap="round"/><circle cx="24" cy="31" r="3" fill="#e8eef4"/><circle cx="40" cy="31" r="3" fill="#e8eef4"/></svg>`

func (s *server) apiProxy() http.Handler {
	return apphttp.NewAPIProxy(apphttp.APIProxyConfig{
		BackendURL: s.cfg.BackendURL,
	})
}
