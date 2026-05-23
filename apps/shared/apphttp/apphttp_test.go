package apphttp

import (
	"bytes"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestWriteJSONSetsContentTypeStatusAndBody(t *testing.T) {
	rec := httptest.NewRecorder()

	WriteJSON(rec, http.StatusCreated, map[string]string{"status": "ok"})

	if rec.Code != http.StatusCreated {
		t.Fatalf("status=%d", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); got != "application/json" {
		t.Fatalf("Content-Type=%q", got)
	}
	if got := rec.Header().Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("X-Content-Type-Options=%q", got)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"status":"ok"}` {
		t.Fatalf("body=%q", got)
	}
}

func TestDependencyFootprintConstantsDocumentSharedBrowserAppRuntime(t *testing.T) {
	if DependencyFootprintGoSharedIDPAuth != "go-plus-shared-idpauth" {
		t.Fatalf("DependencyFootprintGoSharedIDPAuth=%q", DependencyFootprintGoSharedIDPAuth)
	}
	if FrontendDependencyFootprintVanilla != "vanilla" {
		t.Fatalf("FrontendDependencyFootprintVanilla=%q", FrontendDependencyFootprintVanilla)
	}
}

func TestBrowserAppHealthAddsCanonicalDependencyFootprints(t *testing.T) {
	base := map[string]any{
		"status":               "ok",
		"dependency_footprint": "legacy",
	}

	health := BrowserAppHealth(base)

	if health["status"] != "ok" {
		t.Fatalf("status=%v", health["status"])
	}
	if health["dependency_footprint"] != DependencyFootprintGoSharedIDPAuth {
		t.Fatalf("dependency_footprint=%v", health["dependency_footprint"])
	}
	if health["frontend_dependency_footprint"] != FrontendDependencyFootprintVanilla {
		t.Fatalf("frontend_dependency_footprint=%v", health["frontend_dependency_footprint"])
	}
	if health["transitive_javascript_packages"] != 0 {
		t.Fatalf("transitive_javascript_packages=%v", health["transitive_javascript_packages"])
	}
	if health["transitive_python_packages"] != 0 {
		t.Fatalf("transitive_python_packages=%v", health["transitive_python_packages"])
	}
	if base["dependency_footprint"] != "legacy" {
		t.Fatalf("BrowserAppHealth mutated input map: %v", base)
	}
}

func TestWriteBrowserAppHealthWritesCanonicalPayload(t *testing.T) {
	rec := httptest.NewRecorder()

	WriteBrowserAppHealth(rec, map[string]any{"status": "ok"})

	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); got != "application/json" {
		t.Fatalf("Content-Type=%q", got)
	}
	body := rec.Body.String()
	for _, text := range []string{
		`"status":"ok"`,
		`"dependency_footprint":"go-plus-shared-idpauth"`,
		`"frontend_dependency_footprint":"vanilla"`,
		`"transitive_javascript_packages":0`,
		`"transitive_python_packages":0`,
	} {
		if !strings.Contains(body, text) {
			t.Fatalf("browser health body missing %q: %s", text, body)
		}
	}
}

func TestWriteRoleStatusWritesCanonicalStatusPayload(t *testing.T) {
	rec := httptest.NewRecorder()

	WriteRoleStatus(rec, http.StatusOK, "ready", "backend")

	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); got != "application/json" {
		t.Fatalf("Content-Type=%q", got)
	}
	body := rec.Body.String()
	for _, text := range []string{`"status":"ready"`, `"role":"backend"`} {
		if !strings.Contains(body, text) {
			t.Fatalf("body missing %q: %s", text, body)
		}
	}
}

func TestWriteRoleStatusOmitsBlankRole(t *testing.T) {
	rec := httptest.NewRecorder()

	WriteRoleStatus(rec, http.StatusOK, "alive", "")

	if got := strings.TrimSpace(rec.Body.String()); got != `{"status":"alive"}` {
		t.Fatalf("body=%q", got)
	}
}

func TestWriteErrorWritesCanonicalErrorPayload(t *testing.T) {
	rec := httptest.NewRecorder()

	WriteError(rec, http.StatusBadRequest, "missing value")

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status=%d", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); got != "application/json" {
		t.Fatalf("Content-Type=%q", got)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"missing value"}` {
		t.Fatalf("body=%q", got)
	}
}

func TestErrorPayloadIsCanonicalAndTrimmed(t *testing.T) {
	payload := ErrorPayload(" missing value ")

	if got := payload["error"]; got != "missing value" {
		t.Fatalf("error=%q", got)
	}
}

func TestStringDefaultUsesFallbackOnlyForEmptyStrings(t *testing.T) {
	if got := StringDefault("", "/api/v1"); got != "/api/v1" {
		t.Fatalf("empty string default=%q", got)
	}
	if got := StringDefault("  ", "/api/v1"); got != "  " {
		t.Fatalf("whitespace string default=%q", got)
	}
	if got := StringDefault("/custom", "/api/v1"); got != "/custom" {
		t.Fatalf("custom string default=%q", got)
	}
}

func TestFirstNonEmptyReturnsFirstTrimmedNonBlankValue(t *testing.T) {
	if got := FirstNonEmpty("", "  ", " first ", "second"); got != "first" {
		t.Fatalf("FirstNonEmpty=%q", got)
	}
	if got := FirstNonEmpty("", "\t"); got != "" {
		t.Fatalf("FirstNonEmpty blank values=%q", got)
	}
}

func TestHandleCORSWritesAllowedOriginHeadersAndHandlesPreflight(t *testing.T) {
	req := httptest.NewRequest(http.MethodOptions, "/api", nil)
	req.Header.Set("Origin", "https://portal.example.test")
	rec := httptest.NewRecorder()

	handled := HandleCORS(rec, req, CORSConfig{
		AllowedOrigins:   []string{"https://portal.example.test"},
		AllowCredentials: true,
		AllowMethods:     []string{http.MethodGet, http.MethodPost},
		AllowHeaders:     []string{"Authorization", "Content-Type"},
		ExposeHeaders:    []string{"X-Trace-Id"},
		PreflightStatus:  http.StatusNoContent,
	})

	if !handled {
		t.Fatal("expected preflight request to be handled")
	}
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status=%d", rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "https://portal.example.test" {
		t.Fatalf("Access-Control-Allow-Origin=%q", got)
	}
	if got := rec.Header().Get("Vary"); got != "Origin" {
		t.Fatalf("Vary=%q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Credentials"); got != "true" {
		t.Fatalf("Access-Control-Allow-Credentials=%q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Methods"); got != "GET, POST" {
		t.Fatalf("Access-Control-Allow-Methods=%q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Headers"); got != "Authorization, Content-Type" {
		t.Fatalf("Access-Control-Allow-Headers=%q", got)
	}
	if got := rec.Header().Get("Access-Control-Expose-Headers"); got != "X-Trace-Id" {
		t.Fatalf("Access-Control-Expose-Headers=%q", got)
	}
}

func TestHandleCORSLeavesDisallowedOriginUnreflected(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api", nil)
	req.Header.Set("Origin", "https://evil.example.test")
	rec := httptest.NewRecorder()

	handled := HandleCORS(rec, req, CORSConfig{
		AllowedOrigins: []string{"https://portal.example.test"},
		AllowMethods:   []string{http.MethodGet},
	})

	if handled {
		t.Fatal("non-OPTIONS request should continue to the app handler")
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("Access-Control-Allow-Origin=%q", got)
	}
}

func TestCORSMiddlewareHandlesPreflightAndDelegatesNormalRequests(t *testing.T) {
	nextCalled := false
	handler := CORS(CORSConfig{
		AllowedOrigins:  []string{"*"},
		AllowMethods:    []string{http.MethodGet},
		PreflightStatus: http.StatusOK,
	}, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		nextCalled = true
		WriteJSON(w, http.StatusAccepted, map[string]string{"status": "ok"})
	}))

	preflight := httptest.NewRequest(http.MethodOptions, "/api", nil)
	preflight.Header.Set("Origin", "https://any.example.test")
	preflightRec := httptest.NewRecorder()
	handler.ServeHTTP(preflightRec, preflight)

	if preflightRec.Code != http.StatusOK {
		t.Fatalf("preflight status=%d", preflightRec.Code)
	}
	if nextCalled {
		t.Fatal("preflight should not call next handler")
	}
	if got := preflightRec.Header().Get("Access-Control-Allow-Origin"); got != "https://any.example.test" {
		t.Fatalf("preflight Access-Control-Allow-Origin=%q", got)
	}

	req := httptest.NewRequest(http.MethodGet, "/api", nil)
	req.Header.Set("Origin", "https://any.example.test")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if !nextCalled {
		t.Fatal("normal request did not call next handler")
	}
	if rec.Code != http.StatusAccepted {
		t.Fatalf("normal request status=%d", rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "https://any.example.test" {
		t.Fatalf("normal request Access-Control-Allow-Origin=%q", got)
	}
}

func TestMethodNotAllowedSetsAllowHeader(t *testing.T) {
	rec := httptest.NewRecorder()

	MethodNotAllowed(rec, http.MethodGet, http.MethodHead)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status=%d", rec.Code)
	}
	if got := rec.Header().Get("Allow"); got != "GET, HEAD" {
		t.Fatalf("Allow=%q", got)
	}
	if rec.Body.Len() != 0 {
		t.Fatalf("body=%q", rec.Body.String())
	}
}

func TestNoCacheHeadersAppliesSharedBrowserPolicy(t *testing.T) {
	rec := httptest.NewRecorder()

	NoCacheHeaders(rec)

	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("Cache-Control=%q", got)
	}
	if got := rec.Header().Get("Pragma"); got != "no-cache" {
		t.Fatalf("Pragma=%q", got)
	}
	if got := rec.Header().Get("Expires"); got != "0" {
		t.Fatalf("Expires=%q", got)
	}
	if got := rec.Header().Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("X-Content-Type-Options=%q", got)
	}
}

func TestNoCacheJSONHeadersAppliesContentTypeAndCachePolicy(t *testing.T) {
	rec := httptest.NewRecorder()

	NoCacheJSONHeaders(rec)

	if got := rec.Header().Get("Content-Type"); got != "application/json" {
		t.Fatalf("Content-Type=%q", got)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("Cache-Control=%q", got)
	}
	if got := rec.Header().Get("Pragma"); got != "no-cache" {
		t.Fatalf("Pragma=%q", got)
	}
	if got := rec.Header().Get("Expires"); got != "0" {
		t.Fatalf("Expires=%q", got)
	}
	if got := rec.Header().Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("X-Content-Type-Options=%q", got)
	}
}

func TestWriteNoCacheJSONSetsJSONBodyAndBrowserPolicy(t *testing.T) {
	rec := httptest.NewRecorder()

	WriteNoCacheJSON(rec, http.StatusOK, map[string]string{"status": "ok"})

	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); got != "application/json" {
		t.Fatalf("Content-Type=%q", got)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("Cache-Control=%q", got)
	}
	if got := rec.Header().Get("Pragma"); got != "no-cache" {
		t.Fatalf("Pragma=%q", got)
	}
	if got := rec.Header().Get("Expires"); got != "0" {
		t.Fatalf("Expires=%q", got)
	}
	if got := rec.Header().Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("X-Content-Type-Options=%q", got)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"status":"ok"}` {
		t.Fatalf("body=%q", got)
	}
}

func TestWritePrometheusMetricsSetsTextFormatAndNosniff(t *testing.T) {
	rec := httptest.NewRecorder()

	WritePrometheusMetrics(rec, "# HELP demo_total Demo counter.\n")

	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); got != "text/plain; version=0.0.4; charset=utf-8" {
		t.Fatalf("Content-Type=%q", got)
	}
	if got := rec.Header().Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("X-Content-Type-Options=%q", got)
	}
	if got := rec.Body.String(); got != "# HELP demo_total Demo counter.\n" {
		t.Fatalf("body=%q", got)
	}
}

func TestNewServerAppliesSharedRuntimeDefaults(t *testing.T) {
	handler := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	server := NewServer("8080", handler)

	if server.Addr != ":8080" {
		t.Fatalf("Addr=%q", server.Addr)
	}
	if server.Handler == nil {
		t.Fatal("Handler is nil")
	}
	if server.ReadHeaderTimeout != DefaultReadHeaderTimeout {
		t.Fatalf("ReadHeaderTimeout=%s", server.ReadHeaderTimeout)
	}
}

func TestNewServerPreservesExplicitAddress(t *testing.T) {
	server := NewServer(":9000", http.NotFoundHandler())

	if server.Addr != ":9000" {
		t.Fatalf("Addr=%q", server.Addr)
	}
}

func TestRequestLoggerRecordsMethodPathStatusAndDuration(t *testing.T) {
	var logs bytes.Buffer
	logger := slog.New(slog.NewTextHandler(&logs, &slog.HandlerOptions{ReplaceAttr: func(_ []string, attr slog.Attr) slog.Attr {
		if attr.Key == slog.TimeKey {
			return slog.Attr{}
		}
		return attr
	}}))
	handler := RequestLogger("demo", logger, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		WriteJSON(w, http.StatusAccepted, map[string]string{"status": "accepted"})
	}))

	req := httptest.NewRequest(http.MethodPost, "/demo?secret=1", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusAccepted {
		t.Fatalf("status=%d", rec.Code)
	}
	body := logs.String()
	for _, text := range []string{
		`msg="demo request"`,
		`method=POST`,
		`path=/demo`,
		`status=202`,
		`duration_ms=`,
	} {
		if !strings.Contains(body, text) {
			t.Fatalf("log missing %q: %s", text, body)
		}
	}
	if strings.Contains(body, "secret=1") {
		t.Fatalf("request log should not include query strings: %s", body)
	}
}

func TestRequestLoggerRecordsFirstWrittenStatus(t *testing.T) {
	var logs bytes.Buffer
	logger := slog.New(slog.NewTextHandler(&logs, &slog.HandlerOptions{ReplaceAttr: func(_ []string, attr slog.Attr) slog.Attr {
		if attr.Key == slog.TimeKey {
			return slog.Attr{}
		}
		return attr
	}}))
	handler := RequestLogger("demo", logger, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusCreated)
		w.WriteHeader(http.StatusInternalServerError)
	}))

	req := httptest.NewRequest(http.MethodPost, "/demo", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("response status=%d", rec.Code)
	}
	body := logs.String()
	if !strings.Contains(body, `status=201`) {
		t.Fatalf("log should record first written status: %s", body)
	}
	if strings.Contains(body, `status=500`) {
		t.Fatalf("log should not record later ignored status: %s", body)
	}
}

func TestIgnoreServerClosed(t *testing.T) {
	if err := IgnoreServerClosed(http.ErrServerClosed); err != nil {
		t.Fatalf("IgnoreServerClosed(http.ErrServerClosed)=%v", err)
	}

	boom := errors.New("boom")
	if err := IgnoreServerClosed(boom); !errors.Is(err, boom) {
		t.Fatalf("IgnoreServerClosed(boom)=%v, want boom", err)
	}
}

func TestCheckLocalHealthAcceptsOnlySuccessfulResponses(t *testing.T) {
	if DefaultHealthcheckTimeout > time.Second {
		t.Fatalf("DefaultHealthcheckTimeout=%s, want at most 1s", DefaultHealthcheckTimeout)
	}

	ok := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		WriteJSON(w, http.StatusNoContent, map[string]string{"status": "ok"})
	}))
	t.Cleanup(ok.Close)
	failing := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		WriteJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "down"})
	}))
	t.Cleanup(failing.Close)

	if !CheckHealthURL(ok.URL, time.Second) {
		t.Fatal("expected successful health URL to pass")
	}
	if CheckHealthURL(failing.URL, time.Second) {
		t.Fatal("expected failing health URL to fail")
	}
	if CheckHealthURL("http://127.0.0.1:1/not-listening", 10*time.Millisecond) {
		t.Fatal("expected unreachable health URL to fail")
	}
}

func TestLocalHealthURLNormalizesPortAndPath(t *testing.T) {
	if got := LocalHealthURL(":8080", "health"); got != "http://127.0.0.1:8080/health" {
		t.Fatalf("LocalHealthURL=%q", got)
	}
	if got := LocalHealthURL("9090", "/api/v1/health"); got != "http://127.0.0.1:9090/api/v1/health" {
		t.Fatalf("LocalHealthURL=%q", got)
	}
}

func TestHealthcheckCommandRecognizesOnlyStandardSubcommand(t *testing.T) {
	if !HealthcheckCommand([]string{"app", "healthcheck"}) {
		t.Fatal("expected healthcheck subcommand to be recognized")
	}
	for _, args := range [][]string{
		nil,
		{"app"},
		{"app", "serve"},
		{"app", "healthcheck", "extra"},
	} {
		if HealthcheckCommand(args) {
			t.Fatalf("HealthcheckCommand(%v)=true, want false", args)
		}
	}
}

func TestEnvReturnsFallbackForUnsetAndEmptyValues(t *testing.T) {
	const key = "APPHTTP_TEST_EMPTY_ENV"
	t.Setenv(key, "")

	if got := Env(key, "fallback"); got != "fallback" {
		t.Fatalf("Env empty=%q", got)
	}
	if got := Env("APPHTTP_TEST_MISSING_ENV", "fallback"); got != "fallback" {
		t.Fatalf("Env missing=%q", got)
	}
	t.Setenv(key, "   ")
	if got := Env(key, "fallback"); got != "fallback" {
		t.Fatalf("Env blank=%q", got)
	}
}

func TestEnvReturnsConfiguredValue(t *testing.T) {
	const key = "APPHTTP_TEST_CONFIGURED_ENV"
	t.Setenv(key, " configured ")

	if got := Env(key, "fallback"); got != "configured" {
		t.Fatalf("Env configured=%q", got)
	}
}

func TestEnvURLReturnsConfiguredValueWithoutTrailingSlashes(t *testing.T) {
	const key = "APPHTTP_TEST_URL_ENV"
	t.Setenv(key, " https://api.example.test/v1/// ")

	if got := EnvURL(key, "http://fallback.example.test/"); got != "https://api.example.test/v1" {
		t.Fatalf("EnvURL configured=%q", got)
	}
}

func TestNormalizeURLTrimsTrailingSlashesAndPreservesRootSlash(t *testing.T) {
	for _, tc := range []struct {
		name  string
		value string
		want  string
	}{
		{name: "base URL", value: " https://api.example.test/v1/// ", want: "https://api.example.test/v1"},
		{name: "root slash", value: "/", want: "/"},
		{name: "empty", value: " ", want: ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := NormalizeURL(tc.value); got != tc.want {
				t.Fatalf("NormalizeURL(%q)=%q, want %q", tc.value, got, tc.want)
			}
		})
	}
}

func TestEnvURLNormalizesFallbackAndKeepsRootURLSlash(t *testing.T) {
	const key = "APPHTTP_TEST_URL_FALLBACK_ENV"
	t.Setenv(key, "")

	if got := EnvURL(key, "http://fallback.example.test/"); got != "http://fallback.example.test" {
		t.Fatalf("EnvURL fallback=%q", got)
	}
	t.Setenv(key, "https://api.example.test/")
	if got := EnvURL(key, "http://fallback.example.test/"); got != "https://api.example.test" {
		t.Fatalf("EnvURL root=%q", got)
	}
	t.Setenv(key, "/")
	if got := EnvURL(key, "/"); got != "/" {
		t.Fatalf("EnvURL slash=%q", got)
	}
	if got := EnvURL("APPHTTP_TEST_EMPTY_URL_FALLBACK_ENV", ""); got != "" {
		t.Fatalf("EnvURL empty fallback=%q", got)
	}
}

func TestFirstEnvReturnsFirstConfiguredValue(t *testing.T) {
	const (
		first  = "APPHTTP_TEST_FIRST_ENV"
		second = "APPHTTP_TEST_SECOND_ENV"
	)
	t.Setenv(first, " ")
	t.Setenv(second, " configured ")

	if got := FirstEnv(first, second); got != "configured" {
		t.Fatalf("FirstEnv=%q", got)
	}
}

func TestEnvBoolParsesCommonBooleanValues(t *testing.T) {
	const key = "APPHTTP_TEST_BOOL_ENV"

	for _, value := range []string{"1", "true", "TRUE", " yes ", "on"} {
		t.Setenv(key, value)
		if !EnvBool(key, false) {
			t.Fatalf("EnvBool(%q)=false, want true", value)
		}
	}
	for _, value := range []string{"0", "false", "FALSE", " no ", "off"} {
		t.Setenv(key, value)
		if EnvBool(key, true) {
			t.Fatalf("EnvBool(%q)=true, want false", value)
		}
	}

	t.Setenv(key, "")
	if !EnvBool(key, true) {
		t.Fatal("EnvBool empty should return fallback")
	}
	t.Setenv(key, "sometimes")
	if EnvBool(key, false) {
		t.Fatal("EnvBool invalid should return fallback")
	}
}

func TestEnvSecondsParsesPositiveDurations(t *testing.T) {
	const key = "APPHTTP_TEST_SECONDS_ENV"
	t.Setenv(key, "1.5")

	if got := EnvSeconds(key, time.Second); got != 1500*time.Millisecond {
		t.Fatalf("EnvSeconds=%s", got)
	}
}

func TestEnvSecondsReturnsFallbackForUnsetInvalidAndNonPositiveValues(t *testing.T) {
	const key = "APPHTTP_TEST_SECONDS_FALLBACK_ENV"
	fallback := 250 * time.Millisecond

	for _, value := range []string{"", " ", "soon", "0", "-1"} {
		t.Setenv(key, value)
		if got := EnvSeconds(key, fallback); got != fallback {
			t.Fatalf("EnvSeconds(%q)=%s, want %s", value, got, fallback)
		}
	}
}

func TestEnvIntParsesPositiveIntegers(t *testing.T) {
	const key = "APPHTTP_TEST_INT_ENV"
	t.Setenv(key, " 42 ")

	if got := EnvInt(key, 7); got != 42 {
		t.Fatalf("EnvInt=%d", got)
	}
}

func TestEnvIntReturnsFallbackForUnsetInvalidAndNonPositiveValues(t *testing.T) {
	const key = "APPHTTP_TEST_INT_FALLBACK_ENV"

	for _, value := range []string{"", " ", "many", "0", "-1"} {
		t.Setenv(key, value)
		if got := EnvInt(key, 7); got != 7 {
			t.Fatalf("EnvInt(%q)=%d, want 7", value, got)
		}
	}
}

func TestQueryIntParsesPositiveIntegers(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/comments?limit=%2042%20", nil)

	if got := QueryInt(req, "limit", 25); got != 42 {
		t.Fatalf("QueryInt=%d, want 42", got)
	}
}

func TestQueryIntReturnsFallbackForMissingInvalidAndNonPositiveValues(t *testing.T) {
	for _, target := range []string{
		"/comments",
		"/comments?limit=",
		"/comments?limit=many",
		"/comments?limit=0",
		"/comments?limit=-1",
	} {
		req := httptest.NewRequest(http.MethodGet, target, nil)
		if got := QueryInt(req, "limit", 25); got != 25 {
			t.Fatalf("QueryInt(%q)=%d, want 25", target, got)
		}
	}
}

func TestNewHTTPClientUsesRequestedTimeout(t *testing.T) {
	client := NewHTTPClient(1500 * time.Millisecond)

	if client.Timeout != 1500*time.Millisecond {
		t.Fatalf("Timeout=%s, want 1.5s", client.Timeout)
	}
}

func TestNewHTTPClientUsesDefaultTimeoutForNonPositiveValues(t *testing.T) {
	for _, timeout := range []time.Duration{0, -1 * time.Second} {
		client := NewHTTPClient(timeout)
		if client.Timeout != DefaultHealthcheckTimeout {
			t.Fatalf("Timeout=%s, want default %s", client.Timeout, DefaultHealthcheckTimeout)
		}
	}
}

func TestDecodeJSONDecodesBoundedRequestBody(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/api", strings.NewReader(`{"name":"demo"}`))
	rec := httptest.NewRecorder()
	var payload struct {
		Name string `json:"name"`
	}

	if !DecodeJSON(rec, req, &payload, map[string]string{"error": "invalid JSON body"}) {
		t.Fatalf("expected decode to succeed: %s", rec.Body.String())
	}
	if payload.Name != "demo" {
		t.Fatalf("payload=%#v", payload)
	}
	if rec.Body.Len() != 0 {
		t.Fatalf("success should not write a response: %s", rec.Body.String())
	}
}

func TestDecodeJSONWritesCallerErrorPayload(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/api", strings.NewReader(`{`))
	rec := httptest.NewRecorder()
	var payload struct{}

	if DecodeJSON(rec, req, &payload, map[string]string{"error": "bad request"}) {
		t.Fatalf("expected decode to fail")
	}
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status=%d", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); got != "application/json" {
		t.Fatalf("Content-Type=%q", got)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"bad request"}` {
		t.Fatalf("body=%q", got)
	}
}

func TestDecodeJSONErrorWritesCanonicalErrorPayload(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/api", strings.NewReader(`{`))
	rec := httptest.NewRecorder()
	var payload struct{}

	if DecodeJSONError(rec, req, &payload, " invalid JSON body ") {
		t.Fatalf("expected decode to fail")
	}
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status=%d", rec.Code)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"invalid JSON body"}` {
		t.Fatalf("body=%q", got)
	}
}

func TestDecodeJSONRejectsTrailingData(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/api", strings.NewReader(`{"name":"demo"} {"name":"extra"}`))
	rec := httptest.NewRecorder()
	var payload struct {
		Name string `json:"name"`
	}

	if DecodeJSON(rec, req, &payload, map[string]string{"error": "bad request"}) {
		t.Fatalf("expected decode to reject trailing data")
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"bad request"}` {
		t.Fatalf("body=%q", got)
	}
}

func TestDecodeJSONReaderAppliesLimitAndRejectsTrailingData(t *testing.T) {
	var payload struct {
		Name string `json:"name"`
	}
	if err := DecodeJSONReader(strings.NewReader(`{"name":"demo"}`), &payload); err != nil {
		t.Fatalf("DecodeJSONReader returned error: %v", err)
	}
	if payload.Name != "demo" {
		t.Fatalf("payload=%#v", payload)
	}

	for name, body := range map[string]string{
		"invalid":  `{`,
		"trailing": `{"name":"demo"} {"name":"extra"}`,
		"tooLarge": `{"name":"` + strings.Repeat("x", int(defaultJSONBodyLimit)+1) + `"}`,
	} {
		var invalid struct{}
		if err := DecodeJSONReader(strings.NewReader(body), &invalid); err == nil {
			t.Fatalf("%s DecodeJSONReader error=nil, want failure", name)
		}
	}
}

func TestDecodeJSONLimitRejectsOversizedBody(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/api", strings.NewReader(`{"name":"demo"}`))
	rec := httptest.NewRecorder()
	var payload struct{}

	if DecodeJSONLimit(rec, req, &payload, map[string]string{"error": "too large"}, 4) {
		t.Fatalf("expected decode to fail")
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"too large"}` {
		t.Fatalf("body=%q", got)
	}
}

func TestDecodeJSONLimitRejectsValidJSONWithOversizedTrailingWhitespace(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/api", strings.NewReader(`{}`+strings.Repeat(" ", 8)))
	rec := httptest.NewRecorder()
	var payload struct{}

	if DecodeJSONLimit(rec, req, &payload, map[string]string{"error": "too large"}, 4) {
		t.Fatalf("expected decode to fail")
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"too large"}` {
		t.Fatalf("body=%q", got)
	}
}

func TestReadRequestBodyLimitReturnsBodyAndRejectsOversizedInput(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/api", strings.NewReader("hello"))

	body, err := ReadRequestBodyLimit(req, 8)
	if err != nil {
		t.Fatalf("ReadRequestBodyLimit returned error: %v", err)
	}
	if string(body) != "hello" {
		t.Fatalf("body=%q", body)
	}

	req = httptest.NewRequest(http.MethodPost, "/api", strings.NewReader("too large"))
	if _, err := ReadRequestBodyLimit(req, 4); err == nil {
		t.Fatalf("oversized ReadRequestBodyLimit error=nil, want failure")
	}
}

func TestNewAPIProxyPrefersForwardedAccessToken(t *testing.T) {
	var gotAuth string
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	}))
	t.Cleanup(backend.Close)

	proxy := NewAPIProxy(APIProxyConfig{
		BackendURL: backend.URL,
		ErrorPayload: func(message string) any {
			return map[string]string{"error": message}
		},
	})
	req := httptest.NewRequest(http.MethodGet, "/api/v1/demo", nil)
	req.Header.Set("Authorization", "Bearer id-token")
	req.Header.Set("X-Auth-Request-Access-Token", "access-token")
	rec := httptest.NewRecorder()

	proxy.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("proxy returned %d: %s", rec.Code, rec.Body.String())
	}
	if gotAuth != "Bearer access-token" {
		t.Fatalf("Authorization=%q, want forwarded access token", gotAuth)
	}
}

func TestNewAPIProxyFallsBackToAuthorizationHeader(t *testing.T) {
	var gotAuth string
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	}))
	t.Cleanup(backend.Close)

	proxy := NewAPIProxy(APIProxyConfig{
		BackendURL: backend.URL,
		ErrorPayload: func(message string) any {
			return map[string]string{"error": message}
		},
	})
	req := httptest.NewRequest(http.MethodGet, "/api/v1/demo", nil)
	req.Header.Set("Authorization", "Bearer existing-token")
	rec := httptest.NewRecorder()

	proxy.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("proxy returned %d: %s", rec.Code, rec.Body.String())
	}
	if gotAuth != "Bearer existing-token" {
		t.Fatalf("Authorization=%q, want original authorization header", gotAuth)
	}
}

func TestNewAPIProxyWritesCallerErrorPayloadWhenBackendURLMissing(t *testing.T) {
	proxy := NewAPIProxy(APIProxyConfig{
		ErrorPayload: func(message string) any {
			return map[string]string{"detail": message}
		},
	})
	req := httptest.NewRequest(http.MethodGet, "/api/v1/demo", nil)
	rec := httptest.NewRecorder()

	proxy.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status=%d", rec.Code)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"detail":"BACKEND_URL is not configured"}` {
		t.Fatalf("body=%q", got)
	}
}
