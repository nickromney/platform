package apphttp

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strconv"
	"strings"
	"time"

	"platform.local/appconfig"
	"platform.local/apphealth"
)

const defaultJSONBodyLimit int64 = 1 << 20

const DefaultReadHeaderTimeout = 5 * time.Second

const DependencyFootprintGoSharedIDPAuth = apphealth.DependencyFootprintGoSharedIDPAuth

const FrontendDependencyFootprintVanilla = apphealth.FrontendDependencyFootprintVanilla

const DefaultHealthcheckTimeout = apphealth.DefaultHealthcheckTimeout

func BrowserAppHealth(payload map[string]any) map[string]any {
	return apphealth.BrowserAppHealth(payload)
}

func WriteBrowserAppHealth(w http.ResponseWriter, payload map[string]any) {
	WriteJSON(w, http.StatusOK, BrowserAppHealth(payload))
}

func RoleStatus(status string, role string) map[string]string {
	payload := map[string]string{"status": status}
	if strings.TrimSpace(role) != "" {
		payload["role"] = strings.TrimSpace(role)
	}
	return payload
}

func WriteRoleStatus(w http.ResponseWriter, httpStatus int, status string, role string) {
	WriteJSON(w, httpStatus, RoleStatus(status, role))
}

func ErrorPayload(message string) map[string]string {
	return map[string]string{"error": strings.TrimSpace(message)}
}

func WriteError(w http.ResponseWriter, status int, message string) {
	WriteJSON(w, status, ErrorPayload(message))
}

type CORSConfig struct {
	AllowedOrigins   []string
	AllowCredentials bool
	AllowMethods     []string
	AllowHeaders     []string
	ExposeHeaders    []string
	PreflightStatus  int
}

func CORS(config CORSConfig, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if HandleCORS(w, r, config) {
			return
		}
		next.ServeHTTP(w, r)
	})
}

func HandleCORS(w http.ResponseWriter, r *http.Request, config CORSConfig) bool {
	origin := r.Header.Get("Origin")
	if origin != "" && OriginAllowed(config.AllowedOrigins, origin) {
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Vary", "Origin")
		if config.AllowCredentials {
			w.Header().Set("Access-Control-Allow-Credentials", "true")
		}
		if len(config.AllowMethods) > 0 {
			w.Header().Set("Access-Control-Allow-Methods", strings.Join(config.AllowMethods, ", "))
		}
		if len(config.AllowHeaders) > 0 {
			w.Header().Set("Access-Control-Allow-Headers", strings.Join(config.AllowHeaders, ", "))
		}
		if len(config.ExposeHeaders) > 0 {
			w.Header().Set("Access-Control-Expose-Headers", strings.Join(config.ExposeHeaders, ", "))
		}
	}
	if r.Method != http.MethodOptions {
		return false
	}
	status := config.PreflightStatus
	if status == 0 {
		status = http.StatusNoContent
	}
	w.WriteHeader(status)
	return true
}

func OriginAllowed(allowed []string, origin string) bool {
	if origin == "" {
		return false
	}
	for _, item := range allowed {
		if item == "*" || item == origin {
			return true
		}
	}
	return false
}

func RequestLogger(appName string, logger *slog.Logger, next http.Handler) http.Handler {
	if logger == nil {
		logger = slog.Default()
	}
	if strings.TrimSpace(appName) == "" {
		appName = "app"
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		recorder := &statusRecorder{ResponseWriter: w, statusCode: http.StatusOK}
		next.ServeHTTP(recorder, r)
		logger.Info(
			appName+" request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", recorder.statusCode,
			"duration_ms", time.Since(started).Milliseconds(),
		)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	statusCode  int
	wroteHeader bool
}

func (r *statusRecorder) WriteHeader(statusCode int) {
	if r.wroteHeader {
		return
	}
	r.statusCode = statusCode
	r.wroteHeader = true
	r.ResponseWriter.WriteHeader(statusCode)
}

func NewServer(addr string, handler http.Handler) *http.Server {
	return &http.Server{
		Addr:              NormalizeAddr(addr),
		Handler:           handler,
		ReadHeaderTimeout: DefaultReadHeaderTimeout,
	}
}

func ListenAndServe(addr string, handler http.Handler) error {
	return IgnoreServerClosed(NewServer(addr, handler).ListenAndServe())
}

func IgnoreServerClosed(err error) error {
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}

func QueryInt(r *http.Request, key string, fallback int) int {
	if r == nil {
		return fallback
	}
	raw := strings.TrimSpace(r.URL.Query().Get(key))
	if raw == "" {
		return fallback
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value <= 0 {
		return fallback
	}
	return value
}

func Env(key, fallback string) string {
	return appconfig.Env(key, fallback)
}

func EnvURL(key, fallback string) string {
	return appconfig.EnvURL(key, fallback)
}

func NormalizeURL(value string) string {
	return appconfig.NormalizeURL(value)
}

func FirstEnv(keys ...string) string {
	return appconfig.FirstEnv(keys...)
}

func EnvBool(key string, fallback bool) bool {
	return appconfig.EnvBool(key, fallback)
}

func EnvSeconds(key string, fallback time.Duration) time.Duration {
	return appconfig.EnvSeconds(key, fallback)
}

func EnvInt(key string, fallback int) int {
	return appconfig.EnvInt(key, fallback)
}

func NormalizeAddr(addr string) string {
	return appconfig.NormalizeAddr(addr)
}

func StringDefault(value, fallback string) string {
	return appconfig.StringDefault(value, fallback)
}

func FirstNonEmpty(values ...string) string {
	return appconfig.FirstNonEmpty(values...)
}

func CheckHealthURL(rawURL string, timeout time.Duration) bool {
	return apphealth.CheckHealthURL(rawURL, timeout)
}

func LocalHealthURL(port string, path string) string {
	return apphealth.LocalHealthURL(port, path)
}

func CheckLocalHealth(port string, path string) bool {
	return apphealth.CheckLocalHealth(port, path)
}

func HealthcheckCommand(args []string) bool {
	return apphealth.HealthcheckCommand(args)
}

func NewHTTPClient(timeout time.Duration) *http.Client {
	if timeout <= 0 {
		timeout = 1 * time.Second
	}
	return &http.Client{Timeout: timeout}
}

func WriteJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		slog.Error("write json response", "error", err)
	}
}

func WriteNoCacheJSON(w http.ResponseWriter, status int, value any) {
	NoCacheJSONHeaders(w)
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		slog.Error("write no-cache json response", "error", err)
	}
}

func WritePrometheusMetrics(w http.ResponseWriter, body string) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(body))
}

func MethodNotAllowed(w http.ResponseWriter, allowedMethods ...string) {
	w.Header().Set("Allow", strings.Join(allowedMethods, ", "))
	w.WriteHeader(http.StatusMethodNotAllowed)
}

func NoCacheHeaders(w http.ResponseWriter) {
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate, max-age=0")
	w.Header().Set("Pragma", "no-cache")
	w.Header().Set("Expires", "0")
	w.Header().Set("X-Content-Type-Options", "nosniff")
}

func NoCacheJSONHeaders(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	NoCacheHeaders(w)
}

func DecodeJSON(w http.ResponseWriter, r *http.Request, out any, errorPayload any) bool {
	return DecodeJSONLimit(w, r, out, errorPayload, defaultJSONBodyLimit)
}

func DecodeJSONError(w http.ResponseWriter, r *http.Request, out any, errorMessage string) bool {
	return DecodeJSON(w, r, out, ErrorPayload(errorMessage))
}

func ReadRequestBody(r *http.Request) ([]byte, error) {
	return ReadRequestBodyLimit(r, defaultJSONBodyLimit)
}

func ReadRequestBodyLimit(r *http.Request, limit int64) ([]byte, error) {
	defer r.Body.Close()
	if limit <= 0 {
		limit = defaultJSONBodyLimit
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(body)) > limit {
		return nil, errors.New("request body exceeds limit")
	}
	return body, nil
}

func DecodeJSONReader(reader io.Reader, out any) error {
	return DecodeJSONReaderLimit(reader, out, defaultJSONBodyLimit)
}

func DecodeJSONReaderLimit(reader io.Reader, out any, limit int64) error {
	if limit <= 0 {
		limit = defaultJSONBodyLimit
	}
	body, err := io.ReadAll(io.LimitReader(reader, limit+1))
	if err != nil {
		return err
	}
	if int64(len(body)) > limit {
		return errors.New("json body exceeds limit")
	}
	decoder := json.NewDecoder(bytes.NewReader(body))
	if err := decoder.Decode(out); err != nil {
		return err
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return errors.New("json body contains trailing data")
	}
	return nil
}

func DecodeJSONLimit(w http.ResponseWriter, r *http.Request, out any, errorPayload any, limit int64) bool {
	defer r.Body.Close()
	if limit <= 0 {
		limit = defaultJSONBodyLimit
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, limit+1))
	if err != nil || int64(len(body)) > limit {
		WriteJSON(w, http.StatusBadRequest, errorPayload)
		return false
	}
	if err := decodeJSONBytes(body, out); err != nil {
		WriteJSON(w, http.StatusBadRequest, errorPayload)
		return false
	}
	return true
}

func decodeJSONBytes(body []byte, out any) error {
	decoder := json.NewDecoder(bytes.NewReader(body))
	if err := decoder.Decode(out); err != nil {
		return err
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return errors.New("json body contains trailing data")
	}
	return nil
}

type APIProxyConfig struct {
	BackendURL   string
	ErrorPayload func(message string) any
}

func NewAPIProxy(cfg APIProxyConfig) http.Handler {
	errorPayload := cfg.ErrorPayload
	if errorPayload == nil {
		errorPayload = func(message string) any { return ErrorPayload(message) }
	}
	writeBadGateway := func(w http.ResponseWriter, message string) {
		WriteJSON(w, http.StatusBadGateway, errorPayload(message))
	}
	if strings.TrimSpace(cfg.BackendURL) == "" {
		return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			writeBadGateway(w, "BACKEND_URL is not configured")
		})
	}
	target, err := url.Parse(cfg.BackendURL)
	if err != nil {
		return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			writeBadGateway(w, "BACKEND_URL is invalid")
		})
	}
	proxy := httputil.NewSingleHostReverseProxy(target)
	baseDirector := proxy.Director
	proxy.Director = func(r *http.Request) {
		baseDirector(r)
		if auth := proxyAuthorization(r.Header); auth != "" {
			r.Header.Set("Authorization", auth)
		}
	}
	proxy.ErrorHandler = func(w http.ResponseWriter, _ *http.Request, _ error) {
		writeBadGateway(w, "Backend API unavailable")
	}
	return proxy
}

func proxyAuthorization(headers http.Header) string {
	for _, name := range []string{"X-Auth-Request-Access-Token", "X-Forwarded-Access-Token"} {
		if token := strings.TrimSpace(headers.Get(name)); token != "" {
			return "Bearer " + token
		}
	}
	return strings.TrimSpace(headers.Get("Authorization"))
}
