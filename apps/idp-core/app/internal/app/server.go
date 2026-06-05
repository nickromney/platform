package app

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"platform.local/appconfig"
	"platform.local/apphttp"
	"platform.local/idp-core/internal/catalog"
	"platform.local/idp-core/internal/workflow"
)

type Config struct {
	AuditPath   string
	CatalogPath string
	Runtime     string
	StatusCmd   []string
}

type Server struct {
	auditPath   string
	catalogPath string
	runtime     string
	statusCmd   []string
	mux         *http.ServeMux
	registry    *workflow.Registry
}

const (
	apiPathRuntimes                  = "/api/v1/runtimes"
	apiPathRuntime                   = "/api/v1/runtime"
	apiPathStatus                    = "/api/v1/status"
	apiPathCatalogApps               = "/api/v1/catalog/apps"
	apiPathCatalogApp                = "/api/v1/catalog/apps/{app}"
	apiPathDeployments               = "/api/v1/deployments"
	apiPathSecrets                   = "/api/v1/secrets"
	apiPathScorecards                = "/api/v1/scorecards"
	apiPathActions                   = "/api/v1/actions"
	apiPathOpenAPI                   = "/openapi.json"
	apiPathEnvironments              = "/api/v1/environments"
	apiPathEnvironment               = "/api/v1/environments/{app}/{environment}"
	apiPathDeploymentPromote         = "/api/v1/deployments/promote"
	apiPathDeploymentRollback        = "/api/v1/deployments/rollback"
	apiPathAppsScaffold              = "/api/v1/apps/scaffold"
	apiPathWorkflowEnvironmentDryRun = "/api/v1/workflows/environments/dry-run"
	apiPathWorkflowDeploymentDryRun  = "/api/v1/workflows/deployments/dry-run"
	apiPathWorkflowSecretDryRun      = "/api/v1/workflows/secrets/dry-run"
)

var idpAPIPathSpecs = []struct {
	method string
	path   string
}{
	{"get", apiPathRuntimes},
	{"get", apiPathRuntime},
	{"get", apiPathStatus},
	{"get", apiPathCatalogApps},
	{"get", apiPathCatalogApp},
	{"get", apiPathDeployments},
	{"get", apiPathSecrets},
	{"get", apiPathScorecards},
	{"get", apiPathActions},
	{"post", apiPathEnvironments},
	{"delete", apiPathEnvironment},
	{"post", apiPathDeploymentPromote},
	{"post", apiPathDeploymentRollback},
	{"post", apiPathAppsScaffold},
	{"post", apiPathWorkflowEnvironmentDryRun},
	{"post", apiPathWorkflowDeploymentDryRun},
	{"post", apiPathWorkflowSecretDryRun},
}

func NewServer(cfg Config) (*Server, error) {
	if cfg.AuditPath == "" {
		cfg.AuditPath = "/tmp/idp-core/audit.jsonl"
	}
	if cfg.CatalogPath == "" {
		cfg.CatalogPath = "/app/catalog/platform-apps.json"
	}
	if cfg.Runtime == "" {
		cfg.Runtime = "kind"
	}
	registry := workflow.NewPlatformRuntimeRegistry()

	s := &Server{
		auditPath:   cfg.AuditPath,
		catalogPath: cfg.CatalogPath,
		runtime:     cfg.Runtime,
		statusCmd:   cfg.StatusCmd,
		mux:         http.NewServeMux(),
		registry:    registry,
	}
	s.routes()
	return s, nil
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if apphttp.HandleCORS(w, r, portalCORSConfig()) {
		return
	}
	s.mux.ServeHTTP(w, r)
}

func (s *Server) routes() {
	s.mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		apphttp.WriteJSON(w, http.StatusOK, map[string]any{"status": "healthy", "service": "idp-core"})
	})
	s.mux.HandleFunc("GET "+apiPathRuntimes, func(w http.ResponseWriter, r *http.Request) {
		var list []map[string]string
		for _, a := range s.registry.List() {
			list = append(list, map[string]string{"name": a.Name(), "description": a.Description()})
		}
		apphttp.WriteJSON(w, http.StatusOK, map[string]any{"runtimes": list})
	})
	s.mux.HandleFunc("GET "+apiPathRuntime, func(w http.ResponseWriter, r *http.Request) {
		adapter, ok := s.registry.Get(s.runtime)
		if !ok {
			writeError(w, http.StatusBadRequest, "unsupported runtime: "+s.runtime)
			return
		}
		var list []map[string]string
		for _, a := range s.registry.List() {
			list = append(list, map[string]string{"name": a.Name(), "description": a.Description()})
		}
		apphttp.WriteJSON(w, http.StatusOK, map[string]any{
			"active_runtime": map[string]string{"name": adapter.Name(), "description": adapter.Description()},
			"runtimes":       list,
		})
	})
	s.mux.HandleFunc("GET "+apiPathStatus, s.status)
	s.mux.HandleFunc("GET "+apiPathCatalogApps, s.catalogApps)
	s.mux.HandleFunc("GET "+apiPathCatalogApp, s.catalogApp)
	s.mux.HandleFunc("GET "+apiPathDeployments, s.deployments)
	s.mux.HandleFunc("GET "+apiPathSecrets, s.secrets)
	s.mux.HandleFunc("GET "+apiPathScorecards, s.scorecards)
	s.mux.HandleFunc("GET "+apiPathActions, s.actions)
	s.mux.HandleFunc("GET "+apiPathOpenAPI, func(w http.ResponseWriter, r *http.Request) {
		apphttp.WriteJSON(w, http.StatusOK, openAPI())
	})
	s.mux.HandleFunc("POST "+apiPathEnvironments, s.createEnvironment)
	s.mux.HandleFunc("DELETE "+apiPathEnvironment, s.deleteEnvironment)
	s.mux.HandleFunc("POST "+apiPathDeploymentPromote, s.promoteDeployment)
	s.mux.HandleFunc("POST "+apiPathDeploymentRollback, s.rollbackDeployment)
	s.mux.HandleFunc("POST "+apiPathAppsScaffold, s.scaffoldApp)
	s.mux.HandleFunc("POST "+apiPathWorkflowEnvironmentDryRun, s.environmentDryRun)
	s.mux.HandleFunc("POST "+apiPathWorkflowDeploymentDryRun, s.deploymentDryRun)
	s.mux.HandleFunc("POST "+apiPathWorkflowSecretDryRun, s.secretDryRun)
}

func (s *Server) status(w http.ResponseWriter, r *http.Request) {
	adapter, ok := s.registry.Get(s.runtime)
	if !ok {
		writeError(w, http.StatusBadRequest, "unsupported runtime: "+s.runtime)
		return
	}
	payload := map[string]any{
		"overall_state":       "unavailable",
		"active_variant_path": nil,
		"actions":             []any{},
		"source":              "unavailable",
		"source_status":       "unconfigured",
		"detail":              "no status provider configured",
	}
	if len(s.statusCmd) > 0 {
		payload = collectStatus(s.statusCmd)
	}
	payload["runtime"] = adapter.Name()
	apphttp.WriteJSON(w, http.StatusOK, payload)
}

func (s *Server) catalogApps(w http.ResponseWriter, r *http.Request) {
	c, err := catalog.Load(s.catalogPath)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{"applications": c.Applications})
}

func (s *Server) catalogApp(w http.ResponseWriter, r *http.Request) {
	c, err := catalog.Load(s.catalogPath)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	name := r.PathValue("app")
	if app, ok := c.GetApp(name); ok {
		apphttp.WriteJSON(w, http.StatusOK, app)
		return
	}
	writeError(w, http.StatusNotFound, "app not found: "+name)
}

func (s *Server) deployments(w http.ResponseWriter, r *http.Request) {
	c, err := catalog.Load(s.catalogPath)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{"deployments": c.ListDeployments()})
}

func (s *Server) secrets(w http.ResponseWriter, r *http.Request) {
	c, err := catalog.Load(s.catalogPath)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{"secrets": c.ListSecrets()})
}

func (s *Server) scorecards(w http.ResponseWriter, r *http.Request) {
	c, err := catalog.Load(s.catalogPath)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{"scorecards": c.ListScorecards()})
}

func (s *Server) actions(w http.ResponseWriter, r *http.Request) {
	adapter, ok := s.registry.Get(s.runtime)
	if !ok {
		writeError(w, http.StatusBadRequest, "unsupported runtime: "+s.runtime)
		return
	}
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{"actions": []map[string]any{
		{"id": "environment.create", "label": "Create environment", "runtime": adapter.Name(), "dry_run": true},
		{"id": "deployment.promote", "label": "Promote deployment", "runtime": adapter.Name(), "dry_run": true},
		{"id": "app.scaffold", "label": "Scaffold app", "runtime": adapter.Name(), "dry_run": true},
	}})
}

func (s *Server) createEnvironment(w http.ResponseWriter, r *http.Request) {
	if !dryRun(r) {
		writeError(w, http.StatusNotImplemented, "apply mode is not implemented")
		return
	}
	payload, ok := decodeObject(w, r)
	if !ok {
		return
	}
	runtime := appconfig.StringDefault(stringValue(payload["runtime"]), s.runtime)
	adapter, ok := s.registry.Get(runtime)
	if !ok {
		writeError(w, http.StatusBadRequest, "unsupported runtime: "+runtime)
		return
	}
	req := workflow.EnvironmentRequest{
		App:         stringValue(payload["app"]),
		Environment: stringValue(payload["environment"]),
		Action:      "create",
	}
	plan := adapter.PlanEnvironment(req)
	apphttp.WriteJSON(w, http.StatusOK, s.workflowResponse("environment.create", adapter.Name(), plan, payload))
}

func (s *Server) deleteEnvironment(w http.ResponseWriter, r *http.Request) {
	if !dryRun(r) {
		writeError(w, http.StatusNotImplemented, "apply mode is not implemented")
		return
	}
	runtime := appconfig.StringDefault(r.URL.Query().Get("runtime"), s.runtime)
	adapter, ok := s.registry.Get(runtime)
	if !ok {
		writeError(w, http.StatusBadRequest, "unsupported runtime: "+runtime)
		return
	}
	payload := map[string]any{
		"runtime":     adapter.Name(),
		"action":      "delete",
		"app":         r.PathValue("app"),
		"environment": r.PathValue("environment"),
	}
	req := workflow.EnvironmentRequest{
		App:         stringValue(payload["app"]),
		Environment: stringValue(payload["environment"]),
		Action:      "delete",
	}
	plan := adapter.PlanEnvironment(req)
	apphttp.WriteJSON(w, http.StatusOK, s.workflowResponse("environment.delete", adapter.Name(), plan, payload))
}

func (s *Server) promoteDeployment(w http.ResponseWriter, r *http.Request) {
	s.deploymentAction(w, r, "deployment.promote", false)
}

func (s *Server) rollbackDeployment(w http.ResponseWriter, r *http.Request) {
	s.deploymentAction(w, r, "deployment.rollback", true)
}

func (s *Server) deploymentAction(w http.ResponseWriter, r *http.Request, action string, rollback bool) {
	if !dryRun(r) {
		writeError(w, http.StatusNotImplemented, "apply mode is not implemented")
		return
	}
	payload, ok := decodeObject(w, r)
	if !ok {
		return
	}
	runtime := appconfig.StringDefault(stringValue(payload["runtime"]), s.runtime)
	adapter, ok := s.registry.Get(runtime)
	if !ok {
		writeError(w, http.StatusBadRequest, "unsupported runtime: "+runtime)
		return
	}
	req := workflow.DeploymentRequest{
		App:         stringValue(payload["app"]),
		Environment: stringValue(payload["environment"]),
		Image:       stringValue(payload["image"]),
	}
	plan := adapter.PlanDeployment(req)
	if rollback {
		plan.Summary = fmt.Sprintf("would roll back %s/%s on %s", req.App, req.Environment, adapter.Name())
	}
	apphttp.WriteJSON(w, http.StatusOK, s.workflowResponse(action, adapter.Name(), plan, payload))
}

func (s *Server) scaffoldApp(w http.ResponseWriter, r *http.Request) {
	if !dryRun(r) {
		writeError(w, http.StatusNotImplemented, "apply mode is not implemented")
		return
	}
	payload, ok := decodeObject(w, r)
	if !ok {
		return
	}
	runtime := appconfig.StringDefault(stringValue(payload["runtime"]), s.runtime)
	adapter, ok := s.registry.Get(runtime)
	if !ok {
		writeError(w, http.StatusBadRequest, "unsupported runtime: "+runtime)
		return
	}
	req := workflow.EnvironmentRequest{
		App:         stringValue(payload["app"]),
		Environment: "dev",
		Action:      "create",
	}
	plan := adapter.PlanEnvironment(req)
	plan.Summary = fmt.Sprintf("would scaffold app %s for %s on %s", req.App, stringValue(payload["owner"]), adapter.Name())
	apphttp.WriteJSON(w, http.StatusOK, s.workflowResponse("app.scaffold", adapter.Name(), plan, payload))
}

func (s *Server) environmentDryRun(w http.ResponseWriter, r *http.Request) {
	s.workflowDryRun(w, r, "environment", func(adapter workflow.Adapter, payload map[string]any) *workflow.Plan {
		return adapter.PlanEnvironment(workflow.EnvironmentRequest{
			App:         stringValue(payload["app"]),
			Environment: stringValue(payload["environment"]),
			Action:      appconfig.StringDefault(stringValue(payload["action"]), "create"),
		})
	})
}

func (s *Server) deploymentDryRun(w http.ResponseWriter, r *http.Request) {
	s.workflowDryRun(w, r, "deployment", func(adapter workflow.Adapter, payload map[string]any) *workflow.Plan {
		return adapter.PlanDeployment(workflow.DeploymentRequest{
			App:         stringValue(payload["app"]),
			Environment: stringValue(payload["environment"]),
			Image:       stringValue(payload["image"]),
		})
	})
}

func (s *Server) secretDryRun(w http.ResponseWriter, r *http.Request) {
	s.workflowDryRun(w, r, "secret", func(adapter workflow.Adapter, payload map[string]any) *workflow.Plan {
		return adapter.PlanSecret(workflow.SecretRequest{
			App:         stringValue(payload["app"]),
			Environment: stringValue(payload["environment"]),
			Secret:      stringValue(payload["secret"]),
			Keys:        stringSlice(payload["keys"]),
		})
	})
}

func (s *Server) workflowDryRun(w http.ResponseWriter, r *http.Request, workflowName string, planner func(workflow.Adapter, map[string]any) *workflow.Plan) {
	payload, ok := decodeObject(w, r)
	if !ok {
		return
	}
	runtime := appconfig.StringDefault(stringValue(payload["runtime"]), s.runtime)
	adapter, ok := s.registry.Get(runtime)
	if !ok {
		writeError(w, http.StatusBadRequest, "unsupported runtime: "+runtime)
		return
	}
	plan := planner(adapter, payload)
	audit := s.writeAudit(workflowName+".dry_run", adapter.Name(), workflowName, payload)
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{
		"dry_run":  true,
		"runtime":  adapter.Name(),
		"workflow": workflowName,
		"plan":     plan,
		"audit":    audit,
	})
}

func (s *Server) workflowResponse(action, runtime string, plan *workflow.Plan, request map[string]any) map[string]any {
	audit := s.writeAudit(action, runtime, strings.SplitN(action, ".", 2)[0], withDryRun(request))
	return map[string]any{"dry_run": true, "action": action, "runtime": runtime, "plan": plan, "audit": audit}
}

func (s *Server) writeAudit(event, runtime, workflow string, request map[string]any) map[string]any {
	id := uuid()
	requestID := uuid()
	record := map[string]any{
		"id":         id,
		"request_id": requestID,
		"timestamp":  time.Now().UTC().Format(time.RFC3339Nano),
		"event":      event,
		"action":     event,
		"actor":      "local",
		"runtime":    runtime,
		"workflow":   workflow,
		"dry_run":    true,
		"result":     "planned",
		"request":    request,
	}
	if err := os.MkdirAll(filepath.Dir(s.auditPath), 0o755); err == nil {
		if file, err := os.OpenFile(s.auditPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644); err == nil {
			_ = json.NewEncoder(file).Encode(record)
			_ = file.Close()
		}
	}
	return map[string]any{"id": id, "event": event, "runtime": runtime}
}

func collectStatus(command []string) map[string]any {
	ctx := command[0]
	cmd := exec.Command(ctx, command[1:]...)
	out, err := cmd.Output()
	if err != nil {
		return map[string]any{
			"overall_state":       "unavailable",
			"active_variant_path": nil,
			"actions":             []any{},
			"source":              "platform-status-script",
			"source_status":       "unavailable",
			"detail":              err.Error(),
		}
	}
	var payload map[string]any
	if err := json.Unmarshal(out, &payload); err != nil {
		return map[string]any{
			"overall_state":       "unavailable",
			"active_variant_path": nil,
			"actions":             []any{},
			"source":              "platform-status-script",
			"source_status":       "unavailable",
			"detail":              "invalid json: " + err.Error(),
		}
	}
	defaultValue(payload, "source", "platform-status-script")
	defaultValue(payload, "source_status", "available")
	return payload
}

func portalCORSConfig() apphttp.CORSConfig {
	return apphttp.CORSConfig{
		AllowedOrigins: []string{
			"https://portal.127.0.0.1.sslip.io",
			"https://portal-api.127.0.0.1.sslip.io",
			"http://127.0.0.1:5173",
			"http://localhost:5173",
		},
		AllowCredentials: true,
		AllowMethods:     []string{"*"},
		AllowHeaders:     []string{"*"},
		PreflightStatus:  http.StatusOK,
	}
}

func writeError(w http.ResponseWriter, status int, detail string) {
	apphttp.WriteJSON(w, status, map[string]any{"detail": detail})
}

func decodeObject(w http.ResponseWriter, r *http.Request) (map[string]any, bool) {
	var payload map[string]any
	if !apphttp.DecodeJSON(w, r, &payload, map[string]any{"detail": "invalid JSON body"}) {
		return nil, false
	}
	return payload, true
}

func dryRun(r *http.Request) bool {
	return r.URL.Query().Get("dry_run") != "false"
}

func withDryRun(request map[string]any) map[string]any {
	out := copyMap(request)
	out["dry_run"] = true
	return out
}

func uuid() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	text := hex.EncodeToString(b[:])
	return text[0:8] + "-" + text[8:12] + "-" + text[12:16] + "-" + text[16:20] + "-" + text[20:32]
}

func mapValue(value any) map[string]any {
	if out, ok := value.(map[string]any); ok {
		return out
	}
	return map[string]any{}
}

func copyMap(in map[string]any) map[string]any {
	out := make(map[string]any, len(in))
	for key, value := range in {
		out[key] = value
	}
	return out
}

func defaultValue(m map[string]any, key string, value any) {
	if _, ok := m[key]; !ok {
		m[key] = value
	}
}

func stringValue(value any) string {
	if out, ok := value.(string); ok {
		return out
	}
	return ""
}

func stringSlice(value any) []string {
	raw, ok := value.([]any)
	if !ok {
		return []string{}
	}
	out := make([]string, 0, len(raw))
	for _, item := range raw {
		if text := stringValue(item); text != "" {
			out = append(out, text)
		}
	}
	return out
}

func openAPI() map[string]any {
	paths := map[string]any{}
	for _, item := range idpAPIPathSpecs {
		methods := mapValue(paths[item.path])
		methods[item.method] = map[string]any{"operationId": strings.ReplaceAll(strings.Trim(item.path, "/"), "/", "_")}
		paths[item.path] = methods
	}
	return map[string]any{"info": map[string]any{"title": "IDP Core"}, "paths": paths}
}
