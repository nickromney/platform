package app

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func testServer(t *testing.T) *Server {
	t.Helper()
	root := filepath.Join("..", "..", "..", "..", "..")
	server, err := NewServer(Config{
		AuditPath:   filepath.Join(t.TempDir(), "audit.jsonl"),
		CatalogPath: filepath.Join(root, "catalog", "platform-apps.json"),
		Runtime:     "kind",
	})
	if err != nil {
		t.Fatal(err)
	}
	return server
}

func request(t *testing.T, server http.Handler, method, path string, body any) (*httptest.ResponseRecorder, map[string]any) {
	t.Helper()
	var reader bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&reader).Encode(body); err != nil {
			t.Fatal(err)
		}
	}
	req := httptest.NewRequest(method, path, &reader)
	if body != nil {
		req.Header.Set("content-type", "application/json")
	}
	rec := httptest.NewRecorder()
	server.ServeHTTP(rec, req)
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v\n%s", err, rec.Body.String())
	}
	return rec, payload
}

func TestHealthRuntimeAndCatalog(t *testing.T) {
	server := testServer(t)

	rec, health := request(t, server, http.MethodGet, "/health", nil)
	if rec.Code != http.StatusOK || health["service"] != "idp-core" {
		t.Fatalf("unexpected health: %d %#v", rec.Code, health)
	}

	rec, runtime := request(t, server, http.MethodGet, "/api/v1/runtime", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("runtime status: %d", rec.Code)
	}
	active := runtime["active_runtime"].(map[string]any)
	if active["name"] != "kind" {
		t.Fatalf("active runtime = %#v", active)
	}

	rec, catalog := request(t, server, http.MethodGet, "/api/v1/catalog/apps", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("catalog status: %d", rec.Code)
	}
	found := false
	for _, item := range catalog["applications"].([]any) {
		app := item.(map[string]any)
		found = found || app["name"] == "idp-core"
	}
	if !found {
		t.Fatal("catalog did not include idp-core")
	}
}

func TestCORSAllowsPortalOrigins(t *testing.T) {
	server := testServer(t)
	req := httptest.NewRequest(http.MethodOptions, "/api/v1/catalog/apps", nil)
	req.Header.Set("origin", "https://portal-api.127.0.0.1.sslip.io")
	req.Header.Set("access-control-request-method", "GET")
	rec := httptest.NewRecorder()

	server.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	if got := rec.Header().Get("access-control-allow-origin"); got != "https://portal-api.127.0.0.1.sslip.io" {
		t.Fatalf("allow-origin = %q", got)
	}
	if got := rec.Header().Get("access-control-allow-credentials"); got != "true" {
		t.Fatalf("allow-credentials = %q", got)
	}
}

func TestWorkflowResponsesAreDryRunAndAudited(t *testing.T) {
	auditPath := filepath.Join(t.TempDir(), "audit.jsonl")
	server, err := NewServer(Config{
		AuditPath:   auditPath,
		CatalogPath: filepath.Join("..", "..", "..", "..", "..", "catalog", "platform-apps.json"),
		Runtime:     "kind",
	})
	if err != nil {
		t.Fatal(err)
	}

	rec, payload := request(t, server, http.MethodPost, "/api/v1/environments?dry_run=true", map[string]any{
		"runtime":     "kind",
		"app":         "hello-platform",
		"environment": "preview",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("status: %d body=%s", rec.Code, rec.Body.String())
	}
	if payload["action"] != "environment.create" || payload["runtime"] != "kind" || payload["dry_run"] != true {
		t.Fatalf("unexpected workflow response: %#v", payload)
	}
	plan := payload["plan"].(map[string]any)
	if plan["summary"] != "would create environment preview for hello-platform on kind" {
		t.Fatalf("summary = %q", plan["summary"])
	}
	data, err := os.ReadFile(auditPath)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(data, []byte(`"event":"environment.create"`)) {
		t.Fatalf("audit missing event: %s", string(data))
	}
}

func TestCatalogDerivedReadModels(t *testing.T) {
	dir := t.TempDir()
	catalogPath := filepath.Join(dir, "platform-apps.json")
	err := os.WriteFile(catalogPath, []byte(`{
  "applications": [{
    "name": "fixture-service",
    "owner": "team-platform",
    "health": "/readyz",
    "deployment": {"controller": "argocd", "image": "registry.local/fixture:base", "sync": "automated"},
    "environments": [
      {"name": "dev", "route": "https://fixture.dev.example.test", "deployment": {"image": "registry.local/fixture:dev"}},
      {"name": "uat", "route": "https://fixture.uat.example.test", "health": "/healthz", "sync": "manual"}
    ],
    "secrets": [{"name": "runtime-token", "scope": "runtime"}],
    "scorecard": {"tier": "gold"}
  }]
}`), 0o644)
	if err != nil {
		t.Fatal(err)
	}
	server, err := NewServer(Config{AuditPath: filepath.Join(dir, "audit.jsonl"), CatalogPath: catalogPath, Runtime: "kind"})
	if err != nil {
		t.Fatal(err)
	}

	_, deployments := request(t, server, http.MethodGet, "/api/v1/deployments", nil)
	firstDeployment := deployments["deployments"].([]any)[0].(map[string]any)
	if firstDeployment["image"] != "registry.local/fixture:dev" {
		t.Fatalf("deployment projection = %#v", firstDeployment)
	}

	_, secrets := request(t, server, http.MethodGet, "/api/v1/secrets", nil)
	firstSecret := secrets["secrets"].([]any)[0].(map[string]any)
	if firstSecret["binding"] != "unknown" || firstSecret["scope"] != "runtime" {
		t.Fatalf("secret projection = %#v", firstSecret)
	}

	_, scorecards := request(t, server, http.MethodGet, "/api/v1/scorecards", nil)
	firstScorecard := scorecards["scorecards"].([]any)[0].(map[string]any)
	if firstScorecard["has_owner"] != true || firstScorecard["tier"] != "gold" {
		t.Fatalf("scorecard projection = %#v", firstScorecard)
	}
}
