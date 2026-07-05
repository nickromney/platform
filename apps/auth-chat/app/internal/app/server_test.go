package app

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"platform.local/idpauth"
)

type staticVerifier struct {
	claims idpauth.UserClaims
	err    error
}

func (v staticVerifier) Verify(context.Context, string) (idpauth.UserClaims, error) {
	if v.err != nil {
		return idpauth.UserClaims{}, v.err
	}
	return v.claims, nil
}

func TestHealthReportsSharedDependencyFootprint(t *testing.T) {
	rec := httptest.NewRecorder()
	NewServer(testConfig(), nil, nil).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("health returned %d: %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if got := body["dependency_footprint"]; got != "go-plus-shared-idpauth" {
		t.Fatalf("dependency_footprint=%v", got)
	}
}

func TestStaticShellContainsAuthAndChatContracts(t *testing.T) {
	rec := httptest.NewRecorder()
	NewServer(testConfig(), nil, nil).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("index returned %d: %s", rec.Code, rec.Body.String())
	}
	for _, want := range []string{`<title>Auth Chat</title>`, `/auth`, `/chat`, `/idpauth.js`, `/app-shell.js`, `/style.css`, `/app.js`, `Qwen3.5-9B-MLX-4bit`} {
		if !strings.Contains(rec.Body.String(), want) {
			t.Fatalf("index missing %q", want)
		}
	}
}

func TestAuthUsesGatewayHeaders(t *testing.T) {
	cfg := testConfig()
	cfg.APIAuthMode = "gateway"
	req := httptest.NewRequest(http.MethodGet, "/auth", nil)
	req.Header.Set("X-Auth-Request-Email", "demo@dev.test")
	req.Header.Set("X-Auth-Request-Preferred-Username", "demo")
	req.Header.Set("X-Auth-Request-Groups", "platform-viewers")
	req.Header.Set("X-Auth-Request-Access-Token", "access-token-value")
	rec := httptest.NewRecorder()
	NewServer(cfg, nil, nil).ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("auth returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"status":"authenticated"`) ||
		!strings.Contains(rec.Body.String(), `"email":"demo@dev.test"`) ||
		!strings.Contains(rec.Body.String(), `"present":true`) {
		t.Fatalf("auth evidence missing expected fields: %s", rec.Body.String())
	}
}

func TestGatewayModeRequiresGatewaySession(t *testing.T) {
	cfg := testConfig()
	cfg.APIAuthMode = "gateway"
	rec := httptest.NewRecorder()
	NewServer(cfg, nil, nil).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/auth", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("auth returned %d, want 401: %s", rec.Code, rec.Body.String())
	}
}

func TestChatCallsOpenAICompatibleEndpoint(t *testing.T) {
	var upstreamAuth string
	llm := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upstreamAuth = r.Header.Get("Authorization")
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("path=%s", r.URL.Path)
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatal(err)
		}
		if payload["model"] != defaultModel {
			t.Fatalf("model=%v", payload["model"])
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"model":"Qwen3.5-9B-MLX-4bit","choices":[{"message":{"content":"Auth Chat response."}}],"usage":{"total_tokens":12}}`))
	}))
	defer llm.Close()

	cfg := testConfig()
	cfg.APIAuthMode = "gateway"
	cfg.LLMURL = llm.URL + "/v1/chat/completions"
	req := httptest.NewRequest(http.MethodPost, "/chat", strings.NewReader(`{"message":"hello"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Auth-Request-Email", "demo@dev.test")
	req.Header.Set("X-Auth-Request-Access-Token", "user-token")
	rec := httptest.NewRecorder()
	NewServer(cfg, nil, nil).ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("chat returned %d: %s", rec.Code, rec.Body.String())
	}
	if upstreamAuth != "" {
		t.Fatalf("user token was forwarded to model endpoint: %q", upstreamAuth)
	}
	if !strings.Contains(rec.Body.String(), `"assistant":"Auth Chat response."`) ||
		!strings.Contains(rec.Body.String(), `"status":"ok"`) ||
		!strings.Contains(rec.Body.String(), `"source":"gateway"`) {
		t.Fatalf("chat response missing expected fields: %s", rec.Body.String())
	}
}

func TestOIDCModeUsesBearerVerifier(t *testing.T) {
	cfg := testConfig()
	cfg.APIAuthMode = "oidc"
	req := httptest.NewRequest(http.MethodGet, "/auth", nil)
	req.Header.Set("Authorization", "Bearer good")
	rec := httptest.NewRecorder()
	NewServer(cfg, nil, staticVerifier{claims: idpauth.UserClaims{Subject: "user-123", Email: "demo@example.test"}}).ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("auth returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"sub":"user-123"`) {
		t.Fatalf("auth response missing verified claims: %s", rec.Body.String())
	}
}

func testConfig() Config {
	return Config{
		Port:           "8080",
		PublicBaseURL:  "http://localhost:8080",
		LLMURL:         "http://127.0.0.1:8000/v1/chat/completions",
		LLMModel:       defaultModel,
		LLMTimeout:     5_000_000_000,
		LLMMaxTokens:   128,
		LLMTemperature: 0,
		APIAuthMode:    "none",
	}
}
