package app

import (
	"embed"
	"net/http"

	"platform.local/appconfig"
	"platform.local/apphttp"
	"platform.local/appshell"
	"platform.local/idpauth"
)

//go:embed web/*
var web embed.FS

func NewServer(cfg Config, verifier idpauth.TokenVerifier) http.Handler {
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
	server := &server{cfg: cfg, verifier: verifier, analyzer: newSubnetAnalyzer(cfg.ProviderRangeSources)}
	if cfg.RuntimeRole == "backend" || cfg.RuntimeRole == "all" {
		requireAuth := idpauth.Authenticator{Mode: cfg.AuthMode, Verifier: verifier}.Middleware(idpauth.AuthFailureMessages{
			MissingBearerToken: "Missing or invalid bearer token",
			InvalidToken:       "Invalid token",
		})
		mux.HandleFunc("GET /api/v1/health", server.health)
		mux.HandleFunc("GET /api/v1/health/ready", server.ready)
		mux.HandleFunc("GET /api/v1/health/live", server.live)
		mux.Handle("POST /api/v1/ipv4/validate", requireAuth(http.HandlerFunc(server.validateAddress)))
		mux.Handle("POST /api/v1/ipv4/check-private", requireAuth(http.HandlerFunc(server.checkPrivate)))
		mux.Handle("POST /api/v1/ipv4/check-cloudflare", requireAuth(http.HandlerFunc(server.checkCloudflare)))
		mux.Handle("POST /api/v1/provider-ranges/check", requireAuth(http.HandlerFunc(server.checkProviderRange)))
		mux.Handle("POST /api/v1/provider-ranges/cache/invalidate", requireAuth(http.HandlerFunc(server.invalidateProviderRangeCache)))
		mux.Handle("POST /api/v1/provider-ranges/cache/refresh", requireAuth(http.HandlerFunc(server.refreshProviderRangeCache)))
		mux.Handle("POST /api/v1/ipv4/subnet-info", requireAuth(http.HandlerFunc(server.subnetInfoIPv4)))
		mux.Handle("POST /api/v1/ipv6/subnet-info", requireAuth(http.HandlerFunc(server.subnetInfoIPv6)))
		mux.HandleFunc("GET /api/whoami", server.whoami)
		mux.HandleFunc("GET /api/v1/whoami", server.whoami)
	}
	if cfg.RuntimeRole == "frontend" {
		mux.Handle("/api/", server.apiProxy())
	}
	if cfg.RuntimeRole == "frontend" || cfg.RuntimeRole == "all" {
		mux.HandleFunc("GET /runtime-config.js", server.runtimeConfig)
		appshell.RegisterSharedAssets(mux, idpauth.BrowserBundle)
		mux.HandleFunc("GET /favicon.ico", appshell.SVGFavicon(subnetcalcFaviconSVG))
		mux.HandleFunc("GET /signed-out.html", appshell.SignedOutPage(appshell.SignedOutPageConfig{
			AppName:     "IPv4 Subnet Calculator",
			Tagline:     "Vanilla HTML, CSS, JavaScript, and a Go API.",
			SessionName: "subnet calculator",
			Stylesheet:  "/style.css",
			Favicon:     "/favicon.ico",
		}))
		mux.Handle("/", appshell.StaticFiles(web, "web"))
	}
	return apphttp.RequestLogger("subnetcalc", nil, mux)
}

type server struct {
	cfg      Config
	verifier idpauth.TokenVerifier
	analyzer *subnetAnalyzer
}

func (s *server) health(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteBrowserAppHealth(w, map[string]any{
		"status":                          "healthy",
		"service":                         "Subnet Calculator API (Go)",
		"version":                         "1.0.0",
		"using_live_cloudflare_ranges":    false,
		"server_side_token_validation":    s.cfg.AuthMode == "oidc",
		"intentional_backend_dependency":  "github.com/coreos/go-oidc/v3/oidc",
		"intentional_frontend_dependency": "none",
	})
}

func (s *server) ready(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteRoleStatus(w, http.StatusOK, "ready", "")
}

func (s *server) live(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteRoleStatus(w, http.StatusOK, "alive", "")
}

func (s *server) whoami(w http.ResponseWriter, r *http.Request) {
	claims, ok := s.currentUser(w, r)
	if !ok {
		return
	}
	apphttp.WriteJSON(w, http.StatusOK, claims)
}

func (s *server) currentUser(w http.ResponseWriter, r *http.Request) (idpauth.UserClaims, bool) {
	return (idpauth.Authenticator{Mode: s.cfg.AuthMode, Verifier: s.verifier}).CurrentUserOrWriteError(w, r, idpauth.AuthFailureMessages{
		MissingBearerToken: "Missing or invalid bearer token",
		InvalidToken:       "Invalid token",
	})
}

func (s *server) runtimeConfig(w http.ResponseWriter, r *http.Request) {
	runtimePayload := appshell.RuntimeConfigPayload(r, appshell.RuntimeConfigOptions{
		Base: map[string]any{
			"authMethod":    s.cfg.AuthMode,
			"apiAuthMethod": s.cfg.APIAuthMode,
			"backendURL":    s.cfg.BackendURL,
			"oidcAuthority": appconfig.NormalizeURL(s.cfg.OIDCIssuer),
			"oidcClientId":  s.cfg.OIDCClientID,
		},
		OIDCRedirect:        s.cfg.OIDCRedirect,
		IncludeOIDCRedirect: true,
		ShowNetworkPath:     s.cfg.ShowNetworkPath,
		NetworkHopsJSON:     s.cfg.NetworkHops,
	})
	appshell.WriteScriptConfigForRequest(w, r, "window.SUBNETCALC_RUNTIME_CONFIG", runtimePayload)
}

func (s *server) apiProxy() http.Handler {
	return apphttp.NewAPIProxy(apphttp.APIProxyConfig{
		BackendURL: s.cfg.BackendURL,
	})
}

const subnetcalcFaviconSVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="12" fill="#151b21"/><path d="M12 18h40v8H12zm0 20h40v8H12z" fill="#2d6cdf"/><path d="M18 12v40m28-40v40" stroke="#e8eef4" stroke-width="4"/></svg>`
