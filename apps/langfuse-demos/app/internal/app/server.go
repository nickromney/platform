package app

import (
	"bytes"
	"context"
	"crypto/rand"
	"embed"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"mime"
	"net/http"
	"path"
	"strings"
	"sync/atomic"
	"time"

	"platform.local/idpauth"
)

//go:embed web/*
var web embed.FS

type HTTPDoer interface {
	Do(*http.Request) (*http.Response, error)
}

type server struct {
	cfg    Config
	client HTTPDoer
	m      metrics
}

type metrics struct {
	runs             atomic.Int64
	llmCalls         atomic.Int64
	llmErrors        atomic.Int64
	langfuseBatches  atomic.Int64
	langfuseErrors   atomic.Int64
	runLatencyMillis atomic.Int64
}

type runRequest struct {
	Prompt   string     `json:"prompt"`
	Expected string     `json:"expected"`
	Cases    []evalCase `json:"cases"`
}

type evalCase struct {
	Name     string `json:"name"`
	Prompt   string `json:"prompt"`
	Expected string `json:"expected"`
}

type runResponse struct {
	Role           string      `json:"role"`
	TraceID        string      `json:"traceId"`
	Answer         string      `json:"answer"`
	Steps          []demoStep  `json:"steps"`
	Scores         []demoScore `json:"scores"`
	LLMStatus      string      `json:"llmStatus"`
	LangfuseStatus string      `json:"langfuseStatus"`
	DurationMillis int64       `json:"durationMillis"`
}

type demoStep struct {
	Name     string `json:"name"`
	Type     string `json:"type"`
	Status   string `json:"status"`
	Detail   string `json:"detail"`
	TraceID  string `json:"traceId,omitempty"`
	SpanID   string `json:"spanId,omitempty"`
	ScoreID  string `json:"scoreId,omitempty"`
	Duration int64  `json:"durationMillis,omitempty"`
}

type demoScore struct {
	Name     string  `json:"name"`
	Value    float64 `json:"value"`
	DataType string  `json:"dataType"`
	Comment  string  `json:"comment,omitempty"`
}

type langfuseEvent struct {
	ID        string         `json:"id"`
	Type      string         `json:"type"`
	Timestamp string         `json:"timestamp"`
	Body      map[string]any `json:"body"`
}

type llmMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type llmResult struct {
	Content        string
	Status         string
	Model          string
	StatusCode     int
	DurationMillis int64
	Error          string
}

const defaultOpenAIModel = "Qwen3.5-9B-MLX-4bit"

type roleUI struct {
	ScenarioCopy  string   `json:"scenarioCopy"`
	PromptLabel   string   `json:"promptLabel"`
	ActionLabel   string   `json:"actionLabel"`
	DefaultPrompt string   `json:"defaultPrompt"`
	Capabilities  []string `json:"capabilities"`
}

func NewServer(cfg Config, client HTTPDoer) http.Handler {
	if client == nil {
		client = http.DefaultClient
	}
	s := &server{cfg: cfg, client: client}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.health)
	mux.HandleFunc("GET /favicon.ico", s.noContent)
	mux.HandleFunc("GET /metrics", s.metrics)
	mux.HandleFunc("GET /runtime-config.js", s.runtimeConfig)
	mux.HandleFunc("GET /idpauth.js", idpauth.BrowserBundle)
	mux.HandleFunc("GET /.auth/me", idpauth.WriteClientPrincipalSession)
	mux.HandleFunc("POST /api/run", s.runDemo)
	mux.HandleFunc("/", s.static)
	return logMiddleware(mux)
}

func (s *server) noContent(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":          "ok",
		"service":         "langfuse-demos",
		"role":            s.cfg.Role,
		"dependencies":    "go-plus-shared-idpauth",
		"langfuse_host":   s.cfg.LangfuseHost,
		"openai_base_url": s.cfg.OpenAIBaseURL,
	})
}

func (s *server) metrics(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	role := s.cfg.Role
	fmt.Fprintf(w, "# HELP langfuse_demo_runs_total Demo runs accepted by the app.\n")
	fmt.Fprintf(w, "# TYPE langfuse_demo_runs_total counter\n")
	fmt.Fprintf(w, "langfuse_demo_runs_total{role=%q} %d\n", role, s.m.runs.Load())
	fmt.Fprintf(w, "# HELP langfuse_demo_llm_calls_total LLM chat-completion attempts.\n")
	fmt.Fprintf(w, "# TYPE langfuse_demo_llm_calls_total counter\n")
	fmt.Fprintf(w, "langfuse_demo_llm_calls_total{role=%q} %d\n", role, s.m.llmCalls.Load())
	fmt.Fprintf(w, "# HELP langfuse_demo_llm_errors_total LLM attempts that failed or returned non-2xx.\n")
	fmt.Fprintf(w, "# TYPE langfuse_demo_llm_errors_total counter\n")
	fmt.Fprintf(w, "langfuse_demo_llm_errors_total{role=%q} %d\n", role, s.m.llmErrors.Load())
	fmt.Fprintf(w, "# HELP langfuse_demo_langfuse_batches_total Langfuse ingestion batches sent.\n")
	fmt.Fprintf(w, "# TYPE langfuse_demo_langfuse_batches_total counter\n")
	fmt.Fprintf(w, "langfuse_demo_langfuse_batches_total{role=%q} %d\n", role, s.m.langfuseBatches.Load())
	fmt.Fprintf(w, "# HELP langfuse_demo_langfuse_errors_total Langfuse ingestion batches that failed.\n")
	fmt.Fprintf(w, "# TYPE langfuse_demo_langfuse_errors_total counter\n")
	fmt.Fprintf(w, "langfuse_demo_langfuse_errors_total{role=%q} %d\n", role, s.m.langfuseErrors.Load())
	fmt.Fprintf(w, "# HELP langfuse_demo_run_latency_milliseconds_sum Sum of demo run latency in milliseconds.\n")
	fmt.Fprintf(w, "# TYPE langfuse_demo_run_latency_milliseconds_sum counter\n")
	fmt.Fprintf(w, "langfuse_demo_run_latency_milliseconds_sum{role=%q} %d\n", role, s.m.runLatencyMillis.Load())
}

func (s *server) runtimeConfig(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/javascript")
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate, max-age=0")
	payload := map[string]any{
		"role":            s.cfg.Role,
		"demoName":        s.displayName(),
		"langfuseHost":    s.cfg.LangfuseHost,
		"openaiBaseUrl":   s.cfg.OpenAIBaseURL,
		"openaiModel":     s.cfg.OpenAIModel,
		"publicBaseUrl":   s.cfg.PublicBaseURL,
		"runEndpoint":     "/api/run",
		"metricsEndpoint": "/metrics",
		"hostLLMEndpoint": "http://127.0.0.1:8000/v1",
		"llmPrerequisite": "For live LLM content, start the oMLX OpenAI-compatible server on http://127.0.0.1:8000/v1. In kind, agentgateway forwards pod traffic to host.docker.internal:8000.",
	}
	for key, value := range s.roleUIMap() {
		payload[key] = value
	}
	b, _ := json.Marshal(payload)
	fmt.Fprintf(w, "window.LANGFUSE_DEMO_CONFIG = %s;\n", b)
}

func (s *server) runDemo(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	var req runRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	if strings.TrimSpace(req.Prompt) == "" {
		req.Prompt = s.defaultPrompt()
	}

	var res runResponse
	switch s.cfg.Role {
	case "tool-agent":
		res = s.runToolAgent(r.Context(), req, start)
	case "eval-runner":
		res = s.runEvalRunner(r.Context(), req, start)
	default:
		res = s.runTraceChat(r.Context(), req, start)
	}
	s.m.runs.Add(1)
	s.m.runLatencyMillis.Add(res.DurationMillis)
	writeJSON(w, http.StatusOK, res)
}

func (s *server) runTraceChat(ctx context.Context, req runRequest, started time.Time) runResponse {
	traceID := "lf-chat-" + randomID()
	genID := "gen-" + randomID()
	llmStarted := time.Now()
	llm := s.callLLM(ctx, []llmMessage{
		{Role: "system", Content: "Answer tersely. This is a Langfuse observability demo."},
		{Role: "user", Content: req.Prompt},
	})
	answer := llm.Content
	if answer == "" {
		answer = "LLM call did not return content. Langfuse still receives the failed generation for debugging."
	}
	scores := []demoScore{
		{Name: "llm_available", Value: boolFloat(llm.Status == "ok"), DataType: "BOOLEAN", Comment: llm.Status},
		{Name: "response_length", Value: float64(len(answer)), DataType: "NUMERIC", Comment: "characters"},
	}
	events := []langfuseEvent{
		traceCreate(traceID, "langfuse.trace_chat", req.Prompt, answer, []string{"platform-demo", "trace-chat"}),
		generationCreate(genID, traceID, "chat-completion", llm.Model, req.Prompt, answer, llmStarted, time.Now(), llm.Status, llm.StatusCode),
	}
	events = append(events, scoreEvents(traceID, genID, scores)...)
	langfuseStatus := s.ingest(ctx, events)
	return runResponse{
		Role:           s.cfg.Role,
		TraceID:        traceID,
		Answer:         answer,
		Steps:          []demoStep{{Name: "chat-completion", Type: "generation", Status: llm.Status, Detail: llm.Model, TraceID: traceID, SpanID: genID, Duration: llm.DurationMillis}},
		Scores:         scores,
		LLMStatus:      llm.Status,
		LangfuseStatus: langfuseStatus,
		DurationMillis: time.Since(started).Milliseconds(),
	}
}

func (s *server) runToolAgent(ctx context.Context, req runRequest, started time.Time) runResponse {
	traceID := "lf-agent-" + randomID()
	planID := "gen-" + randomID()
	toolPolicyID := "span-" + randomID()
	toolMemoryID := "span-" + randomID()
	finalID := "gen-" + randomID()

	planStarted := time.Now()
	plan := s.callLLM(ctx, []llmMessage{
		{Role: "system", Content: "Plan one or two tool calls. Return a compact plan."},
		{Role: "user", Content: req.Prompt},
	})
	planText := firstNonEmpty(plan.Content, "Deterministic plan: run policy_check and memory_lookup, then answer.")
	policyDetail := "prompt_present=true; langfuse_configured=" + fmt.Sprint(s.langfuseConfigured())
	memoryDetail := "memory_lookup=local-platform-stage-920-langfuse"
	finalPrompt := fmt.Sprintf("User prompt: %s\nPlan: %s\nTool results: %s; %s", req.Prompt, planText, policyDetail, memoryDetail)
	finalStarted := time.Now()
	final := s.callLLM(ctx, []llmMessage{
		{Role: "system", Content: "Use tool results and produce a concise agent answer."},
		{Role: "user", Content: finalPrompt},
	})
	answer := firstNonEmpty(final.Content, fmt.Sprintf(
		"Agent completed with deterministic tool evidence: policy_check passed, memory_lookup returned %s. Langfuse receives the planner attempt, tool spans, final generation attempt, and scores.",
		strings.TrimPrefix(memoryDetail, "memory_lookup="),
	))
	planDisplayStatus := llmDisplayStatus(plan)
	finalDisplayStatus := llmDisplayStatus(final)
	toolSuccess := 1.0
	if strings.TrimSpace(req.Prompt) == "" || !s.langfuseConfigured() {
		toolSuccess = 0.5
	}
	scores := []demoScore{
		{Name: "tool_success_rate", Value: toolSuccess, DataType: "NUMERIC", Comment: "local deterministic tool checks"},
		{Name: "guardrail_passed", Value: boolFloat(!strings.Contains(strings.ToLower(req.Prompt), "secret")), DataType: "BOOLEAN", Comment: "simple prompt guardrail"},
	}
	events := []langfuseEvent{
		traceCreate(traceID, "langfuse.tool_agent", req.Prompt, answer, []string{"platform-demo", "tool-agent"}),
		generationCreate(planID, traceID, "planner", plan.Model, req.Prompt, planText, planStarted, time.Now(), plan.Status, plan.StatusCode),
		spanCreate(toolPolicyID, traceID, "policy_check", req.Prompt, policyDetail, "ok"),
		spanCreate(toolMemoryID, traceID, "memory_lookup", req.Prompt, memoryDetail, "ok"),
		generationCreate(finalID, traceID, "final-response", final.Model, finalPrompt, answer, finalStarted, time.Now(), final.Status, final.StatusCode),
	}
	events = append(events, scoreEvents(traceID, finalID, scores)...)
	langfuseStatus := s.ingest(ctx, events)
	return runResponse{
		Role:    s.cfg.Role,
		TraceID: traceID,
		Answer:  answer,
		Steps: []demoStep{
			{Name: "planner", Type: "generation", Status: planDisplayStatus, Detail: truncate(planText, 120), TraceID: traceID, SpanID: planID, Duration: plan.DurationMillis},
			{Name: "policy_check", Type: "tool", Status: "ok", Detail: policyDetail, TraceID: traceID, SpanID: toolPolicyID},
			{Name: "memory_lookup", Type: "tool", Status: "ok", Detail: memoryDetail, TraceID: traceID, SpanID: toolMemoryID},
			{Name: "final-response", Type: "generation", Status: finalDisplayStatus, Detail: firstNonEmpty(final.Content, "deterministic synthesis"), TraceID: traceID, SpanID: finalID, Duration: final.DurationMillis},
		},
		Scores:         scores,
		LLMStatus:      joinAgentStatuses(planDisplayStatus, finalDisplayStatus),
		LangfuseStatus: langfuseStatus,
		DurationMillis: time.Since(started).Milliseconds(),
	}
}

func (s *server) runEvalRunner(ctx context.Context, req runRequest, started time.Time) runResponse {
	traceID := "lf-eval-" + randomID()
	cases := req.Cases
	if len(cases) == 0 {
		cases = []evalCase{
			{Name: "grounded", Prompt: "Name the observability product in this demo.", Expected: "Langfuse"},
			{Name: "tool-aware", Prompt: "Which agent step should be inspected for tool failures?", Expected: "tool"},
			{Name: "route-aware", Prompt: "Where are demo traces written?", Expected: "trace"},
		}
	}
	events := []langfuseEvent{traceCreate(traceID, "langfuse.eval_runner", map[string]any{"cases": cases}, nil, []string{"platform-demo", "eval-runner"})}
	steps := make([]demoStep, 0, len(cases))
	scores := make([]demoScore, 0, len(cases)+1)
	var total float64
	var answerParts []string
	for _, tc := range cases {
		caseID := "gen-" + randomID()
		caseStarted := time.Now()
		llm := s.callLLM(ctx, []llmMessage{
			{Role: "system", Content: "Answer for an evaluation harness. Keep it one sentence."},
			{Role: "user", Content: tc.Prompt},
		})
		output := firstNonEmpty(llm.Content, "Langfuse trace and score replay fallback output.")
		scoreValue := boolFloat(strings.Contains(strings.ToLower(output), strings.ToLower(tc.Expected)))
		total += scoreValue
		score := demoScore{Name: "expected_keyword_match", Value: scoreValue, DataType: "BOOLEAN", Comment: tc.Name + " expects " + tc.Expected}
		scores = append(scores, score)
		answerParts = append(answerParts, fmt.Sprintf("%s=%0.0f", tc.Name, scoreValue))
		events = append(events,
			generationCreate(caseID, traceID, "eval-case-"+tc.Name, llm.Model, tc.Prompt, output, caseStarted, time.Now(), llm.Status, llm.StatusCode),
		)
		events = append(events, scoreEvents(traceID, caseID, []demoScore{score})...)
		steps = append(steps, demoStep{Name: tc.Name, Type: "eval-case", Status: llm.Status, Detail: "expected=" + tc.Expected, TraceID: traceID, SpanID: caseID, Duration: llm.DurationMillis})
	}
	average := 0.0
	if len(cases) > 0 {
		average = total / float64(len(cases))
	}
	overall := demoScore{Name: "eval_average", Value: average, DataType: "NUMERIC", Comment: "mean expected keyword match"}
	scores = append(scores, overall)
	events = append(events, scoreEvents(traceID, "", []demoScore{overall})...)
	answer := "Eval run complete: " + strings.Join(answerParts, ", ")
	langfuseStatus := s.ingest(ctx, events)
	return runResponse{
		Role:           s.cfg.Role,
		TraceID:        traceID,
		Answer:         answer,
		Steps:          steps,
		Scores:         scores,
		LLMStatus:      "evaluated",
		LangfuseStatus: langfuseStatus,
		DurationMillis: time.Since(started).Milliseconds(),
	}
}

func (s *server) callLLM(ctx context.Context, messages []llmMessage) llmResult {
	start := time.Now()
	s.m.llmCalls.Add(1)
	callCtx, cancel := context.WithTimeout(ctx, positiveDuration(s.cfg.LLMTimeout, 5*time.Second))
	defer cancel()
	model := s.resolveOpenAIModel(callCtx)
	payload := map[string]any{
		"model":       model,
		"messages":    messages,
		"temperature": 0.2,
		"stream":      false,
	}
	body, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(callCtx, http.MethodPost, s.cfg.OpenAIBaseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		s.m.llmErrors.Add(1)
		return llmResult{Status: "error", Model: model, Error: err.Error(), DurationMillis: time.Since(start).Milliseconds()}
	}
	req.Header.Set("Content-Type", "application/json")
	if s.cfg.OpenAIAPIKey != "" {
		req.Header.Set("Authorization", "Bearer "+s.cfg.OpenAIAPIKey)
	}
	resp, err := s.client.Do(req)
	if err != nil {
		s.m.llmErrors.Add(1)
		return llmResult{Status: "error", Model: model, Error: err.Error(), DurationMillis: time.Since(start).Milliseconds()}
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	result := llmResult{Model: model, StatusCode: resp.StatusCode, DurationMillis: time.Since(start).Milliseconds()}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		s.m.llmErrors.Add(1)
		result.Status = "http_error"
		result.Error = strings.TrimSpace(string(raw))
		return result
	}
	var parsed struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(raw, &parsed); err != nil {
		s.m.llmErrors.Add(1)
		result.Status = "parse_error"
		result.Error = err.Error()
		return result
	}
	if len(parsed.Choices) == 0 {
		s.m.llmErrors.Add(1)
		result.Status = "empty"
		return result
	}
	result.Status = "ok"
	result.Content = strings.TrimSpace(parsed.Choices[0].Message.Content)
	return result
}

func (s *server) resolveOpenAIModel(ctx context.Context) string {
	configured := strings.TrimSpace(s.cfg.OpenAIModel)
	if configured != "" && configured != "auto" && configured != "local-omlx" {
		return configured
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, s.cfg.OpenAIBaseURL+"/models", nil)
	if err != nil {
		return defaultOpenAIModel
	}
	if s.cfg.OpenAIAPIKey != "" {
		req.Header.Set("Authorization", "Bearer "+s.cfg.OpenAIAPIKey)
	}
	resp, err := s.client.Do(req)
	if err != nil {
		return defaultOpenAIModel
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return defaultOpenAIModel
	}
	var parsed struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&parsed); err != nil {
		return defaultOpenAIModel
	}
	for _, model := range parsed.Data {
		if strings.TrimSpace(model.ID) != "" {
			return strings.TrimSpace(model.ID)
		}
	}
	return defaultOpenAIModel
}

func (s *server) ingest(ctx context.Context, events []langfuseEvent) string {
	if !s.langfuseConfigured() {
		return "disabled"
	}
	s.m.langfuseBatches.Add(1)
	callCtx, cancel := context.WithTimeout(ctx, positiveDuration(s.cfg.LangfuseTimeout, 5*time.Second))
	defer cancel()
	payload, _ := json.Marshal(map[string]any{"batch": events})
	req, err := http.NewRequestWithContext(callCtx, http.MethodPost, s.cfg.LangfuseHost+"/api/public/ingestion", bytes.NewReader(payload))
	if err != nil {
		s.m.langfuseErrors.Add(1)
		return "error: " + err.Error()
	}
	req.Header.Set("Content-Type", "application/json")
	req.SetBasicAuth(s.cfg.LangfusePublicKey, s.cfg.LangfuseSecretKey)
	resp, err := s.client.Do(req)
	if err != nil {
		s.m.langfuseErrors.Add(1)
		return "error: " + err.Error()
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		s.m.langfuseErrors.Add(1)
		return fmt.Sprintf("http_%d: %s", resp.StatusCode, truncate(string(raw), 180))
	}
	return "ok"
}

func positiveDuration(value, fallback time.Duration) time.Duration {
	if value > 0 {
		return value
	}
	return fallback
}

func traceCreate(traceID, name string, input, output any, tags []string) langfuseEvent {
	return langfuseEvent{
		ID:        traceID + "-trace",
		Type:      "trace-create",
		Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
		Body: map[string]any{
			"id":        traceID,
			"name":      name,
			"input":     input,
			"output":    output,
			"tags":      tags,
			"sessionId": "platform-langfuse-demos",
			"userId":    "platform-demo-user",
			"metadata": map[string]any{
				"source": "platform-langfuse-demos",
			},
		},
	}
}

func generationCreate(id, traceID, name, model string, input, output any, start, end time.Time, status string, statusCode int) langfuseEvent {
	return langfuseEvent{
		ID:        id + "-create",
		Type:      "generation-create",
		Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
		Body: map[string]any{
			"id":        id,
			"traceId":   traceID,
			"name":      name,
			"model":     model,
			"input":     input,
			"output":    output,
			"startTime": start.UTC().Format(time.RFC3339Nano),
			"endTime":   end.UTC().Format(time.RFC3339Nano),
			"metadata": map[string]any{
				"status":      status,
				"http_status": statusCode,
			},
		},
	}
}

func spanCreate(id, traceID, name string, input, output any, status string) langfuseEvent {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	return langfuseEvent{
		ID:        id + "-create",
		Type:      "span-create",
		Timestamp: now,
		Body: map[string]any{
			"id":        id,
			"traceId":   traceID,
			"name":      name,
			"input":     input,
			"output":    output,
			"startTime": now,
			"endTime":   now,
			"metadata":  map[string]any{"status": status},
		},
	}
}

func scoreEvents(traceID, observationID string, scores []demoScore) []langfuseEvent {
	events := make([]langfuseEvent, 0, len(scores))
	for _, score := range scores {
		body := map[string]any{
			"id":       "score-" + randomID(),
			"traceId":  traceID,
			"name":     score.Name,
			"value":    score.Value,
			"dataType": score.DataType,
			"comment":  score.Comment,
		}
		if observationID != "" {
			body["observationId"] = observationID
		}
		events = append(events, langfuseEvent{
			ID:        body["id"].(string) + "-create",
			Type:      "score-create",
			Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
			Body:      body,
		})
	}
	return events
}

func (s *server) static(w http.ResponseWriter, r *http.Request) {
	name := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
	if name == "." || name == "" {
		name = "index.html"
	}
	name = "web/" + name
	b, err := web.ReadFile(name)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate, max-age=0")
	if ct := mime.TypeByExtension(path.Ext(name)); ct != "" {
		w.Header().Set("Content-Type", ct)
	}
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(b)
}

func (s *server) displayName() string {
	switch s.cfg.Role {
	case "tool-agent":
		return "Langfuse Tool Agent"
	case "eval-runner":
		return "Langfuse Eval Runner"
	default:
		return "Langfuse Trace Chat"
	}
}

func (s *server) defaultPrompt() string {
	switch s.cfg.Role {
	case "tool-agent":
		return "Use tools to decide whether this platform has Langfuse tracing wired correctly."
	case "eval-runner":
		return "Run the default regression eval set."
	default:
		return "Explain what this Langfuse trace should show in one sentence."
	}
}

func (s *server) roleUIMap() map[string]any {
	ui := s.roleUI()
	return map[string]any{
		"scenarioCopy":  ui.ScenarioCopy,
		"promptLabel":   ui.PromptLabel,
		"actionLabel":   ui.ActionLabel,
		"defaultPrompt": ui.DefaultPrompt,
		"capabilities":  ui.Capabilities,
	}
}

func (s *server) roleUI() roleUI {
	switch s.cfg.Role {
	case "tool-agent":
		return roleUI{
			ScenarioCopy:  "Planner, deterministic tools, final synthesis, spans, generations, and guardrail scores in one agent trace.",
			PromptLabel:   "Agent task",
			ActionLabel:   "Run Agent",
			DefaultPrompt: s.defaultPrompt(),
			Capabilities:  []string{"Planner generation", "Policy check tool span", "Memory lookup tool span", "Final synthesis score"},
		}
	case "eval-runner":
		return roleUI{
			ScenarioCopy:  "Eval cases replay model calls and attach per-case scores plus an aggregate score to the trace.",
			PromptLabel:   "Eval instruction",
			ActionLabel:   "Run Evals",
			DefaultPrompt: s.defaultPrompt(),
			Capabilities:  []string{"Case generations", "Keyword scoring", "Aggregate eval score", "Replay-ready traces"},
		}
	default:
		return roleUI{
			ScenarioCopy:  "Single prompt to one generation with response quality scores for inspecting the basic LLM trace path.",
			PromptLabel:   "Chat prompt",
			ActionLabel:   "Run Chat Trace",
			DefaultPrompt: s.defaultPrompt(),
			Capabilities:  []string{"Trace create", "Generation create", "Availability score", "Response length score"},
		}
	}
}

func (s *server) langfuseConfigured() bool {
	return s.cfg.LangfuseHost != "" && s.cfg.LangfusePublicKey != "" && s.cfg.LangfuseSecretKey != ""
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func decodeJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	defer r.Body.Close()
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(v); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return false
	}
	return true
}

func logMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		next.ServeHTTP(w, r)
	})
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func boolFloat(ok bool) float64 {
	if ok {
		return 1
	}
	return 0
}

func joinStatuses(values ...string) string {
	seen := map[string]bool{}
	var out []string
	for _, value := range values {
		if value == "" || seen[value] {
			continue
		}
		seen[value] = true
		out = append(out, value)
	}
	if len(out) == 0 {
		return "unknown"
	}
	return strings.Join(out, ",")
}

func joinAgentStatuses(values ...string) string {
	for _, value := range values {
		if value == "deterministic fallback" {
			return "deterministic fallback"
		}
	}
	return joinStatuses(values...)
}

func llmDisplayStatus(result llmResult) string {
	if result.Status == "ok" {
		return "ok"
	}
	if strings.TrimSpace(result.Content) == "" {
		return "deterministic fallback"
	}
	return result.Status
}

func truncate(value string, max int) string {
	value = strings.TrimSpace(value)
	if len(value) <= max {
		return value
	}
	if max <= 3 {
		return value[:max]
	}
	return value[:max-3] + "..."
}

func randomID() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(b[:])
}
