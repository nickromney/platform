package app

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"io"
	"net/http"
	"net/http/httputil"
	"net/url"
	"path"
	"strings"
	"sync"
	"time"

	"platform.local/apphttp"
	"platform.local/appshell"
	"platform.local/idpauth"
)

func NewServer(cfg Config, verifier idpauth.TokenVerifier) http.Handler {
	cfg.applyDefaults()
	mux := http.NewServeMux()
	s := &server{
		cfg:      cfg,
		verifier: verifier,
		client:   apphttp.NewHTTPClient(time.Duration(cfg.ProxyTimeoutSeconds) * time.Second),
		traces:   newTraceStore(100),
		policies: map[string]string{},
	}
	for key, policy := range cfg.Policies {
		s.policies[key] = policy.XML
	}
	mux.HandleFunc("GET /apim/health", s.health)
	mux.HandleFunc("GET /apim/startup", s.startup)
	mux.HandleFunc("GET /apim/management/service", s.requireTenantKey(s.serviceProjection))
	mux.HandleFunc("GET /apim/management/summary", s.requireTenantKey(s.summary))
	mux.HandleFunc("GET /apim/management/apis", s.requireTenantKey(s.listAPIs))
	mux.HandleFunc("POST /apim/management/apis", s.requireTenantKey(s.upsertAPI))
	mux.HandleFunc("PUT /apim/management/apis/{id}", s.requireTenantKey(s.upsertAPI))
	mux.HandleFunc("DELETE /apim/management/apis/{id}", s.requireTenantKey(s.deleteAPI))
	mux.HandleFunc("GET /apim/management/products", s.requireTenantKey(s.listProducts))
	mux.HandleFunc("POST /apim/management/products", s.requireTenantKey(s.upsertProduct))
	mux.HandleFunc("PUT /apim/management/products/{id}", s.requireTenantKey(s.upsertProduct))
	mux.HandleFunc("DELETE /apim/management/products/{id}", s.requireTenantKey(s.deleteProduct))
	mux.HandleFunc("GET /apim/management/subscriptions", s.requireTenantKey(s.listSubscriptions))
	mux.HandleFunc("POST /apim/management/subscriptions", s.requireTenantKey(s.upsertSubscription))
	mux.HandleFunc("PUT /apim/management/subscriptions/{id}", s.requireTenantKey(s.upsertSubscription))
	mux.HandleFunc("DELETE /apim/management/subscriptions/{id}", s.requireTenantKey(s.deleteSubscription))
	mux.HandleFunc("GET /apim/management/named-values", s.requireTenantKey(s.listNamedValues))
	mux.HandleFunc("POST /apim/management/named-values", s.requireTenantKey(s.upsertNamedValue))
	mux.HandleFunc("PUT /apim/management/named-values/{id}", s.requireTenantKey(s.upsertNamedValue))
	mux.HandleFunc("DELETE /apim/management/named-values/{id}", s.requireTenantKey(s.deleteNamedValue))
	mux.HandleFunc("GET /apim/management/traces", s.requireTenantKey(s.listTraces))
	mux.HandleFunc("POST /apim/management/replay", s.requireTenantKey(s.replay))
	mux.HandleFunc("GET /apim/management/policies/{scope}/{name}", s.requireTenantKey(s.getPolicy))
	mux.HandleFunc("PUT /apim/management/policies/{scope}/{name}", s.requireTenantKey(s.putPolicy))
	mux.HandleFunc("POST /apim/management/subscriptions/{id}/rotate", s.requireTenantKey(s.rotateSubscriptionKey))
	mux.HandleFunc("GET /mock/health", s.mockHealth)
	mux.HandleFunc("GET /mock/echo", s.mockEcho)
	mux.HandleFunc("POST /mock/echo", s.mockEcho)
	mux.HandleFunc("GET /.auth/me", s.gatewayIdentity)
	mux.HandleFunc("GET /runtime-config.js", s.runtimeConfig)
	appshell.RegisterSharedAssets(mux, idpauth.BrowserBundle)
	mux.HandleFunc("GET /favicon.ico", appshell.SVGFavicon(apimFaviconSVG))
	mux.HandleFunc("GET /signed-out.html", appshell.SignedOutPage(appshell.SignedOutPageConfig{
		AppName:     "APIM Simulator",
		Tagline:     "Go gateway, vanilla console, APIM-shaped routing and tracing.",
		SessionName: "APIM simulator",
	}))
	mux.HandleFunc("/", s.dispatch)
	return apphttp.RequestLogger("apim", nil, corsMiddleware(cfg, mux))
}

type server struct {
	cfg      Config
	verifier idpauth.TokenVerifier
	client   *http.Client
	traces   *traceStore
	mu       sync.RWMutex
	policies map[string]string
}

func (s *server) health(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteBrowserAppHealth(w, map[string]any{
		"status":  "healthy",
		"service": "APIM Simulator (Go)",
		"version": "1.0.0",
		"routes":  len(s.cfg.Routes),
	})
}

func (s *server) startup(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteRoleStatus(w, http.StatusOK, "ready", "")
}

func (s *server) mockHealth(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteRoleStatus(w, http.StatusOK, "ready", "")
}

func (s *server) mockEcho(w http.ResponseWriter, r *http.Request) {
	body, err := apphttp.ReadRequestBody(r)
	if err != nil {
		apphttp.WriteError(w, http.StatusBadRequest, "Unable to read request body")
		return
	}
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{
		"ok":      true,
		"method":  r.Method,
		"path":    r.URL.Path,
		"headers": selectedHeaders(r.Header),
		"body":    string(body),
	})
}

func (s *server) gatewayIdentity(w http.ResponseWriter, r *http.Request) {
	idpauth.WriteSessionArray(w, r)
}

func (s *server) dispatch(w http.ResponseWriter, r *http.Request) {
	if s.serveStatic(w, r) {
		return
	}
	route, ok := s.resolveRoute(r)
	if !ok {
		apphttp.WriteError(w, http.StatusNotFound, "No APIM route matched the request")
		return
	}
	s.proxyRoute(w, r, route)
}

func (s *server) proxyRoute(w http.ResponseWriter, r *http.Request, route RouteConfig) {
	started := time.Now()
	body, err := apphttp.ReadRequestBody(r)
	if err != nil {
		apphttp.WriteError(w, http.StatusBadRequest, "Unable to read request body")
		return
	}
	auth, ok := s.authenticate(w, r, route)
	if !ok {
		return
	}
	if !s.authorizeRoute(w, route, auth) {
		return
	}
	subscription, ok := s.authorizeSubscription(w, r, route)
	if !ok {
		return
	}
	target, err := s.upstreamURL(route, r)
	if err != nil {
		apphttp.WriteError(w, http.StatusBadGateway, err.Error())
		return
	}
	req, err := http.NewRequestWithContext(r.Context(), r.Method, target, bytes.NewReader(body))
	if err != nil {
		apphttp.WriteError(w, http.StatusBadGateway, "Unable to create upstream request")
		return
	}
	copyUpstreamHeaders(req.Header, r.Header)
	if auth.Subject != "" {
		req.Header.Set("X-Apim-User-Object-Id", auth.Subject)
		req.Header.Set("X-Apim-User-Email", auth.Email)
		req.Header.Set("X-Apim-User-Name", firstString(auth.PreferredUsername, auth.Email, auth.Subject))
		req.Header.Set("X-Apim-Auth-Method", "oidc")
	}
	if subscription.ID != "" {
		req.Header.Set("X-User-Id", subscription.ID)
		req.Header.Set("X-User-Name", subscription.Name)
		req.Header.Set("X-Apim-Products", strings.Join(subscription.Products, ","))
	}
	resp, err := s.client.Do(req)
	traceID := newTraceID()
	trace := TraceRecord{
		TraceID:        traceID,
		Method:         r.Method,
		Path:           r.URL.RequestURI(),
		RouteName:      route.Name,
		UpstreamURL:    target,
		StartedAt:      started.UTC().Format(time.RFC3339Nano),
		DurationMillis: time.Since(started).Milliseconds(),
		RequestHeaders: selectedHeaders(r.Header),
	}
	if err != nil {
		trace.StatusCode = http.StatusBadGateway
		trace.Error = err.Error()
		s.traces.add(trace)
		w.Header().Set("X-Apim-Trace-Id", traceID)
		apphttp.WriteError(w, http.StatusBadGateway, "Upstream request failed")
		return
	}
	defer resp.Body.Close()
	trace.StatusCode = resp.StatusCode
	trace.ResponseHeaders = selectedHeaders(resp.Header)
	copyResponseHeaders(w.Header(), resp.Header)
	w.Header().Set("X-Apim-Simulator", "apim-simulator-go")
	w.Header().Set("X-Apim-Trace-Id", traceID)
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
	trace.DurationMillis = time.Since(started).Milliseconds()
	s.traces.add(trace)
}

func (s *server) authenticate(w http.ResponseWriter, r *http.Request, route RouteConfig) (idpauth.UserClaims, bool) {
	if s.cfg.AllowAnonymous || route.AllowAnonymous || (s.cfg.OIDC.Issuer == "" && s.verifier == nil) {
		return idpauth.UserClaims{Subject: "anonymous", Groups: []string{}}, true
	}
	return (idpauth.Authenticator{Mode: "oidc", Verifier: s.verifier}).CurrentUserOrWriteError(w, r, idpauth.AuthFailureMessages{
		MissingBearerToken: "Missing bearer token",
		InvalidToken:       "Invalid bearer token",
	})
}

func (s *server) authorizeRoute(w http.ResponseWriter, route RouteConfig, claims idpauth.UserClaims) bool {
	failure := (idpauth.AccessPolicy{
		RequiredGroups: route.Authz.RequiredGroups,
		RequiredRoles:  route.Authz.RequiredRoles,
		RequiredClaims: route.Authz.RequiredClaims,
	}).Evaluate(claims)
	if failure == nil {
		return true
	}
	apphttp.WriteError(w, failure.StatusCode, failure.Message)
	return false
}

func (s *server) authorizeSubscription(w http.ResponseWriter, r *http.Request, route RouteConfig) (Subscription, bool) {
	if !s.subscriptionRequired(route) || subscriptionBypassed(s.cfg.Subscriptions, r) {
		return Subscription{}, true
	}
	key := subscriptionKey(s.cfg.Subscriptions, r)
	if key == "" {
		apphttp.WriteError(w, http.StatusUnauthorized, "Subscription key is required")
		return Subscription{}, false
	}
	sub, ok := lookupSubscription(s.cfg.Subscriptions, key)
	if !ok {
		apphttp.WriteError(w, http.StatusForbidden, "Subscription key is invalid")
		return Subscription{}, false
	}
	if sub.State != "" && !strings.EqualFold(sub.State, "active") {
		apphttp.WriteError(w, http.StatusForbidden, "Subscription is not active")
		return Subscription{}, false
	}
	return sub, true
}

func (s *server) subscriptionRequired(route RouteConfig) bool {
	if s.cfg.Subscriptions.Required {
		return true
	}
	if route.Product != "" {
		product, ok := s.cfg.Products[route.Product]
		return ok && product.RequireSubscription
	}
	return false
}

func (s *server) upstreamURL(route RouteConfig, r *http.Request) (string, error) {
	base, err := url.Parse(route.UpstreamBaseURL)
	if err != nil {
		return "", err
	}
	prefix := "/" + strings.Trim(route.PathPrefix, "/")
	if prefix == "/" {
		prefix = ""
	}
	remainder := strings.TrimPrefix(r.URL.Path, prefix)
	if !strings.HasPrefix(remainder, "/") {
		remainder = "/" + remainder
	}
	upstreamPrefix := "/" + strings.Trim(route.UpstreamPathPrefix, "/")
	if upstreamPrefix == "/" {
		upstreamPrefix = ""
	}
	base.Path = path.Join(base.Path, upstreamPrefix, remainder)
	if strings.HasSuffix(r.URL.Path, "/") && !strings.HasSuffix(base.Path, "/") {
		base.Path += "/"
	}
	base.RawQuery = r.URL.RawQuery
	return base.String(), nil
}

func (s *server) resolveRoute(r *http.Request) (RouteConfig, bool) {
	host := stripPort(firstString(r.Header.Get("X-Forwarded-Host"), r.Host, r.URL.Host))
	for _, route := range s.cfg.Routes {
		if !pathMatches(route.PathPrefix, r.URL.Path) {
			continue
		}
		if len(route.HostMatch) > 0 && !hostMatches(route.HostMatch, host) {
			continue
		}
		return route, true
	}
	return RouteConfig{}, false
}

func (s *server) requireTenantKey(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.cfg.TenantAccess.Enabled {
			next(w, r)
			return
		}
		key := r.Header.Get("X-Apim-Tenant-Key")
		if key == "" {
			key = r.URL.Query().Get("tenant-key")
		}
		if key != "" && (key == s.cfg.TenantAccess.PrimaryKey || key == s.cfg.TenantAccess.SecondaryKey) {
			next(w, r)
			return
		}
		apphttp.WriteError(w, http.StatusUnauthorized, "Tenant key is required")
	}
}

func corsMiddleware(cfg Config, next http.Handler) http.Handler {
	return apphttp.CORS(apphttp.CORSConfig{
		AllowedOrigins:  cfg.AllowedOrigins,
		AllowHeaders:    []string{"Authorization", "Content-Type", "Ocp-Apim-Subscription-Key", "X-Apim-Tenant-Key", "X-Apim-Trace"},
		AllowMethods:    []string{http.MethodGet, http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete, http.MethodOptions},
		ExposeHeaders:   []string{"X-Apim-Simulator", "X-Apim-Trace-Id"},
		PreflightStatus: http.StatusNoContent,
	}, next)
}

func copyUpstreamHeaders(dst, src http.Header) {
	for key, values := range src {
		lower := strings.ToLower(key)
		if hopByHopHeaders[lower] || strings.HasPrefix(lower, "x-apim-user-") || lower == "x-ms-client-principal" {
			continue
		}
		for _, value := range values {
			dst.Add(key, value)
		}
	}
}

func copyResponseHeaders(dst, src http.Header) {
	for key, values := range src {
		if hopByHopHeaders[strings.ToLower(key)] {
			continue
		}
		for _, value := range values {
			dst.Add(key, value)
		}
	}
}

var hopByHopHeaders = map[string]bool{
	"connection": true, "keep-alive": true, "proxy-authenticate": true,
	"proxy-authorization": true, "te": true, "trailer": true,
	"transfer-encoding": true, "upgrade": true, "host": true,
}

func newTraceID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return time.Now().UTC().Format("20060102150405.000000000")
	}
	return hex.EncodeToString(b[:])
}

func selectedHeaders(headers http.Header) map[string]string {
	out := map[string]string{}
	for _, key := range []string{"Host", "Authorization", "X-Apim-Trace", "Ocp-Apim-Subscription-Key", "X-Forwarded-Host"} {
		if value := headers.Get(key); value != "" {
			if strings.EqualFold(key, "Authorization") || strings.Contains(strings.ToLower(key), "subscription") {
				value = "***"
			}
			out[key] = value
		}
	}
	return out
}

func dumpResponse(status int, headers http.Header, body []byte) map[string]any {
	return map[string]any{"status_code": status, "headers": selectedHeaders(headers), "body_text": string(body)}
}

func reverseProxyDirector(target *url.URL) func(*http.Request) {
	return func(req *http.Request) {
		req.URL.Scheme = target.Scheme
		req.URL.Host = target.Host
		req.Host = target.Host
	}
}

var _ = httputil.ReverseProxy{Director: reverseProxyDirector(&url.URL{})}
