package app

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
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
	s := &Server{
		auditPath:   cfg.AuditPath,
		catalogPath: cfg.CatalogPath,
		runtime:     cfg.Runtime,
		statusCmd:   cfg.StatusCmd,
		mux:         http.NewServeMux(),
	}
	s.routes()
	return s, nil
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	writeCORS(w, r)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}
	s.mux.ServeHTTP(w, r)
}

func (s *Server) routes() {
	s.mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"status": "healthy", "service": "idp-core"})
	})
	s.mux.HandleFunc("GET /api/v1/runtimes", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"runtimes": runtimeInfos()})
	})
	s.mux.HandleFunc("GET /api/v1/runtime", func(w http.ResponseWriter, r *http.Request) {
		adapter, err := adapterFor(s.runtime)
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"active_runtime": adapter.info(), "runtimes": runtimeInfos()})
	})
	s.mux.HandleFunc("GET /api/v1/status", s.status)
	s.mux.HandleFunc("GET /api/v1/catalog/apps", s.catalogApps)
	s.mux.HandleFunc("GET /api/v1/catalog/apps/{app}", s.catalogApp)
	s.mux.HandleFunc("GET /api/v1/deployments", s.deployments)
	s.mux.HandleFunc("GET /api/v1/secrets", s.secrets)
	s.mux.HandleFunc("GET /api/v1/scorecards", s.scorecards)
	s.mux.HandleFunc("GET /api/v1/actions", s.actions)
	s.mux.HandleFunc("GET /openapi.json", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, openAPI())
	})
	s.mux.HandleFunc("POST /api/v1/environments", s.createEnvironment)
	s.mux.HandleFunc("DELETE /api/v1/environments/{app}/{environment}", s.deleteEnvironment)
	s.mux.HandleFunc("POST /api/v1/deployments/promote", s.promoteDeployment)
	s.mux.HandleFunc("POST /api/v1/deployments/rollback", s.rollbackDeployment)
	s.mux.HandleFunc("POST /api/v1/apps/scaffold", s.scaffoldApp)
	s.mux.HandleFunc("POST /api/v1/workflows/environments/dry-run", s.environmentDryRun)
	s.mux.HandleFunc("POST /api/v1/workflows/deployments/dry-run", s.deploymentDryRun)
	s.mux.HandleFunc("POST /api/v1/workflows/secrets/dry-run", s.secretDryRun)
}

func (s *Server) status(w http.ResponseWriter, r *http.Request) {
	adapter, err := adapterFor(s.runtime)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	payload := map[string]any{
		"overall_state":       "unknown",
		"active_variant_path": nil,
		"actions":             []any{},
		"source":              "unavailable",
		"source_status":       "unconfigured",
		"detail":              "no status provider configured",
	}
	if len(s.statusCmd) > 0 {
		payload = collectStatus(s.statusCmd)
	}
	payload["runtime"] = adapter.Name
	writeJSON(w, http.StatusOK, payload)
}

func (s *Server) catalogApps(w http.ResponseWriter, r *http.Request) {
	catalog, err := s.catalog()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"applications": arrayValue(catalog["applications"])})
}

func (s *Server) catalogApp(w http.ResponseWriter, r *http.Request) {
	catalog, err := s.catalog()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	name := r.PathValue("app")
	for _, item := range arrayValue(catalog["applications"]) {
		app, ok := item.(map[string]any)
		if ok && stringValue(app["name"]) == name {
			writeJSON(w, http.StatusOK, app)
			return
		}
	}
	writeError(w, http.StatusNotFound, "app not found: "+name)
}

func (s *Server) deployments(w http.ResponseWriter, r *http.Request) {
	catalog, err := s.catalog()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	var records []map[string]any
	for _, item := range arrayValue(catalog["applications"]) {
		app, ok := item.(map[string]any)
		if !ok {
			continue
		}
		baseDeployment := mapValue(app["deployment"])
		for _, envItem := range arrayValue(app["environments"]) {
			env := mapValue(envItem)
			envDeployment := mapValue(env["deployment"])
			records = append(records, map[string]any{
				"app":         stringValue(app["name"]),
				"environment": stringValue(env["name"]),
				"route":       optionalString(env["route"]),
				"controller":  baseDeployment["controller"],
				"image":       firstString(envDeployment["image"], baseDeployment["image"]),
				"health":      firstString(env["health"], app["health"]),
				"sync":        firstString(env["sync"], baseDeployment["sync"]),
			})
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"deployments": records})
}

func (s *Server) secrets(w http.ResponseWriter, r *http.Request) {
	catalog, err := s.catalog()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	var records []map[string]any
	for _, item := range arrayValue(catalog["applications"]) {
		app, ok := item.(map[string]any)
		if !ok {
			continue
		}
		for _, secretItem := range arrayValue(app["secrets"]) {
			secret := copyMap(mapValue(secretItem))
			secret["app"] = stringValue(app["name"])
			if _, ok := secret["binding"]; !ok {
				secret["binding"] = "unknown"
			}
			if _, ok := secret["rotation"]; !ok {
				secret["rotation"] = "unknown"
			}
			records = append(records, secret)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"secrets": records})
}

func (s *Server) scorecards(w http.ResponseWriter, r *http.Request) {
	catalog, err := s.catalog()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	var records []map[string]any
	for _, item := range arrayValue(catalog["applications"]) {
		app, ok := item.(map[string]any)
		if !ok {
			continue
		}
		scorecard := copyMap(mapValue(app["scorecard"]))
		defaultValue(scorecard, "runtime_profile", "unknown")
		defaultValue(scorecard, "has_health_endpoint", false)
		defaultValue(scorecard, "has_network_policy", false)
		if _, ok := scorecard["has_owner"]; !ok {
			scorecard["has_owner"] = stringValue(app["owner"]) != ""
		}
		scorecard["app"] = stringValue(app["name"])
		records = append(records, scorecard)
	}
	writeJSON(w, http.StatusOK, map[string]any{"scorecards": records})
}

func (s *Server) actions(w http.ResponseWriter, r *http.Request) {
	adapter, err := adapterFor(s.runtime)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"actions": []map[string]any{
		{"id": "environment.create", "label": "Create environment", "runtime": adapter.Name, "dry_run": true},
		{"id": "deployment.promote", "label": "Promote deployment", "runtime": adapter.Name, "dry_run": true},
		{"id": "app.scaffold", "label": "Scaffold app", "runtime": adapter.Name, "dry_run": true},
	}})
}

func (s *Server) createEnvironment(w http.ResponseWriter, r *http.Request) {
	if !dryRun(r) {
		writeError(w, http.StatusNotImplemented, "apply mode is not implemented")
		return
	}
	request, err := decodeObject(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	request["action"] = "create"
	runtime := defaultString(request["runtime"], "kind")
	adapter, err := adapterFor(runtime)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	plan := adapter.planEnvironment(request)
	writeJSON(w, http.StatusOK, s.workflowResponse("environment.create", adapter.Name, plan, request))
}

func (s *Server) deleteEnvironment(w http.ResponseWriter, r *http.Request) {
	if !dryRun(r) {
		writeError(w, http.StatusNotImplemented, "apply mode is not implemented")
		return
	}
	runtime := defaultString(r.URL.Query().Get("runtime"), "kind")
	adapter, err := adapterFor(runtime)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	request := map[string]any{
		"runtime":     adapter.Name,
		"action":      "delete",
		"app":         r.PathValue("app"),
		"environment": r.PathValue("environment"),
	}
	plan := adapter.planEnvironment(request)
	writeJSON(w, http.StatusOK, s.workflowResponse("environment.delete", adapter.Name, plan, request))
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
	request, err := decodeObject(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	runtime := defaultString(request["runtime"], "kind")
	adapter, err := adapterFor(runtime)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	plan := adapter.planDeployment(request)
	if rollback {
		plan["summary"] = fmt.Sprintf("would roll back %s/%s on %s", stringValue(request["app"]), stringValue(request["environment"]), adapter.Name)
	}
	writeJSON(w, http.StatusOK, s.workflowResponse(action, adapter.Name, plan, request))
}

func (s *Server) scaffoldApp(w http.ResponseWriter, r *http.Request) {
	if !dryRun(r) {
		writeError(w, http.StatusNotImplemented, "apply mode is not implemented")
		return
	}
	request, err := decodeObject(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	runtime := defaultString(request["runtime"], "kind")
	adapter, err := adapterFor(runtime)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	envRequest := map[string]any{"runtime": adapter.Name, "action": "create", "app": request["app"], "environment": "dev"}
	plan := adapter.planEnvironment(envRequest)
	plan["summary"] = fmt.Sprintf("would scaffold app %s for %s on %s", stringValue(request["app"]), stringValue(request["owner"]), adapter.Name)
	writeJSON(w, http.StatusOK, s.workflowResponse("app.scaffold", adapter.Name, plan, request))
}

func (s *Server) environmentDryRun(w http.ResponseWriter, r *http.Request) {
	s.workflowDryRun(w, r, "environment", func(adapter runtimeAdapter, request map[string]any) map[string]any {
		return adapter.planEnvironment(request)
	})
}

func (s *Server) deploymentDryRun(w http.ResponseWriter, r *http.Request) {
	s.workflowDryRun(w, r, "deployment", func(adapter runtimeAdapter, request map[string]any) map[string]any {
		return adapter.planDeployment(request)
	})
}

func (s *Server) secretDryRun(w http.ResponseWriter, r *http.Request) {
	s.workflowDryRun(w, r, "secret", func(adapter runtimeAdapter, request map[string]any) map[string]any {
		return adapter.planSecret(request)
	})
}

func (s *Server) workflowDryRun(w http.ResponseWriter, r *http.Request, workflow string, planner func(runtimeAdapter, map[string]any) map[string]any) {
	request, err := decodeObject(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	runtime := defaultString(request["runtime"], "kind")
	adapter, err := adapterFor(runtime)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	plan := planner(adapter, request)
	audit := s.writeAudit(workflow+".dry_run", adapter.Name, workflow, request)
	writeJSON(w, http.StatusOK, map[string]any{
		"dry_run":  true,
		"runtime":  adapter.Name,
		"workflow": workflow,
		"plan":     plan,
		"audit":    audit,
	})
}

func (s *Server) catalog() (map[string]any, error) {
	data, err := os.ReadFile(s.catalogPath)
	if err != nil {
		return nil, err
	}
	var payload map[string]any
	if err := json.Unmarshal(data, &payload); err != nil {
		return nil, err
	}
	return payload, nil
}

func (s *Server) workflowResponse(action, runtime string, plan map[string]any, request map[string]any) map[string]any {
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
			"overall_state":       "unknown",
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
			"overall_state":       "unknown",
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

func writeCORS(w http.ResponseWriter, r *http.Request) {
	origin := r.Header.Get("Origin")
	for _, allowed := range []string{
		"https://portal.127.0.0.1.sslip.io",
		"https://portal-api.127.0.0.1.sslip.io",
		"http://127.0.0.1:5173",
		"http://localhost:5173",
	} {
		if origin == allowed {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			break
		}
	}
	w.Header().Set("Access-Control-Allow-Methods", "*")
	w.Header().Set("Access-Control-Allow-Headers", "*")
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, detail string) {
	writeJSON(w, status, map[string]any{"detail": detail})
}

func decodeObject(r *http.Request) (map[string]any, error) {
	defer r.Body.Close()
	var payload map[string]any
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		return nil, err
	}
	return payload, nil
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

func arrayValue(value any) []any {
	if out, ok := value.([]any); ok {
		return out
	}
	return []any{}
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

func defaultString(value any, fallback string) string {
	if out := stringValue(value); out != "" {
		return out
	}
	return fallback
}

func stringValue(value any) string {
	if out, ok := value.(string); ok {
		return out
	}
	return ""
}

func optionalString(value any) any {
	if out := stringValue(value); out != "" {
		return out
	}
	return nil
}

func firstString(values ...any) any {
	for _, value := range values {
		if out := stringValue(value); out != "" {
			return out
		}
	}
	return nil
}

type runtimeAdapter struct {
	Name        string
	Description string
	Kind        string
	MakeDir     string
	DisplayName string
}

func runtimeInfos() []map[string]string {
	return []map[string]string{
		{"name": "generic_kubernetes", "description": "Generic Kubernetes workflow adapter"},
		{"name": "kind", "description": "Local kind workflow adapter"},
		{"name": "lima", "description": "Local Lima workflow adapter"},
	}
}

func adapterFor(name string) (runtimeAdapter, error) {
	switch name {
	case "generic_kubernetes":
		return runtimeAdapter{Name: name, Description: "Generic Kubernetes workflow adapter", Kind: "generic"}, nil
	case "kind":
		return runtimeAdapter{Name: name, Description: "Local kind workflow adapter", Kind: "make", MakeDir: "kubernetes/kind", DisplayName: "kind"}, nil
	case "lima":
		return runtimeAdapter{Name: name, Description: "Local Lima workflow adapter", Kind: "make", MakeDir: "kubernetes/lima", DisplayName: "lima"}, nil
	default:
		return runtimeAdapter{}, errors.New("unknown runtime: " + name)
	}
}

func (a runtimeAdapter) info() map[string]string {
	return map[string]string{"name": a.Name, "description": a.Description}
}

func (a runtimeAdapter) planEnvironment(request map[string]any) map[string]any {
	app := stringValue(request["app"])
	environment := stringValue(request["environment"])
	action := defaultString(request["action"], "create")
	if a.Kind == "generic" {
		namespace := app + "-" + environment
		verb := "create namespace"
		if action != "create" {
			verb = "delete namespace"
		}
		return plan(a.Name,
			fmt.Sprintf("would %s environment %s for %s on generic Kubernetes", action, environment, app),
			[]string{fmt.Sprintf("kubectl %s %s --dry-run=client -o yaml", verb, namespace)},
			[]string{"Namespace/" + namespace},
		)
	}
	return plan(a.Name,
		fmt.Sprintf("would %s environment %s for %s on %s", action, environment, app, a.DisplayName),
		[]string{fmt.Sprintf("make -C %s idp-env ACTION=%s APP=%s ENV=%s DRY_RUN=1", a.MakeDir, action, app, environment)},
		[]string{fmt.Sprintf("EnvironmentRequest/%s/%s", app, environment)},
	)
}

func (a runtimeAdapter) planDeployment(request map[string]any) map[string]any {
	app := stringValue(request["app"])
	environment := stringValue(request["environment"])
	image := stringValue(request["image"])
	if a.Kind == "generic" {
		namespace := app + "-" + environment
		return plan(a.Name,
			fmt.Sprintf("would deploy %s to %s/%s on generic Kubernetes", image, app, environment),
			[]string{fmt.Sprintf("kubectl set image deployment/%s %s=%s --namespace %s --dry-run=server", app, app, image, namespace)},
			[]string{fmt.Sprintf("Deployment/%s/%s", namespace, app)},
		)
	}
	return plan(a.Name,
		fmt.Sprintf("would deploy %s to %s/%s on %s", image, app, environment, a.DisplayName),
		[]string{fmt.Sprintf("make -C %s idp-deployments APP=%s ENV=%s IMAGE=%s DRY_RUN=1", a.MakeDir, app, environment, image)},
		[]string{fmt.Sprintf("Deployment/%s/%s", app, environment)},
	)
}

func (a runtimeAdapter) planSecret(request map[string]any) map[string]any {
	app := stringValue(request["app"])
	environment := stringValue(request["environment"])
	secret := stringValue(request["secret"])
	keys := stringSlice(request["keys"])
	if a.Kind == "generic" {
		namespace := app + "-" + environment
		var literals []string
		for _, key := range keys {
			literals = append(literals, "--from-literal="+key+"=<redacted>")
		}
		return plan(a.Name,
			fmt.Sprintf("would reconcile secret %s for %s/%s on generic Kubernetes", secret, app, environment),
			[]string{fmt.Sprintf("kubectl create secret generic %s --namespace %s %s --dry-run=client -o yaml", secret, namespace, strings.Join(literals, " "))},
			[]string{fmt.Sprintf("Secret/%s/%s", namespace, secret)},
		)
	}
	return plan(a.Name,
		fmt.Sprintf("would reconcile secret %s for %s/%s on %s", secret, app, environment, a.DisplayName),
		[]string{fmt.Sprintf("make -C %s idp-secrets APP=%s ENV=%s SECRET=%s KEYS=%s DRY_RUN=1", a.MakeDir, app, environment, secret, strings.Join(keys, ","))},
		[]string{fmt.Sprintf("Secret/%s/%s/%s", app, environment, secret)},
	)
}

func plan(runtime, summary string, commands, manifests []string) map[string]any {
	return map[string]any{"dry_run": true, "runtime": runtime, "summary": summary, "commands": commands, "manifests": manifests}
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
	for _, item := range []struct {
		method string
		path   string
	}{
		{"get", "/api/v1/runtimes"},
		{"get", "/api/v1/status"},
		{"post", "/api/v1/environments"},
		{"delete", "/api/v1/environments/{app_name}/{environment}"},
		{"post", "/api/v1/deployments/promote"},
		{"post", "/api/v1/deployments/rollback"},
		{"post", "/api/v1/workflows/secrets/dry-run"},
	} {
		methods := mapValue(paths[item.path])
		methods[item.method] = map[string]any{"operationId": strings.ReplaceAll(strings.Trim(item.path, "/"), "/", "_")}
		paths[item.path] = methods
	}
	return map[string]any{"info": map[string]any{"title": "IDP Core"}, "paths": paths}
}
