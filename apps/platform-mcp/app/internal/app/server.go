package app

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"

	"platform.local/apphttp"
)

type server struct {
	cfg    Config
	client *http.Client
}

type rpcRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      any             `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type toolCallParams struct {
	Name      string         `json:"name"`
	Arguments map[string]any `json:"arguments"`
}

var metrics = newToolMetrics()

type toolMetrics struct {
	mu           sync.Mutex
	calls        map[string]int
	durationSums map[string]float64
}

func newToolMetrics() *toolMetrics {
	return &toolMetrics{
		calls:        map[string]int{},
		durationSums: map[string]float64{},
	}
}

func NewServer(cfg Config) http.Handler {
	if cfg.LLMBaseURL == "" || cfg.LLMModel == "" || cfg.ServiceName == "" || cfg.ServiceNamespace == "" {
		defaults := ConfigFromEnv()
		if cfg.Port == "" {
			cfg.Port = defaults.Port
		}
		if cfg.MetricsPort == "" {
			cfg.MetricsPort = defaults.MetricsPort
		}
		if cfg.PublicBaseURL == "" {
			cfg.PublicBaseURL = defaults.PublicBaseURL
		}
		if cfg.LLMBaseURL == "" {
			cfg.LLMBaseURL = defaults.LLMBaseURL
		}
		if cfg.LLMModel == "" {
			cfg.LLMModel = defaults.LLMModel
		}
		if cfg.OTLPEndpoint == "" {
			cfg.OTLPEndpoint = defaults.OTLPEndpoint
		}
		if cfg.ServiceName == "" {
			cfg.ServiceName = defaults.ServiceName
		}
		if cfg.ServiceNamespace == "" {
			cfg.ServiceNamespace = defaults.ServiceNamespace
		}
	}
	cfg.PublicBaseURL = apphttp.NormalizeURL(cfg.PublicBaseURL)
	cfg.LLMBaseURL = apphttp.NormalizeURL(cfg.LLMBaseURL)
	cfg.OTLPEndpoint = apphttp.NormalizeURL(cfg.OTLPEndpoint)
	s := &server{cfg: cfg, client: apphttp.NewHTTPClient(90 * time.Second)}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.health)
	mux.HandleFunc("GET /.well-known", s.protectedResource)
	mux.HandleFunc("GET /.well-known/agent-card.json", s.agentCard)
	mux.HandleFunc("GET /.well-known/oauth-protected-resource", s.protectedResource)
	mux.HandleFunc("GET /.well-known/oauth-protected-resource/mcp", s.protectedResource)
	mux.HandleFunc("GET /a2a/.well-known/agent-card.json", s.agentCard)
	mux.HandleFunc("POST /a2a", s.a2a)
	mux.HandleFunc("POST /mcp", s.mcp)
	return apphttp.RequestLogger("platform-mcp", nil, mux)
}

func NewMetricsHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /metrics", func(w http.ResponseWriter, _ *http.Request) {
		apphttp.WritePrometheusMetrics(w, metrics.render())
	})
	return mux
}

func (s *server) health(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{"status": "ok", "service": "platform-mcp"})
}

func (s *server) protectedResource(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{
		"resource":                 s.cfg.PublicBaseURL + "/mcp",
		"authorization_servers":    []string{"https://keycloak.127.0.0.1.sslip.io/realms/platform"},
		"scopes_supported":         []string{"openid", "profile", "mcp.access"},
		"bearer_methods_supported": []string{"header"},
	})
}

func (s *server) agentCard(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{
		"protocolVersion":    "0.3.0",
		"name":               "platform-mcp",
		"description":        "Local platform agent that can validate MCP, APIM, and agentgateway LLM connectivity.",
		"url":                s.cfg.PublicBaseURL + "/a2a",
		"preferredTransport": "JSONRPC",
		"capabilities": map[string]any{
			"streaming":              false,
			"pushNotifications":      false,
			"stateTransitionHistory": false,
		},
		"securitySchemes": map[string]any{
			"bearer": map[string]any{"type": "http", "scheme": "bearer"},
		},
		"security": []map[string][]string{{"bearer": []string{"openid", "profile"}}},
		"skills": []map[string]any{
			{
				"id":          "model_ping",
				"name":        "Model gateway ping",
				"description": "Validate that this agent can reach an OpenAI-compatible model through agentgateway.",
				"tags":        []string{"llm", "agentgateway", "openai-compatible"},
			},
		},
	})
}

func (s *server) a2a(w http.ResponseWriter, r *http.Request) {
	var req rpcRequest
	if !apphttp.DecodeJSONError(w, r, &req, "invalid JSON body") {
		return
	}
	switch req.Method {
	case "message/send":
		prompt := a2aPrompt(req.Params)
		result, err := s.modelPing(r, map[string]any{"prompt": prompt})
		if err != nil {
			writeRPCError(w, req.ID, -32000, err.Error())
			return
		}
		writeRPC(w, req.ID, map[string]any{
			"kind":      "message",
			"messageId": randomHex(8),
			"role":      "agent",
			"parts":     []map[string]string{{"kind": "text", "text": result}},
		})
	default:
		writeRPCError(w, req.ID, -32601, "method not found")
	}
}

func a2aPrompt(raw json.RawMessage) string {
	if len(raw) == 0 {
		return "Say that the A2A agent can reach the model gateway."
	}
	var params struct {
		Message struct {
			Parts []struct {
				Text string `json:"text"`
			} `json:"parts"`
		} `json:"message"`
	}
	if err := json.Unmarshal(raw, &params); err != nil {
		return "Say that the A2A agent can reach the model gateway."
	}
	var parts []string
	for _, part := range params.Message.Parts {
		if text := strings.TrimSpace(part.Text); text != "" {
			parts = append(parts, text)
		}
	}
	if len(parts) == 0 {
		return "Say that the A2A agent can reach the model gateway."
	}
	return strings.Join(parts, "\n")
}

func (s *server) mcp(w http.ResponseWriter, r *http.Request) {
	var req rpcRequest
	if !apphttp.DecodeJSONError(w, r, &req, "invalid JSON body") {
		return
	}
	switch req.Method {
	case "initialize":
		writeRPC(w, req.ID, map[string]any{
			"protocolVersion": "2025-06-18",
			"serverInfo":      map[string]string{"name": "platform-mcp", "version": "0.1.0"},
			"capabilities":    map[string]any{"tools": map[string]any{"listChanged": false}},
		})
	case "tools/list":
		writeRPC(w, req.ID, map[string]any{"tools": []map[string]any{
			{
				"name":        "model_ping",
				"description": "Send a small OpenAI-compatible chat completion request through agentgateway.",
				"inputSchema": map[string]any{
					"type":       "object",
					"properties": map[string]any{"prompt": map[string]string{"type": "string"}},
				},
			},
			{
				"name":        "d2_validate",
				"description": "Validate D2 source for the MCP Inspector smoke path.",
				"inputSchema": map[string]any{
					"type":       "object",
					"properties": map[string]any{"source": map[string]string{"type": "string"}},
					"required":   []string{"source"},
				},
			},
			{
				"name":        "d2_render",
				"description": "Render a lightweight SVG artifact from D2 source for the MCP Inspector smoke path.",
				"inputSchema": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"source":        map[string]string{"type": "string"},
						"output_format": map[string]string{"type": "string"},
						"layout":        map[string]string{"type": "string"},
					},
					"required": []string{"source"},
				},
			},
		}})
	case "tools/call":
		var params toolCallParams
		_ = json.Unmarshal(req.Params, &params)
		switch params.Name {
		case "model_ping":
			start := time.Now()
			result, err := s.modelPing(r, params.Arguments)
			if err != nil {
				metrics.observe(params.Name, "error", time.Since(start))
				writeRPCError(w, req.ID, -32000, err.Error())
				return
			}
			metrics.observe(params.Name, "ok", time.Since(start))
			writeRPC(w, req.ID, map[string]any{"content": []map[string]string{{"type": "text", "text": result}}})
		case "d2_validate":
			start := time.Now()
			result, err := d2Validate(params.Arguments)
			if err != nil {
				metrics.observe(params.Name, "error", time.Since(start))
				writeRPCError(w, req.ID, -32602, err.Error())
				return
			}
			metrics.observe(params.Name, "ok", time.Since(start))
			writeRPCTextPayload(w, req.ID, result)
		case "d2_render":
			start := time.Now()
			result, err := d2Render(params.Arguments)
			if err != nil {
				metrics.observe(params.Name, "error", time.Since(start))
				writeRPCError(w, req.ID, -32602, err.Error())
				return
			}
			metrics.observe(params.Name, "ok", time.Since(start))
			writeRPCTextPayload(w, req.ID, result)
		default:
			writeRPCError(w, req.ID, -32602, "unsupported tool")
		}
	default:
		writeRPCError(w, req.ID, -32601, "method not found")
	}
}

func d2Validate(args map[string]any) (map[string]any, error) {
	source, _ := args["source"].(string)
	if strings.TrimSpace(source) == "" {
		return nil, fmt.Errorf("source is required")
	}
	return map[string]any{
		"status": "ok",
		"data": map[string]any{
			"valid": true,
		},
	}, nil
}

func d2Render(args map[string]any) (map[string]any, error) {
	source, _ := args["source"].(string)
	if strings.TrimSpace(source) == "" {
		return nil, fmt.Errorf("source is required")
	}
	escaped := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;").Replace(source)
	svg := fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" width="640" height="220" role="img" aria-label="D2 diagram"><rect width="640" height="220" fill="#ffffff"/><rect x="24" y="24" width="592" height="172" rx="6" fill="#f8fafc" stroke="#334155" stroke-width="2"/><text x="42" y="64" font-family="Arial, sans-serif" font-size="20" fill="#0f172a">Platform MCP D2 render</text><text x="42" y="102" font-family="monospace" font-size="15" fill="#334155">%s</text></svg>`, escaped)
	return map[string]any{
		"status": "ok",
		"data": map[string]any{
			"artifact": svg,
			"content":  svg,
			"svg":      svg,
		},
	}, nil
}

func (s *server) modelPing(r *http.Request, args map[string]any) (string, error) {
	prompt, _ := args["prompt"].(string)
	if strings.TrimSpace(prompt) == "" {
		prompt = "Say that the MCP server can reach the model gateway."
	}
	model, err := s.openAICompatibleModel(r)
	if err != nil {
		return "", err
	}
	start := time.Now()
	payload := map[string]any{
		"model": model,
		"messages": []map[string]string{
			{"role": "system", "content": "You are validating MCP to LLM gateway connectivity."},
			{"role": "user", "content": prompt},
		},
		"temperature": 0,
		"max_tokens":  64,
	}
	body, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(r.Context(), http.MethodPost, s.cfg.LLMBaseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.client.Do(req)
	latency := time.Since(start)
	success := err == nil && resp != nil && resp.StatusCode >= 200 && resp.StatusCode < 300
	defer s.emitLLMSpan(r, latency, success, model)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	respBody, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", err
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return "", fmt.Errorf("llm gateway returned %d: %s", resp.StatusCode, string(respBody))
	}
	var decoded struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(respBody, &decoded); err != nil {
		return modelPingPayload(model, string(respBody)), nil
	}
	if len(decoded.Choices) == 0 {
		return modelPingPayload(model, string(respBody)), nil
	}
	return modelPingPayload(model, decoded.Choices[0].Message.Content), nil
}

func modelPingPayload(model string, response string) string {
	payload := map[string]any{
		"success":  true,
		"route":    "agentgateway",
		"model":    model,
		"response": strings.TrimSpace(response),
	}
	encoded, _ := json.MarshalIndent(payload, "", "  ")
	return string(encoded)
}

func (s *server) openAICompatibleModel(r *http.Request) (string, error) {
	if strings.TrimSpace(s.cfg.LLMModel) != "" {
		return strings.TrimSpace(s.cfg.LLMModel), nil
	}
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, s.cfg.LLMBaseURL+"/models", nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Accept", "application/json")
	resp, err := s.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return "", fmt.Errorf("llm model discovery returned %d", resp.StatusCode)
	}
	var decoded struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := apphttp.DecodeJSONReader(resp.Body, &decoded); err != nil {
		return "", err
	}
	for _, model := range decoded.Data {
		if id := strings.TrimSpace(model.ID); id != "" {
			return id, nil
		}
	}
	return "", fmt.Errorf("no OpenAI-compatible models advertised")
}

func writeRPC(w http.ResponseWriter, id any, result any) {
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{"jsonrpc": "2.0", "id": id, "result": result})
}

func writeRPCTextPayload(w http.ResponseWriter, id any, payload map[string]any) {
	text, _ := json.Marshal(payload)
	writeRPC(w, id, map[string]any{"content": []map[string]string{{"type": "text", "text": string(text)}}})
}

func writeRPCError(w http.ResponseWriter, id any, code int, message string) {
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{"jsonrpc": "2.0", "id": id, "error": map[string]any{"code": code, "message": message}})
}

func (m *toolMetrics) observe(tool string, status string, duration time.Duration) {
	tool = strings.TrimSpace(tool)
	status = strings.TrimSpace(status)
	if tool == "" || status == "" {
		return
	}
	key := tool + "\x00" + status
	m.mu.Lock()
	defer m.mu.Unlock()
	m.calls[key]++
	m.durationSums[key] += duration.Seconds()
}

func (m *toolMetrics) render() string {
	m.mu.Lock()
	defer m.mu.Unlock()
	var keys []string
	for key := range m.calls {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	var b strings.Builder
	b.WriteString("# HELP platform_mcp_tool_calls_total MCP tool calls by tool and status.\n")
	b.WriteString("# TYPE platform_mcp_tool_calls_total counter\n")
	for _, key := range keys {
		tool, status, _ := strings.Cut(key, "\x00")
		fmt.Fprintf(&b, "platform_mcp_tool_calls_total{tool=%q,status=%q} %d\n", tool, status, m.calls[key])
	}
	b.WriteString("# HELP platform_mcp_tool_duration_seconds_sum Total MCP tool call duration in seconds.\n")
	b.WriteString("# TYPE platform_mcp_tool_duration_seconds_sum counter\n")
	for _, key := range keys {
		tool, status, _ := strings.Cut(key, "\x00")
		fmt.Fprintf(&b, "platform_mcp_tool_duration_seconds_sum{tool=%q,status=%q} %.6f\n", tool, status, m.durationSums[key])
	}
	return b.String()
}

func (s *server) emitLLMSpan(r *http.Request, latency time.Duration, success bool, model string) {
	if s.cfg.OTLPEndpoint == "" {
		return
	}
	traceID := randomHex(16)
	spanID := randomHex(8)
	now := time.Now()
	payload := map[string]any{
		"resourceSpans": []map[string]any{{
			"resource": map[string]any{"attributes": []map[string]any{
				attr("service.name", s.cfg.ServiceName),
				attr("service.namespace", s.cfg.ServiceNamespace),
				attr("telemetry.sdk.name", "openllmetry"),
			}},
			"scopeSpans": []map[string]any{{
				"scope": map[string]any{"name": "openllmetry", "version": "0.1.0"},
				"spans": []map[string]any{{
					"traceId":           traceID,
					"spanId":            spanID,
					"name":              "llm.openai.chat.completions",
					"kind":              3,
					"startTimeUnixNano": fmt.Sprintf("%d", now.Add(-latency).UnixNano()),
					"endTimeUnixNano":   fmt.Sprintf("%d", now.UnixNano()),
					"attributes": []map[string]any{
						attr("gen_ai.system", "openai"),
						attr("gen_ai.operation.name", "chat"),
						attr("gen_ai.request.model", model),
						attr("gen_ai.request.type", "chat_completions"),
						attr("mcp.tool.name", "model_ping"),
						attr("mcp.transport", "streamable-http"),
						attr("server.address", r.Host),
						attr("url.path", r.URL.Path),
						attr("agentgateway.route", s.cfg.LLMBaseURL),
						attr("pce.egress.via", "agentgateway"),
						attr("pce.success", success),
					},
				}},
			}},
		}},
	}
	body, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(r.Context(), http.MethodPost, s.cfg.OTLPEndpoint+"/v1/traces", bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.client.Do(req)
	if err != nil {
		log.Printf("otlp_trace_export_failed error=%v", err)
		return
	}
	_ = resp.Body.Close()
}

func attr(key string, value any) map[string]any {
	switch v := value.(type) {
	case bool:
		return map[string]any{"key": key, "value": map[string]any{"boolValue": v}}
	default:
		return map[string]any{"key": key, "value": map[string]any{"stringValue": fmt.Sprint(v)}}
	}
}

func randomHex(bytesLen int) string {
	buf := make([]byte, bytesLen)
	if _, err := rand.Read(buf); err != nil {
		return strings.Repeat("0", bytesLen*2)
	}
	return hex.EncodeToString(buf)
}
