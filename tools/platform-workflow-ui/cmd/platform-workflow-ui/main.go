package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"html"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type optionsPayload struct {
	Variants       []variantOption `json:"variants"`
	Stages         []stageOption   `json:"stages"`
	ActionMetadata []actionOption  `json:"action_metadata"`
	Apps           []string        `json:"apps"`
	AppMetadata    []labelOption   `json:"app_metadata"`
	PresetGroups   []presetGroup   `json:"preset_groups"`
	Presets        []presetOption  `json:"presets"`
	UIRules        map[string]any  `json:"ui_rules"`
	Raw            map[string]any  `json:"-"`
}

type variantOption struct {
	ID                string `json:"id"`
	Path              string `json:"path"`
	Label             string `json:"label"`
	GuidedLabel       string `json:"guided_label"`
	GuidedDescription string `json:"guided_description"`
}

type stageOption struct {
	ID                string `json:"id"`
	Label             string `json:"label"`
	GuidedDescription string `json:"guided_description"`
	AppToggles        bool   `json:"app_toggles"`
}

type actionOption struct {
	ID              string `json:"id"`
	Label           string `json:"label"`
	UsesAutoApprove bool   `json:"uses_auto_approve"`
}

type labelOption struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

type presetGroup struct {
	ID      string   `json:"id"`
	Label   string   `json:"label"`
	Presets []string `json:"presets"`
}

type presetOption struct {
	Group   string         `json:"group"`
	ID      string         `json:"id"`
	Label   string         `json:"label"`
	Overlay map[string]any `json:"overlay"`
}

type workflowSelection struct {
	Variant         string
	Stage           string
	Action          string
	Apps            map[string]string
	Presets         map[string]string
	CustomOverrides map[string]string
	AutoApprove     bool
	Command         string
	DryRun          bool
	Source          string
}

type server struct {
	repoRoot string
	options  optionsPayload
	csrf     string
	jobs     *jobStore
	history  *historyStore
}

type jobStore struct {
	mu   sync.Mutex
	jobs map[string]*workflowJob
}

type workflowJob struct {
	ID         string
	Payload    workflowSelection
	Command    []string
	Output     []string
	ReturnCode *int
	StartedAt  time.Time
	FinishedAt *time.Time
}

type historyStore struct {
	mu    sync.Mutex
	limit int
	items []historyItem
}

type historyItem struct {
	ID         string
	Command    string
	Kind       string
	Variant    string
	ExitStatus string
	Timestamp  string
	Output     string
}

func main() {
	host := flag.String("host", "console.127.0.0.1.sslip.io", "listen host")
	port := flag.String("port", "8443", "listen port")
	httpMode := flag.String("http", "h2", "http1 or h2")
	certFile := flag.String("tls-cert-file", "", "TLS certificate file")
	keyFile := flag.String("tls-key-file", "", "TLS key file")
	repoRoot := flag.String("repo-root", "", "repository root")
	flag.Parse()

	root := *repoRoot
	if root == "" {
		root = os.Getenv("PLATFORM_REPO_ROOT")
	}
	if root == "" {
		wd, err := os.Getwd()
		if err != nil {
			log.Fatal(err)
		}
		root = filepath.Clean(filepath.Join(wd, "..", ".."))
	}

	options, err := loadOptions(root)
	if err != nil {
		log.Fatal(err)
	}

	app := &server{
		repoRoot: root,
		options:  options,
		csrf:     randomToken(),
		jobs:     &jobStore{jobs: map[string]*workflowJob{}},
		history:  &historyStore{limit: 5},
	}
	mux := http.NewServeMux()
	app.routes(mux)

	address := *host + ":" + *port
	log.Printf("Open %s://%s", scheme(*httpMode), address)
	if *httpMode == "http1" {
		log.Fatal(http.ListenAndServe(address, mux))
	}
	if *certFile == "" || *keyFile == "" {
		log.Fatal("--tls-cert-file and --tls-key-file are required for --http h2")
	}
	log.Fatal(http.ListenAndServeTLS(address, *certFile, *keyFile, mux))
}

func (s *server) routes(mux *http.ServeMux) {
	static := os.DirFS(filepath.Join(s.repoRoot, "tools", "platform-workflow-ui", "static"))
	mux.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.FS(static))))
	mux.HandleFunc("/health", s.health)
	mux.HandleFunc("/favicon.ico", s.favicon)
	mux.HandleFunc("/api/options", s.apiOptions)
	mux.HandleFunc("/preview", s.preview)
	mux.HandleFunc("/run", s.run)
	mux.HandleFunc("/inventory", s.inventory)
	mux.HandleFunc("/next", s.next)
	mux.HandleFunc("/jobs/", s.jobStatus)
	mux.HandleFunc("/", s.index)
}

func (s *server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, map[string]string{"status": "ok", "service": "platform-workflow-ui"})
}

func (s *server) favicon(w http.ResponseWriter, r *http.Request) {
	path := filepath.Join(s.repoRoot, "sites", "docs", "app", "favicon.ico")
	http.ServeFile(w, r, path)
}

func (s *server) apiOptions(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, s.options.Raw)
}

func (s *server) index(w http.ResponseWriter, _ *http.Request) {
	writeHTML(w, s.page())
}

func (s *server) preview(w http.ResponseWriter, r *http.Request) {
	selection, ok := s.verifiedSelection(w, r)
	if !ok {
		return
	}
	result, err := s.previewResult(r.Context(), selection)
	if err != nil {
		writeHTML(w, `<div class="preview-error"><div class="notice error">Preview failed</div><pre class="output preview-error-output">`+html.EscapeString(err.Error())+`</pre></div>`)
		return
	}
	writeHTML(w, s.previewPanel(result, selection)+s.latestOutputPanel())
}

func (s *server) run(w http.ResponseWriter, r *http.Request) {
	selection, ok := s.verifiedSelection(w, r)
	if !ok {
		return
	}
	if selection.Command == "" {
		result, err := s.previewResult(r.Context(), selection)
		if err != nil {
			writeHTML(w, `<div class="notice error">Preview failed</div><pre class="output">`+html.EscapeString(err.Error())+`</pre>`)
			return
		}
		selection.Command = result["command"]
	}
	historyID := s.history.add(selection.Command, actionLabel(s.options, selection.Action), selection.Variant)
	job := s.jobs.start(s.repoRoot, selection, historyID, s.history)
	writeHTML(w, s.jobFragment(job))
}

func (s *server) jobStatus(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/jobs/")
	job := s.jobs.get(id)
	if job == nil {
		http.Error(w, "job not found", http.StatusNotFound)
		return
	}
	writeHTML(w, s.jobFragment(job))
}

func (s *server) inventory(w http.ResponseWriter, r *http.Request) {
	variant := first(r.URL.Query().Get("variant"), "kubernetes/kind")
	stage := first(r.URL.Query().Get("stage"), "900")
	args := []string{
		filepath.Join(s.repoRoot, "scripts", "platform-inventory.sh"),
		"--execute",
		"--variant", variantToTarget(s.options, variant),
		"--stage", stage,
		"--output", "json",
	}
	result := runCommand(r.Context(), s.repoRoot, args)
	if result.err != nil || result.code != 0 {
		writeHTML(w, `<section class="inventory"><div class="notice error">Inventory unavailable</div><pre class="output">`+html.EscapeString(result.output())+`</pre></section>`)
		return
	}
	writeHTML(w, `<section class="inventory"><h2>Inventory</h2><pre class="output">`+html.EscapeString(result.stdout)+`</pre></section>`)
}

func (s *server) next(w http.ResponseWriter, r *http.Request) {
	selection, ok := s.verifiedSelection(w, r)
	if !ok {
		return
	}
	result, err := s.previewResult(r.Context(), selection)
	if err != nil {
		writeHTML(w, `<div class="notice error">Preview failed</div><pre class="output">`+html.EscapeString(err.Error())+`</pre>`)
		return
	}
	writeHTML(w, s.previewPanel(result, selection))
}

func (s *server) verifiedSelection(w http.ResponseWriter, r *http.Request) (workflowSelection, bool) {
	if err := r.ParseMultipartForm(1 << 20); err != nil {
		if err := r.ParseForm(); err != nil {
			http.Error(w, "invalid form", http.StatusBadRequest)
			return workflowSelection{}, false
		}
	}
	supplied := first(r.Form.Get("csrf_token"), r.Header.Get("x-csrf-token"))
	if supplied == "" || supplied != s.csrf {
		http.Error(w, "invalid CSRF token", http.StatusForbidden)
		return workflowSelection{}, false
	}
	return selectionFromForm(s.options, r), true
}

func (s *server) previewResult(ctx context.Context, selection workflowSelection) (map[string]string, error) {
	args := append([]string{filepath.Join(s.repoRoot, "scripts", "platform-workflow.sh")}, workflowArgs(s.options, selection, "preview", "--execute")...)
	args = append(args, "--output", "json")
	result := runCommand(ctx, s.repoRoot, args)
	if result.err != nil {
		return nil, result.err
	}
	if result.code != 0 {
		return nil, errors.New(strings.TrimSpace(result.output()))
	}
	parsed := map[string]any{}
	if err := json.Unmarshal([]byte(result.stdout), &parsed); err != nil {
		return map[string]string{"command": strings.TrimSpace(result.stdout)}, nil
	}
	out := map[string]string{}
	for _, key := range []string{"command", "summary", "target", "stage", "action"} {
		if value, ok := parsed[key].(string); ok {
			out[key] = value
		}
	}
	if out["command"] == "" {
		out["command"] = strings.TrimSpace(result.stdout)
	}
	return out, nil
}

func (s *server) page() string {
	return `<!doctype html>
<html lang="en" data-theme="dark">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Platform Workflow UI</title>
  <script src="/static/htmx.min.js"></script>
  <style>` + pageCSS() + `</style>
</head>
<body>
  <main>
    <header>
      <div>
        <p class="eyebrow">Local platform workflow</p>
        <h1>Platform Workflow UI</h1>
      </div>
      <button type="button" id="theme-toggle" onclick="toggleTheme()">Theme</button>
    </header>
    <form id="workflow-form" hx-post="/preview" hx-target="#preview" hx-swap="innerHTML">
      <input type="hidden" name="csrf_token" value="` + html.EscapeString(s.csrf) + `">
      <section class="card grid">
        <div class="field"><label for="variant">Target</label>` + s.variantSelect() + `</div>
        <div class="field"><label for="stage">Stage</label>` + s.stageSelect() + `</div>
        <div class="field"><label for="action">Action</label>` + s.actionSelect() + `</div>
        <label class="check"><input type="checkbox" name="auto_approve" value="on"> Auto approve</label>
        <label class="check"><input type="checkbox" name="dry_run" value="on"> Dry run command execution</label>
        <div class="actions">
          <button type="submit">Preview</button>
          <button type="button" hx-post="/run" hx-include="#workflow-form" hx-target="#job" hx-swap="innerHTML">Run</button>
          <button type="button" hx-get="/inventory" hx-include="#workflow-form" hx-target="#inventory" hx-swap="innerHTML">Inventory</button>
        </div>
      </section>
    </form>
    <section id="preview" class="slot"></section>
    <section id="job" class="slot"></section>
    <section id="inventory" class="slot"></section>
  </main>
  <script>
    function toggleTheme() {
      const root = document.documentElement;
      const next = root.dataset.theme === "dark" ? "light" : "dark";
      root.dataset.theme = next;
      localStorage.setItem("platform-workflow-ui-theme", next);
    }
    try { document.documentElement.dataset.theme = localStorage.getItem("platform-workflow-ui-theme") || "dark"; } catch (_) {}
  </script>
</body>
</html>`
}

func (s *server) variantSelect() string {
	var b strings.Builder
	b.WriteString(`<select id="variant" name="variant">`)
	for _, variant := range s.options.Variants {
		path := first(variant.Path, variant.ID)
		label := first(variant.GuidedLabel, variant.Label, path)
		selected := ""
		if path == "kubernetes/kind" {
			selected = ` selected`
		}
		fmt.Fprintf(&b, `<option value="%s"%s>%s</option>`, html.EscapeString(path), selected, html.EscapeString(label))
	}
	b.WriteString(`</select>`)
	return b.String()
}

func (s *server) stageSelect() string {
	var b strings.Builder
	b.WriteString(`<select id="stage" name="stage">`)
	for _, stage := range s.options.Stages {
		selected := ""
		if stage.ID == "900" {
			selected = ` selected`
		}
		fmt.Fprintf(&b, `<option value="%s"%s>%s</option>`, html.EscapeString(stage.ID), selected, html.EscapeString(first(stage.Label, stage.ID)))
	}
	b.WriteString(`</select>`)
	return b.String()
}

func (s *server) actionSelect() string {
	var b strings.Builder
	b.WriteString(`<select id="action" name="action">`)
	for _, action := range s.options.ActionMetadata {
		if action.ID == "reset" {
			continue
		}
		selected := ""
		if action.ID == "apply" {
			selected = ` selected`
		}
		fmt.Fprintf(&b, `<option value="%s"%s>%s</option>`, html.EscapeString(action.ID), selected, html.EscapeString(first(action.Label, action.ID)))
	}
	b.WriteString(`</select>`)
	return b.String()
}

func (s *server) previewPanel(result map[string]string, selection workflowSelection) string {
	return `<section class="card"><h2>Preview</h2><dl>` +
		dtdd("Target", first(result["target"], selection.Variant)) +
		dtdd("Stage", first(result["stage"], selection.Stage)) +
		dtdd("Action", first(result["action"], selection.Action)) +
		`</dl><pre class="output">` + html.EscapeString(result["command"]) + `</pre></section>`
}

func (s *server) latestOutputPanel() string {
	items := s.history.snapshot()
	if len(items) == 0 {
		return ""
	}
	item := items[0]
	return `<section class="card"><h2>Latest command</h2><p>` + html.EscapeString(item.Kind) + ` on ` + html.EscapeString(item.Variant) + `</p><pre class="output">` + html.EscapeString(item.Command) + `</pre></section>`
}

func (s *server) jobFragment(job *workflowJob) string {
	status := "running"
	poll := fmt.Sprintf(` hx-get="/jobs/%s" hx-trigger="every 2s" hx-swap="outerHTML"`, html.EscapeString(job.ID))
	if job.ReturnCode != nil {
		status = fmt.Sprintf("exit %d", *job.ReturnCode)
		poll = ""
	}
	return fmt.Sprintf(`<section id="job-panel" class="card"%s><h2>Run %s</h2><pre class="output">%s</pre></section>`, poll, html.EscapeString(status), html.EscapeString(strings.Join(job.Output, "\n")))
}

func selectionFromForm(options optionsPayload, r *http.Request) workflowSelection {
	action := first(r.Form.Get("action"), "apply")
	selection := workflowSelection{
		Variant:         first(r.Form.Get("variant"), "kubernetes/kind"),
		Stage:           first(r.Form.Get("stage"), "900"),
		Action:          action,
		Apps:            map[string]string{},
		Presets:         map[string]string{},
		CustomOverrides: map[string]string{},
		AutoApprove:     truthy(r.Form.Get("auto_approve")) || actionUsesAutoApprove(options, action),
		Command:         r.Form.Get("command"),
		DryRun:          truthy(r.Form.Get("dry_run")),
		Source:          first(r.Form.Get("source"), "dropdowns"),
	}
	for _, app := range options.Apps {
		selection.Apps[app] = r.Form.Get(app)
	}
	for _, group := range options.PresetGroups {
		selection.Presets["preset_"+group.ID] = first(r.Form.Get("preset_"+group.ID), "default")
	}
	for _, field := range []string{"custom_worker_count", "custom_node_image", "custom_enable_backstage"} {
		selection.CustomOverrides[field] = r.Form.Get(field)
	}
	return selection
}

func workflowArgs(options optionsPayload, selection workflowSelection, subcommand, standardFlag string) []string {
	args := []string{subcommand, standardFlag, "--variant", variantToTarget(options, selection.Variant), "--stage", selection.Stage, "--action", selection.Action}
	for field, value := range selection.Presets {
		if value == "" || value == "default" {
			continue
		}
		args = append(args, "--preset", strings.TrimPrefix(field, "preset_")+"="+value)
	}
	customMap := map[string]string{
		"custom_worker_count":     "worker_count",
		"custom_node_image":       "node_image",
		"custom_enable_backstage": "enable_backstage",
	}
	for field, option := range customMap {
		if value := selection.CustomOverrides[field]; value != "" {
			args = append(args, "--set", option+"="+value)
		}
	}
	for _, app := range options.Apps {
		if value := selection.Apps[app]; value != "" && value != "on" {
			args = append(args, "--app", app+"="+value)
		}
	}
	if selection.AutoApprove && actionUsesAutoApprove(options, selection.Action) {
		args = append(args, "--auto-approve")
	}
	return args
}

func loadOptions(repoRoot string) (optionsPayload, error) {
	data, err := os.ReadFile(filepath.Join(repoRoot, "kubernetes", "workflow", "options.json"))
	if err != nil {
		return optionsPayload{}, err
	}
	var raw map[string]any
	if err := json.Unmarshal(data, &raw); err != nil {
		return optionsPayload{}, err
	}
	var options optionsPayload
	if err := json.Unmarshal(data, &options); err != nil {
		return optionsPayload{}, err
	}
	options.Raw = raw
	if len(options.Variants) == 0 {
		if rawVariants, ok := raw["variants"].([]any); ok {
			for _, item := range rawVariants {
				if value, ok := item.(map[string]any); ok {
					id, _ := value["id"].(string)
					path, _ := value["path"].(string)
					options.Variants = append(options.Variants, variantOption{ID: id, Path: path})
				}
			}
		}
	}
	return options, nil
}

type commandResult struct {
	code   int
	stdout string
	stderr string
	err    error
}

func runCommand(ctx context.Context, cwd string, args []string) commandResult {
	command := exec.CommandContext(ctx, args[0], args[1:]...)
	command.Dir = cwd
	stdout, err := command.Output()
	result := commandResult{stdout: string(stdout), err: err}
	if exitErr, ok := err.(*exec.ExitError); ok {
		result.code = exitErr.ExitCode()
		result.stderr = string(exitErr.Stderr)
		result.err = nil
	}
	return result
}

func (r commandResult) output() string {
	if strings.TrimSpace(r.stderr) != "" {
		return r.stderr
	}
	if strings.TrimSpace(r.stdout) != "" {
		return r.stdout
	}
	if r.err != nil {
		return r.err.Error()
	}
	return ""
}

func (s *jobStore) start(repoRoot string, selection workflowSelection, historyID string, history *historyStore) *workflowJob {
	id := randomToken()
	standardFlag := "--execute"
	if selection.DryRun {
		standardFlag = "--dry-run"
	}
	command := append([]string{filepath.Join(repoRoot, "scripts", "platform-workflow.sh")}, workflowArgs(loadOptionsMust(repoRoot), selection, selection.Action, standardFlag)...)
	job := &workflowJob{ID: id, Payload: selection, Command: command, StartedAt: time.Now()}
	s.mu.Lock()
	s.jobs[id] = job
	s.mu.Unlock()
	go func() {
		cmd := exec.Command(command[0], command[1:]...)
		cmd.Dir = repoRoot
		output, err := cmd.CombinedOutput()
		code := 0
		if err != nil {
			code = 1
			if exitErr, ok := err.(*exec.ExitError); ok {
				code = exitErr.ExitCode()
			}
		}
		now := time.Now()
		lines := strings.Split(strings.TrimRight(string(output), "\n"), "\n")
		s.mu.Lock()
		job.Output = lines
		job.ReturnCode = &code
		job.FinishedAt = &now
		s.mu.Unlock()
		history.recordExit(historyID, code, string(output))
	}()
	return job
}

func (s *jobStore) get(id string) *workflowJob {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.jobs[id]
}

func (s *historyStore) add(command, kind, variant string) string {
	if strings.TrimSpace(command) == "" {
		return ""
	}
	item := historyItem{ID: randomToken(), Command: command, Kind: kind, Variant: variant, ExitStatus: "running", Timestamp: time.Now().Format("15:04:05")}
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.items) > 0 && s.items[0].Command == command && s.items[0].Kind == kind {
		return s.items[0].ID
	}
	s.items = append([]historyItem{item}, s.items...)
	if len(s.items) > s.limit {
		s.items = s.items[:s.limit]
	}
	return item.ID
}

func (s *historyStore) recordExit(id string, code int, output string) {
	if id == "" {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for index := range s.items {
		if s.items[index].ID == id {
			s.items[index].ExitStatus = fmt.Sprintf("%d", code)
			s.items[index].Output = output
			return
		}
	}
}

func (s *historyStore) snapshot() []historyItem {
	s.mu.Lock()
	defer s.mu.Unlock()
	items := make([]historyItem, len(s.items))
	copy(items, s.items)
	return items
}

func loadOptionsMust(repoRoot string) optionsPayload {
	options, err := loadOptions(repoRoot)
	if err != nil {
		panic(err)
	}
	return options
}

func variantToTarget(options optionsPayload, variant string) string {
	for _, option := range options.Variants {
		if option.Path == variant {
			return first(option.ID, filepath.Base(variant))
		}
	}
	return filepath.Base(variant)
}

func actionUsesAutoApprove(options optionsPayload, action string) bool {
	for _, option := range options.ActionMetadata {
		if option.ID == action {
			return option.UsesAutoApprove
		}
	}
	return action == "apply" || action == "reset" || action == "state-reset"
}

func actionLabel(options optionsPayload, action string) string {
	for _, option := range options.ActionMetadata {
		if option.ID == action {
			return first(option.Label, action)
		}
	}
	return action
}

func first(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func truthy(value string) bool {
	switch strings.ToLower(value) {
	case "1", "true", "on", "yes":
		return true
	default:
		return false
	}
}

func dtdd(term, detail string) string {
	return `<dt>` + html.EscapeString(term) + `</dt><dd>` + html.EscapeString(detail) + `</dd>`
}

func writeHTML(w http.ResponseWriter, text string) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprint(w, text)
}

func writeJSON(w http.ResponseWriter, value any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(value)
}

func randomToken() string {
	var data [16]byte
	if _, err := rand.Read(data[:]); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(data[:])
}

func scheme(mode string) string {
	if mode == "http1" {
		return "http"
	}
	return "https"
}

func pageCSS() string {
	return `
:root { color-scheme: light dark; --bg:#0b0b0c; --panel:#171719; --text:#f5f5f5; --muted:#a1a1aa; --line:rgb(255 255 255 / .12); --accent:#f5f5f5; --accent-text:#18181b; }
:root[data-theme="light"] { color-scheme: light; --bg:#fafafa; --panel:#fff; --text:#18181b; --muted:#52525b; --line:rgb(0 0 0 / .12); --accent:#18181b; --accent-text:#fff; }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--text); font:16px/1.5 system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
main { width:min(1120px, calc(100vw - 32px)); margin:0 auto; padding:32px 0 56px; display:grid; gap:16px; }
header { display:flex; align-items:start; justify-content:space-between; gap:16px; }
h1 { margin:0; font-size:2.2rem; line-height:1.1; letter-spacing:0; }
h2 { margin:0 0 12px; font-size:1rem; }
.eyebrow, p { color:var(--muted); margin:0; }
.card { border:1px solid var(--line); border-radius:12px; background:var(--panel); padding:18px; box-shadow:0 1px 2px rgb(0 0 0 / .08); }
.grid { display:grid; grid-template-columns:repeat(3, minmax(0, 1fr)); gap:14px; align-items:end; }
.field { display:grid; gap:6px; }
label { font-weight:700; font-size:.9rem; }
select, input[type="text"] { width:100%; min-height:38px; border:1px solid var(--line); border-radius:8px; background:rgb(255 255 255 / .05); color:var(--text); padding:8px 10px; font:inherit; }
button { min-height:38px; border:0; border-radius:8px; background:var(--accent); color:var(--accent-text); padding:8px 14px; font:inherit; font-weight:650; cursor:pointer; }
.actions { grid-column:1 / -1; display:flex; flex-wrap:wrap; gap:8px; }
.check { display:flex; align-items:center; gap:8px; font-weight:500; color:var(--muted); }
.slot:empty { display:none; }
dl { display:grid; grid-template-columns:max-content minmax(0, 1fr); gap:6px 12px; }
dt { color:var(--muted); }
dd { margin:0; }
.output { margin:0; white-space:pre-wrap; overflow:auto; max-height:460px; border:1px solid var(--line); border-radius:8px; padding:12px; background:rgb(0 0 0 / .22); color:var(--text); }
.notice.error { color:#fca5a5; }
@media (max-width: 800px) { .grid { grid-template-columns:1fr; } header { flex-direction:column; } }
`
}
