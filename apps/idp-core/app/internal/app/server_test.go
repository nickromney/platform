package app

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"platform.local/idp-core/internal/workflow"
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

func rawJSONRequest(t *testing.T, server http.Handler, method, path, body string) (*httptest.ResponseRecorder, map[string]any) {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.Header.Set("content-type", "application/json")
	rec := httptest.NewRecorder()
	server.ServeHTTP(rec, req)
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v\n%s", err, rec.Body.String())
	}
	return rec, payload
}

func TestServerUsesSharedStringDefault(t *testing.T) {
	source, err := os.ReadFile("server.go")
	if err != nil {
		t.Fatal(err)
	}
	text := string(source)
	if !strings.Contains(text, "appconfig.StringDefault(") {
		t.Fatalf("server.go should use shared appconfig string defaulting")
	}
	if strings.Contains(text, "func defaultString(") {
		t.Fatalf("server.go should not keep app-local defaultString helper")
	}
}

func assertSchemaShaped(t *testing.T, record map[string]any, schemaName string) {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "..", "schemas", "idp", schemaName))
	if err != nil {
		t.Fatal(err)
	}
	var schema map[string]any
	if err := json.Unmarshal(data, &schema); err != nil {
		t.Fatal(err)
	}
	for _, field := range arrayValue(schema["required"]) {
		name := field.(string)
		if _, ok := record[name]; !ok {
			t.Fatalf("%s missing required field %q in %#v", schemaName, name, record)
		}
	}
	properties := mapValue(schema["properties"])
	for name, rawSpec := range properties {
		value, ok := record[name]
		if !ok {
			continue
		}
		spec := mapValue(rawSpec)
		if !valueMatchesSchemaType(value, spec["type"]) {
			t.Fatalf("%s field %q has %T=%#v, want %v", schemaName, name, value, value, spec["type"])
		}
	}
}

func valueMatchesSchemaType(value any, expected any) bool {
	for _, schemaType := range schemaTypes(expected) {
		switch schemaType {
		case "array":
			if reflect.TypeOf(value).Kind() == reflect.Slice {
				return true
			}
		case "boolean":
			if _, ok := value.(bool); ok {
				return true
			}
		case "null":
			if value == nil {
				return true
			}
		case "object":
			if _, ok := value.(map[string]any); ok {
				return true
			}
		case "string":
			if _, ok := value.(string); ok {
				return true
			}
		}
	}
	return false
}

func schemaTypes(expected any) []string {
	switch value := expected.(type) {
	case string:
		return []string{value}
	case []any:
		out := make([]string, 0, len(value))
		for _, item := range value {
			if text, ok := item.(string); ok {
				out = append(out, text)
			}
		}
		return out
	default:
		return []string{}
	}
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

	rec, runtimes := request(t, server, http.MethodGet, "/api/v1/runtimes", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("runtimes status: %d", rec.Code)
	}
	wantRuntimes := []map[string]string{
		{"name": "generic_kubernetes", "description": "Generic Kubernetes workflow adapter"},
		{"name": "kind", "description": "Local kind workflow adapter"},
		{"name": "lima", "description": "Local Lima workflow adapter"},
	}
	if len(runtimes["runtimes"].([]any)) != len(wantRuntimes) {
		t.Fatalf("runtimes = %#v", runtimes["runtimes"])
	}
	for idx, item := range runtimes["runtimes"].([]any) {
		got := item.(map[string]any)
		if got["name"] != wantRuntimes[idx]["name"] || got["description"] != wantRuntimes[idx]["description"] {
			t.Fatalf("runtime %d = %#v", idx, got)
		}
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

	rec, app := request(t, server, http.MethodGet, "/api/v1/catalog/apps/idp-core", nil)
	if rec.Code != http.StatusOK || app["name"] != "idp-core" {
		t.Fatalf("catalog app = %d %#v", rec.Code, app)
	}

	for _, path := range []string{"/api/v1/deployments", "/api/v1/secrets", "/api/v1/scorecards", "/api/v1/actions", "/openapi.json"} {
		rec, _ := request(t, server, http.MethodGet, path, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s status = %d", path, rec.Code)
		}
	}
}

func TestOpenAPIUsesRegisteredRouteSpecs(t *testing.T) {
	paths := openAPI()["paths"].(map[string]any)
	for _, path := range []string{
		"/api/v1/runtime",
		"/api/v1/status",
		"/api/v1/catalog/apps",
		"/api/v1/deployments",
		"/api/v1/secrets",
		"/api/v1/scorecards",
		"/api/v1/actions",
		"/api/v1/environments",
		"/api/v1/environments/{app}/{environment}",
		"/api/v1/deployments/promote",
		"/api/v1/workflows/secrets/dry-run",
	} {
		if _, ok := paths[path]; !ok {
			t.Fatalf("openapi paths missing %s in %#v", path, paths)
		}
	}
	if _, ok := paths["/api/v1/environments/{app_name}/{environment}"]; ok {
		t.Fatalf("openapi should use registered route parameter names: %#v", paths)
	}
}

func TestCORSAllowsPortalOrigins(t *testing.T) {
	server := testServer(t)

	for _, origin := range []string{"https://portal.127.0.0.1.sslip.io", "https://portal-api.127.0.0.1.sslip.io"} {
		req := httptest.NewRequest(http.MethodOptions, "/api/v1/catalog/apps", nil)
		req.Header.Set("origin", origin)
		req.Header.Set("access-control-request-method", "GET")
		rec := httptest.NewRecorder()

		server.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("%s status = %d", origin, rec.Code)
		}
		if got := rec.Header().Get("access-control-allow-origin"); got != origin {
			t.Fatalf("%s allow-origin = %q", origin, got)
		}
		if got := rec.Header().Get("access-control-allow-credentials"); got != "true" {
			t.Fatalf("%s allow-credentials = %q", origin, got)
		}
	}
}

func TestStatusProjectionUsesInjectedCommand(t *testing.T) {
	statusJSON := `{"overall_state":"running","active_variant_path":"kubernetes/kind","actions":[{"id":"kind-status","label":"Kind status","command":"make -C kubernetes/kind status","enabled":true}],"source":"fixture","source_status":"available"}`
	server, err := NewServer(Config{
		AuditPath:   filepath.Join(t.TempDir(), "audit.jsonl"),
		CatalogPath: filepath.Join("..", "..", "..", "..", "..", "catalog", "platform-apps.json"),
		Runtime:     "kind",
		StatusCmd:   []string{"sh", "-c", fmt.Sprintf("printf '%%s\\n' %q", statusJSON)},
	})
	if err != nil {
		t.Fatal(err)
	}

	rec, status := request(t, server, http.MethodGet, "/api/v1/status", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("status code = %d", rec.Code)
	}
	if status["runtime"] != "kind" || status["overall_state"] != "running" || status["active_variant_path"] != "kubernetes/kind" {
		t.Fatalf("status projection = %#v", status)
	}
	actions := status["actions"].([]any)
	if actions[0].(map[string]any)["id"] != "kind-status" {
		t.Fatalf("actions = %#v", actions)
	}
	assertSchemaShaped(t, status, "status.schema.json")
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

	cases := []struct {
		method string
		path   string
		body   map[string]any
		action string
	}{
		{http.MethodDelete, "/api/v1/environments/hello-platform/preview?runtime=kind&dry_run=true", nil, "environment.delete"},
		{http.MethodPost, "/api/v1/deployments/promote?dry_run=true", map[string]any{"runtime": "kind", "app": "hello-platform", "environment": "uat", "image": "registry.local/hello-platform:test"}, "deployment.promote"},
		{http.MethodPost, "/api/v1/deployments/rollback?dry_run=true", map[string]any{"runtime": "kind", "app": "hello-platform", "environment": "uat"}, "deployment.rollback"},
		{http.MethodPost, "/api/v1/apps/scaffold?dry_run=true", map[string]any{"runtime": "kind", "app": "new-service", "owner": "team-platform"}, "app.scaffold"},
	}
	for _, tc := range cases {
		rec, payload := request(t, server, tc.method, tc.path, tc.body)
		if rec.Code != http.StatusOK || payload["action"] != tc.action || payload["dry_run"] != true {
			t.Fatalf("%s %s = %d %#v", tc.method, tc.path, rec.Code, payload)
		}
	}

	for _, tc := range []struct {
		method string
		path   string
		body   map[string]any
	}{
		{http.MethodPost, "/api/v1/environments?dry_run=false", map[string]any{"runtime": "kind", "app": "hello-platform", "environment": "preview"}},
		{http.MethodDelete, "/api/v1/environments/hello-platform/preview?runtime=kind&dry_run=false", nil},
		{http.MethodPost, "/api/v1/deployments/promote?dry_run=false", map[string]any{"runtime": "kind", "app": "hello-platform", "environment": "uat", "image": "registry.local/hello-platform:test"}},
		{http.MethodPost, "/api/v1/deployments/rollback?dry_run=false", map[string]any{"runtime": "kind", "app": "hello-platform", "environment": "uat"}},
		{http.MethodPost, "/api/v1/apps/scaffold?dry_run=false", map[string]any{"runtime": "kind", "app": "new-service", "owner": "team-platform"}},
	} {
		rec, _ := request(t, server, tc.method, tc.path, tc.body)
		if rec.Code != http.StatusNotImplemented {
			t.Fatalf("%s %s status = %d", tc.method, tc.path, rec.Code)
		}
	}
}

func TestWorkflowDryRunsUseSelectedAdapters(t *testing.T) {
	server := testServer(t)

	rec, env := request(t, server, http.MethodPost, "/api/v1/workflows/environments/dry-run", map[string]any{
		"runtime":     "kind",
		"action":      "create",
		"app":         "hello-platform",
		"environment": "preview",
	})
	if rec.Code != http.StatusOK || env["runtime"] != "kind" || env["workflow"] != "environment" {
		t.Fatalf("environment dry-run = %d %#v", rec.Code, env)
	}
	envPlan := env["plan"].(map[string]any)
	if envPlan["commands"].([]any)[0] != "make -C kubernetes/kind idp-env ACTION=create APP=hello-platform ENV=preview DRY_RUN=1" {
		t.Fatalf("environment command = %#v", envPlan["commands"])
	}

	rec, deployment := request(t, server, http.MethodPost, "/api/v1/workflows/deployments/dry-run", map[string]any{
		"runtime":     "lima",
		"app":         "sentiment",
		"environment": "uat",
		"image":       "registry.local/sentiment:test",
	})
	if rec.Code != http.StatusOK || deployment["runtime"] != "lima" || deployment["workflow"] != "deployment" {
		t.Fatalf("deployment dry-run = %d %#v", rec.Code, deployment)
	}
	deploymentPlan := deployment["plan"].(map[string]any)
	if deploymentPlan["commands"].([]any)[0] != "make -C kubernetes/lima idp-deployments APP=sentiment ENV=uat IMAGE=registry.local/sentiment:test DRY_RUN=1" {
		t.Fatalf("deployment command = %#v", deploymentPlan["commands"])
	}

	rec, secret := request(t, server, http.MethodPost, "/api/v1/workflows/secrets/dry-run", map[string]any{
		"runtime":     "generic_kubernetes",
		"app":         "hello-platform",
		"environment": "dev",
		"secret":      "database-url",
		"keys":        []string{"url", "username"},
	})
	if rec.Code != http.StatusOK || secret["runtime"] != "generic_kubernetes" || secret["workflow"] != "secret" {
		t.Fatalf("secret dry-run = %d %#v", rec.Code, secret)
	}
	secretPlan := secret["plan"].(map[string]any)
	if secretPlan["commands"].([]any)[0] != "kubectl create secret generic database-url --namespace hello-platform-dev --from-literal=url=<redacted> --from-literal=username=<redacted> --dry-run=client -o yaml" {
		t.Fatalf("secret command = %#v", secretPlan["commands"])
	}

	rec, unsupported := request(t, server, http.MethodPost, "/api/v1/workflows/environments/dry-run", map[string]any{
		"runtime":     "docker-compose",
		"app":         "hello-platform",
		"environment": "preview",
	})
	if rec.Code != http.StatusBadRequest || unsupported["detail"] != "unsupported runtime: docker-compose" {
		t.Fatalf("unsupported runtime = %d %#v", rec.Code, unsupported)
	}
}

func TestWorkflowDryRunRejectsTrailingJSON(t *testing.T) {
	server := testServer(t)

	rec, payload := rawJSONRequest(
		t,
		server,
		http.MethodPost,
		"/api/v1/workflows/environments/dry-run",
		`{"runtime":"kind","app":"hello-platform","environment":"preview"} {}`,
	)

	if rec.Code != http.StatusBadRequest || payload["detail"] != "invalid JSON body" {
		t.Fatalf("trailing JSON response = %d %#v", rec.Code, payload)
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
	assertSchemaShaped(t, firstDeployment, "deployment.schema.json")

	_, secrets := request(t, server, http.MethodGet, "/api/v1/secrets", nil)
	firstSecret := secrets["secrets"].([]any)[0].(map[string]any)
	if firstSecret["binding"] != "not declared" || firstSecret["rotation"] != "not declared" || firstSecret["scope"] != "runtime" {
		t.Fatalf("secret projection = %#v", firstSecret)
	}
	assertSchemaShaped(t, firstSecret, "secret-binding.schema.json")

	_, scorecards := request(t, server, http.MethodGet, "/api/v1/scorecards", nil)
	firstScorecard := scorecards["scorecards"].([]any)[0].(map[string]any)
	if firstScorecard["has_owner"] != true || firstScorecard["runtime_profile"] != "not declared" || firstScorecard["tier"] != "gold" {
		t.Fatalf("scorecard projection = %#v", firstScorecard)
	}
	assertSchemaShaped(t, firstScorecard, "scorecard.schema.json")
}

func TestStatusFallbacksUseExplicitUnavailableState(t *testing.T) {
	dir := t.TempDir()
	server, err := NewServer(Config{AuditPath: filepath.Join(dir, "audit.jsonl"), CatalogPath: filepath.Join(dir, "missing.json"), Runtime: "kind"})
	if err != nil {
		t.Fatal(err)
	}

	_, status := request(t, server, http.MethodGet, "/api/v1/status", nil)
	if status["overall_state"] != "unavailable" || status["source_status"] != "unconfigured" {
		t.Fatalf("default status fallback should be explicit: %#v", status)
	}

	server, err = NewServer(Config{
		AuditPath: filepath.Join(dir, "audit.jsonl"),
		Runtime:   "kind",
		StatusCmd: []string{"/bin/sh", "-c", "exit 12"},
	})
	if err != nil {
		t.Fatal(err)
	}
	_, status = request(t, server, http.MethodGet, "/api/v1/status", nil)
	if status["overall_state"] != "unavailable" || status["source_status"] != "unavailable" {
		t.Fatalf("failed status provider fallback should be explicit: %#v", status)
	}
}

func TestAllAdaptersImplementDryRunContracts(t *testing.T) {
	registry := workflow.NewRegistry()
	registry.Register(&workflow.GenericAdapter{})
	registry.Register(workflow.NewMakeAdapter("kind", "Local kind workflow adapter", "kubernetes/kind", "kind"))
	registry.Register(workflow.NewMakeAdapter("lima", "Local Lima workflow adapter", "kubernetes/lima", "lima"))

	for _, adapter := range registry.List() {
		environment := adapter.PlanEnvironment(workflow.EnvironmentRequest{Action: "create", App: "hello-platform", Environment: "preview"})
		deployment := adapter.PlanDeployment(workflow.DeploymentRequest{App: "hello-platform", Environment: "preview", Image: "registry.local/hello-platform:test"})
		secret := adapter.PlanSecret(workflow.SecretRequest{App: "hello-platform", Environment: "preview", Secret: "api-token", Keys: []string{"token"}})
		for _, plan := range []*workflow.Plan{environment, deployment, secret} {
			if plan.DryRun != true || plan.Runtime != adapter.Name() || len(plan.Commands) == 0 || len(plan.Manifests) == 0 {
				t.Fatalf("%s plan = %#v", adapter.Name(), plan)
			}
		}
	}
}

func arrayValue(value any) []any {
	if out, ok := value.([]any); ok {
		return out
	}
	return []any{}
}
