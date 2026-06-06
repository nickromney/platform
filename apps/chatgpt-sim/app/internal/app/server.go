package app

import (
	"bytes"
	"context"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"platform.local/appconfig"
	"platform.local/apphealth"
	"platform.local/apphttp"
	"platform.local/appshell"
	"platform.local/idpauth"
)

//go:embed web/*
var web embed.FS

type HTTPDoer interface {
	Do(*http.Request) (*http.Response, error)
}

type server struct {
	cfg        Config
	client     HTTPDoer
	verifier   idpauth.TokenVerifier
	mu         sync.Mutex
	connectors []connector
	nextID     int
}

func NewServer(cfg Config, client HTTPDoer, verifier ...idpauth.TokenVerifier) http.Handler {
	if client == nil {
		client = http.DefaultClient
	}
	var tokenVerifier idpauth.TokenVerifier
	if len(verifier) > 0 {
		tokenVerifier = verifier[0]
	}
	s := &server{cfg: cfg, client: client, verifier: tokenVerifier, nextID: 2}
	s.connectors = initialConnectors(cfg)
	mux := http.NewServeMux()
	switch cfg.Role {
	case "mcp":
		mux.HandleFunc("GET /health", s.mcpHealth)
		mux.HandleFunc("GET /.well-known/oauth-protected-resource/mcp", s.protectedResourceMetadata)
		mux.HandleFunc("GET /.well-known/oauth-authorization-server", s.oauthAuthorizationServer)
		mux.HandleFunc("POST /mcp", s.mcp)
	case "llm":
		mux.HandleFunc("GET /health", s.llmHealth)
		mux.HandleFunc("GET /v1/models", s.llmModels)
		mux.HandleFunc("POST /v1/chat/completions", s.llmChatCompletions)
	default:
		mux.HandleFunc("GET /health", s.shellHealth)
		mux.HandleFunc("GET /api/whoami", s.whoami)
		mux.HandleFunc("GET /api/v1/whoami", s.whoami)
		mux.HandleFunc("GET /api/discovery", s.shellDiscovery)
		mux.HandleFunc("GET /api/connectors", s.listConnectors)
		mux.HandleFunc("POST /api/connectors", s.addConnector)
		mux.HandleFunc("DELETE /api/connectors/{id}", s.deleteConnector)
		mux.HandleFunc("POST /api/chat", s.shellChat)
		mux.HandleFunc("GET /.auth/me", s.gatewaySession)
		mux.HandleFunc("GET /runtime-config.js", s.runtimeConfig)
		appshell.RegisterSharedAssets(mux, idpauth.BrowserBundle)
		mux.HandleFunc("GET /favicon.ico", appshell.SVGFavicon(chatGPTSimFaviconSVG))
		mux.HandleFunc("GET /signed-out.html", appshell.SignedOutPage(appshell.SignedOutPageConfig{
			AppName:     "ChatGPT Sim",
			Tagline:     "MCP connector shell for OAuth discovery and tool calls.",
			SessionName: "ChatGPT Sim",
			Stylesheet:  "/style.css",
			Favicon:     "/favicon.ico",
			PanelClass:  "panel",
		}))
		mux.HandleFunc("GET /oauth/callback", s.oauthCallback)
		mux.Handle("/", appshell.StaticFiles(web, "web"))
	}
	return apphttp.RequestLogger("chatgpt-sim", nil, mux)
}

func (s *server) mcpHealth(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{"status": "ok", "service": "go-local-mcp"})
}

func (s *server) llmHealth(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{"status": "ok", "service": "go-local-openai-compatible-llm"})
}

func (s *server) llmModels(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{
		"object": "list",
		"data": []map[string]any{{
			"id":       s.localLLMModel(),
			"object":   "model",
			"owned_by": "platform",
		}},
	})
}

func (s *server) shellHealth(w http.ResponseWriter, _ *http.Request) {
	apphttp.WriteBrowserAppHealth(w, map[string]any{
		"status":          "ok",
		"service":         "chatgpt-sim-shell",
		"mcp_url":         s.cfg.MCPURL,
		"model_provider":  s.modelProvider(),
		"llm_configured":  s.llmConfigured(),
		"trace_provider":  "langfuse",
		"trace_ingestion": s.traceIngestionStatus(),
	})
}

func (s *server) whoami(w http.ResponseWriter, r *http.Request) {
	claims, ok := s.currentUser(w, r)
	if !ok {
		return
	}
	apphttp.WriteJSON(w, http.StatusOK, claims)
}

func (s *server) currentUser(w http.ResponseWriter, r *http.Request) (idpauth.UserClaims, bool) {
	return (idpauth.Authenticator{Mode: s.cfg.AuthMode, Verifier: s.verifier}).CurrentUserOrWriteError(w, r, idpauth.AuthFailureMessages{})
}

func (s *server) gatewaySession(w http.ResponseWriter, r *http.Request) {
	idpauth.WriteClientPrincipalSession(w, r)
}

func (s *server) llmChatCompletions(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Model    string `json:"model"`
		Messages []struct {
			Role    string `json:"role"`
			Content string `json:"content"`
		} `json:"messages"`
	}
	if !apphttp.DecodeJSONError(w, r, &req, "invalid JSON body") {
		return
	}
	if req.Model == "" {
		req.Model = s.localLLMModel()
	}
	userMessage := ""
	mcpContext := ""
	for _, message := range req.Messages {
		if message.Role == "user" {
			userMessage = message.Content
		}
		if strings.Contains(message.Content, "MCP tool result JSON:") {
			mcpContext = message.Content
		}
	}
	subject := "not provided"
	if strings.Contains(mcpContext, "local-chatgpt-go-user") {
		subject = "local-chatgpt-go-user"
	}
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{
		"model": req.Model,
		"choices": []map[string]any{{
			"index": 0,
			"message": map[string]string{
				"role":    "assistant",
				"content": "OpenAI-compatible local deterministic stub saw `" + userMessage + "` and the MCP subject `" + subject + "`.",
			},
			"finish_reason": "stop",
		}},
	})
}

func (s *server) protectedResourceMetadata(w http.ResponseWriter, r *http.Request) {
	baseURL := s.publicBaseURL(r)
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{
		"resource":                 baseURL + "/mcp",
		"authorization_servers":    []string{baseURL},
		"scopes_supported":         []string{"mcp.access"},
		"bearer_methods_supported": []string{"header"},
	})
}

func (s *server) oauthAuthorizationServer(w http.ResponseWriter, r *http.Request) {
	baseURL := s.publicBaseURL(r)
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{
		"issuer":                                      baseURL,
		"authorization_endpoint":                      baseURL + "/oauth2/v1/authorize",
		"token_endpoint":                              baseURL + "/oauth2/v1/token",
		"registration_endpoint":                       baseURL + "/oauth2/v1/register",
		"client_id_metadata_document_supported":       true,
		"token_endpoint_auth_methods_supported":       []string{"none", "client_secret_basic", "client_secret_post"},
		"code_challenge_methods_supported":            []string{"S256"},
		"response_types_supported":                    []string{"code"},
		"grant_types_supported":                       []string{"authorization_code"},
		"scopes_supported":                            []string{"mcp.access"},
		"local_demo_validates_authorization_endpoint": false,
	})
}

func (s *server) mcp(w http.ResponseWriter, r *http.Request) {
	if !strings.HasPrefix(r.Header.Get("Authorization"), "Bearer ") {
		w.Header().Set("WWW-Authenticate", `Bearer resource_metadata="`+s.publicBaseURL(r)+`/.well-known/oauth-protected-resource/mcp"`)
		apphttp.WriteError(w, http.StatusUnauthorized, "missing bearer token")
		return
	}
	var req rpcRequest
	if !apphttp.DecodeJSONError(w, r, &req, "invalid JSON body") {
		return
	}
	switch req.Method {
	case "initialize":
		writeRPC(w, req.ID, map[string]any{
			"protocolVersion": "2025-06-18",
			"serverInfo":      map[string]string{"name": "go-local-mcp", "version": "0.1.0"},
			"capabilities":    map[string]any{"tools": map[string]any{"listChanged": false}, "resources": map[string]any{"listChanged": false}},
		})
	case "tools/list":
		writeRPC(w, req.ID, map[string]any{"tools": mcpTools()})
	case "resources/list":
		writeRPC(w, req.ID, map[string]any{"resources": []map[string]any{widgetResource()}})
	case "resources/read":
		writeRPC(w, req.ID, map[string]any{"contents": []map[string]any{{
			"uri":      "ui://pce-go/proof-panel.v1.html",
			"mimeType": "text/html;profile=mcp-app",
			"text":     proofWidgetHTML,
		}}})
	case "tools/call":
		var params toolCallParams
		_ = remarshal(req.Params, &params)
		writeRPC(w, req.ID, toolResult(params.Name, params.Arguments))
	default:
		writeRPCError(w, req.ID, -32601, "method not found")
	}
}

func (s *server) shellDiscovery(w http.ResponseWriter, r *http.Request) {
	conn := s.defaultConnector()
	discovery, err := s.discoverConnector(conn, outboundAuthorization(r))
	if err != nil {
		apphttp.WriteError(w, http.StatusBadGateway, err.Error())
		return
	}
	apphttp.WriteJSON(w, http.StatusOK, discovery)
}

func (s *server) shellChat(w http.ResponseWriter, r *http.Request) {
	var req chatRequest
	if !apphttp.DecodeJSONError(w, r, &req, "invalid JSON body") {
		return
	}
	req.Message = strings.TrimSpace(req.Message)
	if req.Message == "" {
		apphttp.WriteError(w, http.StatusBadRequest, "message is required")
		return
	}
	conn, ok := s.connectorByID(req.ConnectorID)
	if !ok {
		apphttp.WriteError(w, http.StatusBadRequest, "connector not found")
		return
	}
	requestBudget := s.llmTimeout()
	deadline := time.Now().Add(requestBudget)
	discoveryTimeout := stageTimeout(deadline, requestBudget-50*time.Millisecond, 900*time.Millisecond)
	discovery, err := s.discoverConnectorWithinBudget(conn, outboundAuthorization(r), discoveryTimeout)
	if err != nil {
		apphttp.WriteError(w, http.StatusBadGateway, err.Error())
		return
	}
	toolName, args := chooseTool(req.Tool, req.Message)
	if toolName == "model_ping" && s.cfg.LLMURL != "" {
		pingTimeout := stageTimeout(deadline, requestBudget-50*time.Millisecond, 900*time.Millisecond)
		result, err := s.pingLLMModelsWithinBudget(pingTimeout)
		steps := []map[string]any{{"method": "llm.models", "status": "ok", "route": "agentgateway"}}
		if err != nil {
			steps[0]["status"] = "error"
			steps[0]["error"] = err.Error()
			result = failedToolResult(toolName, err)
		}
		assistant := deterministicReply(toolName, result)
		model := map[string]any{"provider": "deterministic", "model": "go-local-rule"}
		if modelEvidence := modelFromToolResult(toolName, result); modelEvidence != nil {
			model = modelEvidence
		}
		traceTimeout := stageTimeout(deadline, s.langfuseTimeout(), s.langfuseTimeout())
		trace := s.emitChatTraceWithinBudget(r, req.Message, assistant, toolName, result, model, traceTimeout)
		apphttp.WriteJSON(w, http.StatusOK, map[string]any{
			"assistant":      assistant,
			"connector":      conn,
			"model":          model,
			"trace":          trace,
			"selected_tool":  toolName,
			"tool_arguments": args,
			"tool_result":    result,
			"discovery":      discovery,
			"mcp_steps":      steps,
		})
		return
	}
	mcpTimeout := stageTimeout(deadline, requestBudget-50*time.Millisecond, 900*time.Millisecond)
	steps, result, selectedTool, err := s.callConnectorMCPWithinBudget(conn, toolName, args, req.Tool, req.Message, outboundAuthorization(r), mcpTimeout)
	if err != nil {
		steps = append(steps, map[string]any{"method": "tools/call", "status": "error", "error": err.Error()})
		result = failedToolResult(toolName, err)
		selectedTool = toolName
	}
	toolName = selectedTool
	assistant := deterministicReply(toolName, result)
	model := map[string]any{"provider": "deterministic", "model": "go-local-rule"}
	if modelEvidence := modelFromToolResult(toolName, result); modelEvidence != nil {
		model = modelEvidence
	} else if s.cfg.LLMURL != "" && toolName != "tools/list" && !isToolError(result) {
		var modelName string
		llmTimeout := stageTimeout(deadline, requestBudget-50*time.Millisecond, 900*time.Millisecond)
		assistant, modelName, err = s.completeWithLLMWithinBudget(req.Message, toolName, result, llmTimeout)
		if err != nil {
			assistant = deterministicReply(toolName, result)
			model = map[string]any{"provider": "openai-compatible", "route": "agentgateway", "status": "unavailable", "error": err.Error()}
		} else if isUnusableAssistantText(assistant) {
			assistant = deterministicReply(toolName, result)
			model = map[string]any{"provider": "openai-compatible", "model": modelName, "route": "agentgateway", "status": "fallback"}
		} else {
			model = map[string]any{"provider": "openai-compatible", "model": modelName, "route": "agentgateway", "status": "ok"}
		}
	}
	traceTimeout := stageTimeout(deadline, s.langfuseTimeout(), s.langfuseTimeout())
	trace := s.emitChatTraceWithinBudget(r, req.Message, assistant, toolName, result, model, traceTimeout)
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{
		"assistant":      assistant,
		"connector":      conn,
		"model":          model,
		"trace":          trace,
		"selected_tool":  toolName,
		"tool_arguments": args,
		"tool_result":    result,
		"discovery":      discovery,
		"mcp_steps":      steps,
	})
}

func stageTimeout(deadline time.Time, preferred time.Duration, cap time.Duration) time.Duration {
	if preferred <= 0 {
		preferred = time.Second
	}
	if cap > 0 && preferred > cap {
		preferred = cap
	}
	remaining := time.Until(deadline)
	if remaining <= 0 {
		return time.Millisecond
	}
	if preferred > remaining {
		return remaining
	}
	return preferred
}

func isToolError(result map[string]any) bool {
	value, _ := result["isError"].(bool)
	return value
}

func modelFromToolResult(toolName string, result map[string]any) map[string]any {
	if toolName != "model_ping" || isToolError(result) {
		return nil
	}
	content, _ := result["structuredContent"].(map[string]any)
	if content == nil {
		return nil
	}
	success, _ := content["success"].(bool)
	if !success {
		return nil
	}
	modelName := stringValue(content["model"])
	if modelName == "" {
		modelName = stringValue(content["deployment_name"])
	}
	if modelName == "" {
		modelName = "discovered-model"
	}
	route := stringValue(content["route"])
	if route == "" {
		route = "agentgateway"
	}
	source := stringValue(content["source"])
	if source == "" {
		source = "mcp.model_ping"
	}
	return map[string]any{"provider": "openai-compatible", "model": modelName, "route": route, "status": "ok", "source": source}
}

func failedToolResult(toolName string, err error) map[string]any {
	message := ""
	if err != nil {
		message = err.Error()
	}
	content := map[string]any{
		"status": "error",
		"tool":   toolName,
		"error":  message,
	}
	text, _ := json.MarshalIndent(content, "", "  ")
	return map[string]any{
		"content":           []map[string]any{{"type": "text", "text": string(text)}},
		"structuredContent": content,
		"isError":           true,
	}
}

func (s *server) discoverConnectorWithinBudget(conn connector, authorization string, timeout time.Duration) (map[string]any, error) {
	if timeout <= 0 {
		timeout = time.Millisecond
	}
	type discoveryResult struct {
		discovery map[string]any
		err       error
	}
	done := make(chan discoveryResult, 1)
	go func() {
		discovery, err := s.discoverConnector(conn, authorization)
		done <- discoveryResult{discovery: discovery, err: err}
	}()
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case result := <-done:
		return result.discovery, result.err
	case <-timer.C:
		return nil, fmt.Errorf("MCP discovery exceeded %s", timeout)
	}
}

func (s *server) callConnectorMCPWithinBudget(conn connector, toolName string, args map[string]any, requestedTool string, message string, authorization string, timeout time.Duration) ([]map[string]any, map[string]any, string, error) {
	if timeout <= 0 {
		timeout = time.Millisecond
	}
	type mcpResult struct {
		steps        []map[string]any
		result       map[string]any
		selectedTool string
		err          error
	}
	done := make(chan mcpResult, 1)
	go func() {
		steps, result, selectedTool, err := s.callConnectorMCP(conn, toolName, args, requestedTool, message, authorization)
		done <- mcpResult{steps: steps, result: result, selectedTool: selectedTool, err: err}
	}()
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case result := <-done:
		return result.steps, result.result, result.selectedTool, result.err
	case <-timer.C:
		return nil, nil, "", fmt.Errorf("MCP connector call exceeded %s", timeout)
	}
}

func (s *server) completeWithLLMWithinBudget(message string, toolName string, toolResult map[string]any, timeout time.Duration) (string, string, error) {
	if timeout <= 0 {
		timeout = time.Millisecond
	}
	type completionResult struct {
		assistant string
		modelName string
		err       error
	}
	done := make(chan completionResult, 1)
	go func() {
		assistant, modelName, err := s.completeWithLLM(message, toolName, toolResult, timeout)
		done <- completionResult{assistant: assistant, modelName: modelName, err: err}
	}()
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case result := <-done:
		return result.assistant, result.modelName, result.err
	case <-timer.C:
		return "", "", fmt.Errorf("LLM completion exceeded %s", timeout)
	}
}

func (s *server) pingLLMModelsWithinBudget(timeout time.Duration) (map[string]any, error) {
	if timeout <= 0 {
		timeout = time.Millisecond
	}
	type pingResult struct {
		result map[string]any
		err    error
	}
	done := make(chan pingResult, 1)
	go func() {
		result, err := s.pingLLMModels(timeout)
		done <- pingResult{result: result, err: err}
	}()
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case result := <-done:
		return result.result, result.err
	case <-timer.C:
		return nil, fmt.Errorf("LLM model catalogue exceeded %s", timeout)
	}
}

func (s *server) emitChatTraceWithinBudget(r *http.Request, message string, assistant string, toolName string, toolResult map[string]any, model map[string]any, timeout time.Duration) map[string]string {
	if timeout <= 0 {
		timeout = time.Millisecond
	}
	done := make(chan map[string]string, 1)
	go func() {
		done <- s.emitChatTrace(r, message, assistant, toolName, toolResult, model)
	}()
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case result := <-done:
		return result
	case <-timer.C:
		traceID := fmt.Sprintf("chatgpt-sim-%d", time.Now().UnixNano())
		return map[string]string{"provider": "langfuse", "status": "error", "traceId": traceID, "error": fmt.Sprintf("Langfuse ingestion exceeded %s", timeout)}
	}
}

func (s *server) emitChatTrace(r *http.Request, message string, assistant string, toolName string, toolResult map[string]any, model map[string]any) map[string]string {
	traceID := fmt.Sprintf("chatgpt-sim-%d", time.Now().UnixNano())
	return s.emitChatTraceWithID(r, traceID, message, assistant, toolName, toolResult, model)
}

func (s *server) emitChatTraceWithID(r *http.Request, traceID string, message string, assistant string, toolName string, toolResult map[string]any, model map[string]any) map[string]string {
	status := "disabled"
	if !s.langfuseConfigured() {
		return map[string]string{"provider": "langfuse", "status": status, "traceId": traceID}
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)
	modelName, _ := model["model"].(string)
	if strings.TrimSpace(modelName) == "" {
		modelName = stringValue(model["provider"])
	}
	if strings.TrimSpace(modelName) == "" {
		modelName = "unavailable"
	}
	payload := map[string]any{"batch": []map[string]any{
		{
			"id":        traceID + "-trace",
			"type":      "trace-create",
			"timestamp": now,
			"body": map[string]any{
				"id":     traceID,
				"name":   "chatgpt-sim.chat",
				"input":  message,
				"output": assistant,
				"tags":   []string{"platform-demo", "chatgpt-sim"},
				"metadata": map[string]any{
					"selected_tool": toolName,
					"mcp_url":       s.cfg.MCPURL,
					"llm_url":       s.cfg.LLMURL,
				},
			},
		},
		{
			"id":        traceID + "-generation",
			"type":      "generation-create",
			"timestamp": now,
			"body": map[string]any{
				"id":      traceID + "-gen",
				"traceId": traceID,
				"name":    "assistant-response",
				"model":   modelName,
				"input": map[string]any{
					"message":       message,
					"selected_tool": toolName,
					"tool_result":   toolResult,
				},
				"output":    assistant,
				"startTime": now,
				"endTime":   now,
				"metadata": map[string]any{
					"model": model,
				},
			},
		},
	}}
	body, _ := json.Marshal(payload)
	timeout := s.cfg.LangfuseTimeout
	if timeout <= 0 {
		timeout = time.Second
	}
	ctx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(s.cfg.LangfuseHost, "/")+"/api/public/ingestion", bytes.NewReader(body))
	if err != nil {
		return map[string]string{"provider": "langfuse", "status": "error", "traceId": traceID, "error": err.Error()}
	}
	req.Header.Set("Content-Type", "application/json")
	req.SetBasicAuth(s.cfg.LangfusePublicKey, s.cfg.LangfuseSecretKey)
	resp, err := s.llmClient(timeout).Do(req)
	if err != nil {
		return map[string]string{"provider": "langfuse", "status": "error", "traceId": traceID, "error": err.Error()}
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
		return map[string]string{"provider": "langfuse", "status": fmt.Sprintf("http_%d", resp.StatusCode), "traceId": traceID, "error": truncate(string(raw), 180)}
	}
	return map[string]string{"provider": "langfuse", "status": "ok", "traceId": traceID}
}

func (s *server) langfuseTimeout() time.Duration {
	if s.cfg.LangfuseTimeout > 0 {
		return s.cfg.LangfuseTimeout
	}
	return time.Second
}

func (s *server) langfuseConfigured() bool {
	return strings.TrimSpace(s.cfg.LangfuseHost) != "" && strings.TrimSpace(s.cfg.LangfusePublicKey) != "" && strings.TrimSpace(s.cfg.LangfuseSecretKey) != ""
}

func truncate(value string, limit int) string {
	value = strings.TrimSpace(value)
	if limit <= 0 || len(value) <= limit {
		return value
	}
	return value[:limit] + "..."
}

func (s *server) completeWithLLM(message string, toolName string, toolResult map[string]any, timeout time.Duration) (string, string, error) {
	if timeout <= 0 {
		timeout = time.Millisecond
	}
	modelName, err := s.openAICompatibleModel()
	if err != nil {
		return "", "", err
	}
	contextJSON, _ := json.Marshal(toolResult)
	toolText := extractMCPText(toolResult)
	payload := map[string]any{
		"model": modelName,
		"messages": []map[string]string{
			{
				"role":    "system",
				"content": "You are ChatGPT Sim. The platform shell has already executed the selected MCP tool. /no_think Answer the user from the observed MCP tool result in one concise paragraph. Do not include hidden reasoning. Do not say you need to call the tool, and do not invent tool results.",
			},
			{"role": "user", "content": message},
			{
				"role": "user",
				"content": "Observed MCP tool result.\nSelected MCP tool: " + toolName +
					"\nMCP tool result text: " + toolText +
					"\nMCP tool result JSON: " + string(contextJSON),
			},
		},
		"max_tokens":  s.llmMaxTokens(),
		"temperature": 0,
		"stream":      false,
	}
	body, _ := json.Marshal(payload)
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.cfg.LLMURL, strings.NewReader(string(body)))
	if err != nil {
		return "", "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	resp, err := s.llmClient(timeout).Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return "", "", errors.New(resp.Status)
	}
	var completion struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := apphttp.DecodeJSONReader(resp.Body, &completion); err != nil {
		return "", "", err
	}
	if len(completion.Choices) == 0 || strings.TrimSpace(completion.Choices[0].Message.Content) == "" {
		return "", "", errors.New("empty LLM completion")
	}
	return cleanAssistantText(completion.Choices[0].Message.Content), modelName, nil
}

func (s *server) pingLLMModels(timeout time.Duration) (map[string]any, error) {
	modelsURL, err := llmModelsURL(s.cfg.LLMURL)
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, modelsURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	resp, err := s.llmClient(timeout).Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, errors.New(resp.Status)
	}
	var models struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := apphttp.DecodeJSONReader(resp.Body, &models); err != nil {
		return nil, err
	}
	modelName := s.cfg.LLMModel
	if modelName == "" && len(models.Data) > 0 {
		modelName = models.Data[0].ID
	}
	if strings.TrimSpace(modelName) == "" {
		modelName = "discovered-model"
	}
	content := map[string]any{"success": true, "provider": "openai-compatible", "route": "agentgateway", "model": modelName, "source": "llm.models"}
	text, _ := json.MarshalIndent(content, "", "  ")
	return map[string]any{
		"content":           []map[string]any{{"type": "text", "text": string(text)}},
		"structuredContent": content,
		"isError":           false,
	}, nil
}

func llmModelsURL(completionsURL string) (string, error) {
	parsed, err := url.Parse(strings.TrimSpace(completionsURL))
	if err != nil {
		return "", err
	}
	if parsed.Scheme == "" || parsed.Host == "" {
		return "", errors.New("invalid LLM URL")
	}
	path := strings.TrimRight(parsed.Path, "/")
	switch {
	case strings.HasSuffix(path, "/chat/completions"):
		parsed.Path = strings.TrimSuffix(path, "/chat/completions") + "/models"
	case strings.HasSuffix(path, "/completions"):
		parsed.Path = strings.TrimSuffix(path, "/completions") + "/models"
	default:
		parsed.Path = strings.TrimRight(path, "/") + "/models"
	}
	parsed.RawQuery = ""
	parsed.Fragment = ""
	return parsed.String(), nil
}

func (s *server) llmTimeout() time.Duration {
	if s.cfg.LLMTimeout > 0 {
		return s.cfg.LLMTimeout
	}
	return time.Second
}

func (s *server) llmClient(timeout time.Duration) HTTPDoer {
	if client, ok := s.client.(*http.Client); ok {
		bounded := *client
		if bounded.Timeout == 0 || bounded.Timeout > timeout {
			bounded.Timeout = timeout
		}
		return &bounded
	}
	return s.client
}

func (s *server) llmMaxTokens() int {
	if s.cfg.LLMMaxTokens > 0 {
		return s.cfg.LLMMaxTokens
	}
	return 32
}

func cleanAssistantText(content string) string {
	content = strings.TrimSpace(content)
	if content == "" {
		return content
	}
	for _, marker := range []string{"Direct Answer:", "Final Answer:", "Answer:"} {
		if idx := strings.LastIndex(content, marker); idx >= 0 {
			content = strings.TrimSpace(content[idx+len(marker):])
			break
		}
	}
	if strings.HasPrefix(content, "Thinking Process:") {
		lines := strings.Split(content, "\n")
		for i := len(lines) - 1; i >= 0; i-- {
			line := strings.TrimSpace(lines[i])
			if strings.HasPrefix(line, "*   Direct Answer:") {
				content = strings.TrimSpace(strings.TrimPrefix(line, "*   Direct Answer:"))
				break
			}
			if strings.HasPrefix(line, "Direct Answer:") {
				content = strings.TrimSpace(strings.TrimPrefix(line, "Direct Answer:"))
				break
			}
		}
	}
	if idx := strings.Index(content, "\n"); idx >= 0 {
		content = strings.TrimSpace(content[:idx])
	}
	return strings.TrimSpace(content)
}

func isUnusableAssistantText(content string) bool {
	content = strings.TrimSpace(content)
	return content == "" || content == "Thinking Process:" || content == "Thinking Process"
}

func extractMCPText(result map[string]any) string {
	content, ok := result["content"].([]any)
	if !ok {
		return ""
	}
	var parts []string
	for _, item := range content {
		entry, ok := item.(map[string]any)
		if !ok {
			continue
		}
		text, _ := entry["text"].(string)
		if trimmed := strings.TrimSpace(text); trimmed != "" {
			parts = append(parts, trimmed)
		}
	}
	return strings.Join(parts, "\n")
}

func (s *server) openAICompatibleModel() (string, error) {
	if strings.TrimSpace(s.cfg.LLMModel) != "" {
		return strings.TrimSpace(s.cfg.LLMModel), nil
	}
	modelsURL, err := modelsURLForChatCompletions(s.cfg.LLMURL)
	if err != nil {
		return "", err
	}
	req, err := http.NewRequest(http.MethodGet, modelsURL, nil)
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
		return "", errors.New(resp.Status)
	}
	var models struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := apphttp.DecodeJSONReader(resp.Body, &models); err != nil {
		return "", err
	}
	for _, model := range models.Data {
		if id := strings.TrimSpace(model.ID); id != "" {
			return id, nil
		}
	}
	return "", errors.New("no OpenAI-compatible models advertised")
}

func modelsURLForChatCompletions(chatURL string) (string, error) {
	parsed, err := url.Parse(strings.TrimSpace(chatURL))
	if err != nil {
		return "", err
	}
	if parsed.Scheme == "" || parsed.Host == "" {
		return "", errors.New("LLM_URL must be absolute")
	}
	parsed.RawQuery = ""
	parsed.Fragment = ""
	parsed.Path = strings.TrimSuffix(parsed.Path, "/")
	if strings.HasSuffix(parsed.Path, "/chat/completions") {
		parsed.Path = strings.TrimSuffix(parsed.Path, "/chat/completions") + "/models"
		return parsed.String(), nil
	}
	parsed.Path = strings.TrimRight(parsed.Path, "/") + "/models"
	return parsed.String(), nil
}

func (s *server) localLLMModel() string {
	if strings.TrimSpace(s.cfg.LLMModel) != "" {
		return strings.TrimSpace(s.cfg.LLMModel)
	}
	return "go-local-openai-compatible-stub"
}

func (s *server) listConnectors(w http.ResponseWriter, _ *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{"items": s.connectors})
}

func (s *server) addConnector(w http.ResponseWriter, r *http.Request) {
	var req connectorRequest
	if !apphttp.DecodeJSONError(w, r, &req, "invalid JSON body") {
		return
	}
	req.URL = normalizeConnectorURL(req.URL)
	if req.URL == "" {
		apphttp.WriteError(w, http.StatusBadRequest, "mcp url is required")
		return
	}
	if req.Name = strings.TrimSpace(req.Name); req.Name == "" {
		req.Name = req.URL
	}
	if req.Auth = strings.TrimSpace(req.Auth); req.Auth == "" {
		req.Auth = "local_bearer"
	}
	req.OAuthClientID = strings.TrimSpace(req.OAuthClientID)
	req.normalizeOAuthAdvanced()
	if existing, ok := s.connectorByURL(req.URL); ok {
		apphttp.WriteJSON(w, http.StatusConflict, map[string]any{"error": "connector already exists", "connector": existing})
		return
	}
	discovery, err := s.discover(req.URL, outboundAuthorization(r))
	if discovery == nil {
		discovery = map[string]any{}
	}
	applyOAuthOverrides(discovery, req)
	conn := connector{
		ID:            s.reserveConnectorID(),
		Name:          req.Name,
		URL:           req.URL,
		Auth:          req.Auth,
		Status:        "ready",
		Discovery:     discovery,
		ClientID:      req.OAuthClientID,
		OAuthAdvanced: req.advancedSummary(),
	}
	if err != nil {
		conn.Status = "discovery_failed"
		conn.Error = err.Error()
	}
	if oauth, ok := discovery["oauth_authorization_server"].(map[string]any); ok {
		conn.OAuth = oauthSummary(oauth)
	}
	if len(conn.OAuth) == 0 {
		if oidc, ok := discovery["oidc_configuration"].(map[string]any); ok {
			conn.OAuth = oauthSummary(oidc)
		}
	}
	conn.LoginURL = s.oauthLoginURL(discovery, conn.ClientID, conn.ID, r, req.loginScopes())
	s.mu.Lock()
	s.connectors = append(s.connectors, conn)
	s.mu.Unlock()
	apphttp.WriteJSON(w, http.StatusOK, conn)
}

func initialConnectors(cfg Config) []connector {
	if len(cfg.MCPConnectors) > 0 {
		connectors := make([]connector, 0, len(cfg.MCPConnectors))
		for idx, item := range cfg.MCPConnectors {
			id := item.ID
			if id == "" {
				id = fmt.Sprintf("connector-%d", idx+1)
			}
			name := item.Name
			if name == "" {
				name = item.URL
			}
			auth := item.Auth
			if auth == "" {
				auth = "local_bearer"
			}
			connectors = append(connectors, connector{
				ID:          id,
				Name:        name,
				URL:         item.URL,
				InternalURL: item.InternalURL,
				Auth:        auth,
				Status:      "configured",
			})
		}
		return connectors
	}
	if cfg.MCPURL == "" {
		return nil
	}
	return []connector{{
		ID:          "default",
		Name:        "Local Go MCP",
		URL:         cfg.MCPURL,
		InternalURL: cfg.MCPInternalURL,
		Auth:        "local_bearer",
		Status:      "configured",
	}}
}

func (s *server) deleteConnector(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.PathValue("id"))
	if id == "" {
		apphttp.WriteError(w, http.StatusBadRequest, "connector id is required")
		return
	}
	if id == "default" {
		apphttp.WriteError(w, http.StatusBadRequest, "default connector cannot be deleted")
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, conn := range s.connectors {
		if conn.ID == id {
			s.connectors = append(s.connectors[:i], s.connectors[i+1:]...)
			w.WriteHeader(http.StatusNoContent)
			return
		}
	}
	apphttp.WriteError(w, http.StatusNotFound, "connector not found")
}

func (s *server) runtimeConfig(w http.ResponseWriter, r *http.Request) {
	payload := appshell.RuntimeConfigPayload(r, appshell.RuntimeConfigOptions{
		Base: map[string]any{
			"authMethod":          s.cfg.AuthMode,
			"apiAuthMethod":       s.cfg.APIAuthMode,
			"oidcAuthority":       appconfig.NormalizeURL(s.cfg.OIDCIssuer),
			"oidcClientId":        s.cfg.OIDCClientID,
			"mcpUrl":              s.cfg.MCPURL,
			"modelProvider":       s.modelProvider(),
			"traceProvider":       s.traceProvider(),
			"dependencyFootprint": apphealth.DependencyFootprintGoSharedIDPAuth,
		},
		OIDCRedirect:        s.cfg.OIDCRedirect,
		IncludeOIDCRedirect: true,
		ShowNetworkPath:     s.cfg.ShowNetworkPath,
		NetworkHopsJSON:     s.cfg.NetworkHops,
	})
	appshell.WriteScriptConfigForRequest(w, r, "window.PCE_CHATGPT_GO_CONFIG", payload)
}

func (s *server) modelProvider() string {
	if s.llmConfigured() {
		return "openai-compatible via agentgateway"
	}
	return "deterministic"
}

func (s *server) llmConfigured() bool {
	return strings.TrimSpace(s.cfg.LLMURL) != ""
}

func (s *server) traceProvider() string {
	if s.langfuseConfigured() {
		return "langfuse configured"
	}
	return "disabled"
}

func (s *server) traceIngestionStatus() string {
	if s.langfuseConfigured() {
		return "configured"
	}
	return "disabled"
}

func (s *server) oauthCallback(w http.ResponseWriter, r *http.Request) {
	appshell.NoCacheHeaders(w)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	code := r.URL.Query().Get("code")
	state := r.URL.Query().Get("state")
	errorText := r.URL.Query().Get("error")
	description := r.URL.Query().Get("error_description")
	if errorText != "" {
		_, _ = io.WriteString(w, callbackHTML("OAuth returned an error", errorText+"\n"+description))
		return
	}
	if code == "" {
		_, _ = io.WriteString(w, callbackHTML("OAuth callback received", "No authorization code was returned."))
		return
	}
	_, _ = io.WriteString(w, callbackHTML("OAuth authorization code received", "state="+state+"\ncode="+code+"\n\nToken exchange is not implemented yet."))
}

func (s *server) publicBaseURL(r *http.Request) string {
	if s.cfg.PublicBaseURL != "" {
		return strings.TrimRight(s.cfg.PublicBaseURL, "/")
	}
	scheme := "http"
	if r.TLS != nil {
		scheme = "https"
	}
	return scheme + "://" + r.Host
}

const chatGPTSimFaviconSVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="10" fill="#14171d"/><path d="M16 18h32M16 32h22M16 46h28" stroke="#79d89f" stroke-width="6" stroke-linecap="round"/></svg>`

func (s *server) discover(mcpURL string, authorization string) (map[string]any, error) {
	return s.discoverResolved(mcpURL, "", authorization)
}

func (s *server) discoverConnector(conn connector, authorization string) (map[string]any, error) {
	return s.discoverResolved(conn.URL, conn.InternalURL, authorization)
}

func (s *server) discoverResolved(mcpURL string, internalURL string, authorization string) (map[string]any, error) {
	resolvedURL := s.resolveMCPURL(mcpURL, internalURL)
	hostOverride := s.mcpHostOverride(mcpURL, internalURL)
	base := strings.TrimSuffix(strings.TrimRight(resolvedURL, "/"), "/mcp")
	protected, err := s.getJSONWithHost(base+"/.well-known/oauth-protected-resource/mcp", authorization, hostOverride)
	if err != nil {
		return nil, err
	}
	oauth := map[string]any{}
	oidc := map[string]any{}
	if servers, ok := protected["authorization_servers"].([]any); ok && len(servers) > 0 {
		if issuer, ok := servers[0].(string); ok {
			issuer = strings.TrimRight(issuer, "/")
			var err error
			oauth, err = s.getJSON(issuer+"/.well-known/oauth-authorization-server", authorization)
			if err != nil {
				oauth = map[string]any{}
				oidc, _ = s.getJSON(issuer+"/.well-known/openid-configuration", authorization)
			}
		}
	}
	return map[string]any{
		"metadata_url":               strings.TrimSuffix(strings.TrimRight(mcpURL, "/"), "/mcp") + "/.well-known/oauth-protected-resource/mcp",
		"protected_resource":         protected,
		"oauth_authorization_server": oauth,
		"oidc_configuration":         oidc,
	}, nil
}

func (s *server) getJSON(url string, authorization string) (map[string]any, error) {
	return s.getJSONWithHost(url, authorization, "")
}

func (s *server) getJSONWithHost(url string, authorization string, hostOverride string) (map[string]any, error) {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	if hostOverride != "" {
		req.Host = hostOverride
	}
	if authorization != "" {
		req.Header.Set("Authorization", authorization)
	}
	resp, err := s.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, errors.New(resp.Status)
	}
	var out map[string]any
	if err := apphttp.DecodeJSONReader(resp.Body, &out); err != nil {
		return nil, err
	}
	return out, nil
}

func (s *server) defaultConnector() connector {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.connectors) > 0 {
		return s.connectors[0]
	}
	return connector{ID: "default", Name: "Configured MCP", URL: s.cfg.MCPURL, Auth: "local_bearer", Status: "configured"}
}

func (s *server) connectorByID(id string) (connector, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if id == "" && len(s.connectors) > 0 {
		return s.connectors[0], true
	}
	for _, conn := range s.connectors {
		if conn.ID == id {
			return conn, true
		}
	}
	return connector{}, false
}

func (s *server) connectorByURL(url string) (connector, bool) {
	normalized := normalizeConnectorURL(url)
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, conn := range s.connectors {
		if normalizeConnectorURL(conn.URL) == normalized {
			return conn, true
		}
	}
	return connector{}, false
}

func (s *server) newConnectorID() string {
	id := fmt.Sprintf("connector-%d", s.nextID)
	s.nextID++
	return id
}

func (s *server) reserveConnectorID() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.newConnectorID()
}

func normalizeConnectorURL(raw string) string {
	trimmed := strings.TrimRight(strings.TrimSpace(raw), "/")
	if trimmed == "" {
		return ""
	}
	parsed, err := url.Parse(trimmed)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return trimmed
	}
	if parsed.Path == "" || parsed.Path == "/" {
		parsed.Path = "/mcp"
	}
	return strings.TrimRight(parsed.String(), "/")
}

func oauthSummary(metadata map[string]any) map[string]any {
	keys := []string{
		"issuer",
		"authorization_endpoint",
		"token_endpoint",
		"registration_endpoint",
		"client_id_metadata_document_supported",
		"token_endpoint_auth_methods_supported",
		"scopes_supported",
	}
	out := map[string]any{}
	for _, key := range keys {
		if value, ok := metadata[key]; ok {
			out[key] = value
		}
	}
	return out
}

func applyOAuthOverrides(discovery map[string]any, req connectorRequest) {
	oauth := ensureMap(discovery, "oauth_authorization_server")
	if req.OAuthAuthorizationURL != "" {
		oauth["authorization_endpoint"] = req.OAuthAuthorizationURL
	}
	if req.OAuthTokenURL != "" {
		oauth["token_endpoint"] = req.OAuthTokenURL
	}
	if req.OAuthRegistrationURL != "" {
		oauth["registration_endpoint"] = req.OAuthRegistrationURL
	}
	if req.OAuthAuthorizationServerBase != "" {
		oauth["issuer"] = req.OAuthAuthorizationServerBase
	}
	if req.OAuthTokenEndpointAuthMethod != "" {
		oauth["token_endpoint_auth_methods_supported"] = []string{req.OAuthTokenEndpointAuthMethod}
	}
	if scopes := req.loginScopes(); len(scopes) > 0 {
		oauth["scopes_supported"] = scopes
	}
	protected := ensureMap(discovery, "protected_resource")
	if req.OAuthResource != "" {
		protected["resource"] = req.OAuthResource
	}
	if scopes := req.loginScopes(); len(scopes) > 0 {
		protected["scopes_supported"] = scopes
	}
	oidc := ensureMap(discovery, "oidc_configuration")
	if req.OAuthOIDCConfigurationURL != "" {
		oidc["configuration_url"] = req.OAuthOIDCConfigurationURL
	}
	if req.OAuthOIDCUserinfoEndpoint != "" {
		oidc["userinfo_endpoint"] = req.OAuthOIDCUserinfoEndpoint
	}
	if len(req.OAuthOIDCScopesSupported) > 0 {
		oidc["scopes_supported"] = req.OAuthOIDCScopesSupported
	}
}

func ensureMap(parent map[string]any, key string) map[string]any {
	if existing, ok := parent[key].(map[string]any); ok {
		return existing
	}
	created := map[string]any{}
	parent[key] = created
	return created
}

func (s *server) oauthLoginURL(discovery map[string]any, clientID string, state string, r *http.Request, scopes []string) string {
	if clientID == "" {
		return ""
	}
	authEndpoint := authorizationEndpoint(discovery)
	if authEndpoint == "" {
		return ""
	}
	values := url.Values{}
	values.Set("client_id", clientID)
	values.Set("response_type", "code")
	values.Set("redirect_uri", s.publicBaseURL(r)+"/oauth/callback")
	if len(scopes) == 0 {
		scopes = loginScopesFromDiscovery(discovery)
	}
	values.Set("scope", strings.Join(scopes, " "))
	values.Set("state", state)
	values.Set("prompt", "select_account")
	return authEndpoint + "?" + values.Encode()
}

func authorizationEndpoint(discovery map[string]any) string {
	for _, key := range []string{"oauth_authorization_server", "oidc_configuration"} {
		if metadata, ok := discovery[key].(map[string]any); ok {
			if endpoint := stringValue(metadata["authorization_endpoint"]); endpoint != "" {
				return endpoint
			}
		}
	}
	return ""
}

func loginScopesFromDiscovery(discovery map[string]any) []string {
	if protected, ok := discovery["protected_resource"].(map[string]any); ok {
		if scopes, ok := protected["scopes_supported"].([]any); ok && len(scopes) > 0 {
			if scope := stringValue(scopes[0]); scope != "" {
				return []string{scope}
			}
		}
	}
	if metadata, ok := discovery["oauth_authorization_server"].(map[string]any); ok {
		if scopes, ok := metadata["scopes_supported"].([]any); ok && len(scopes) > 0 {
			if scope := stringValue(scopes[0]); scope != "" {
				return []string{scope}
			}
		}
	}
	return []string{"openid"}
}

func (s *server) callMCP(mcpURL string, toolName string, args map[string]any, requestedTool string, message string, authorization string) ([]map[string]any, map[string]any, string, error) {
	return s.callMCPResolved(mcpURL, "", toolName, args, requestedTool, message, authorization, true)
}

func (s *server) callConnectorMCP(conn connector, toolName string, args map[string]any, requestedTool string, message string, authorization string) ([]map[string]any, map[string]any, string, error) {
	var err error
	authorization, err = connectorAuthorization(conn, authorization)
	if err != nil {
		return nil, nil, "", err
	}
	return s.callMCPResolved(conn.URL, conn.InternalURL, toolName, args, requestedTool, message, authorization, connectorAllowsLocalBearerFallback(conn))
}

func connectorAuthorization(conn connector, forwardedAuthorization string) (string, error) {
	forwardedAuthorization = strings.TrimSpace(forwardedAuthorization)
	switch strings.ToLower(strings.TrimSpace(conn.Auth)) {
	case "sso_bearer":
		if forwardedAuthorization == "" {
			return "", fmt.Errorf("connector %q requires an SSO bearer token, but oauth2-proxy did not forward one to ChatGPT Sim", conn.Name)
		}
		return forwardedAuthorization, nil
	case "none", "anonymous":
		return "", nil
	default:
		return forwardedAuthorization, nil
	}
}

func connectorAllowsLocalBearerFallback(conn connector) bool {
	switch strings.ToLower(strings.TrimSpace(conn.Auth)) {
	case "none", "anonymous", "sso_bearer":
		return false
	default:
		return true
	}
}

func (s *server) callMCPResolved(mcpURL string, internalURL string, toolName string, args map[string]any, requestedTool string, message string, authorization string, allowLocalBearerFallback bool) ([]map[string]any, map[string]any, string, error) {
	hostOverride := s.mcpHostOverride(mcpURL, internalURL)
	mcpURL = s.resolveMCPURL(mcpURL, internalURL)
	if authorization == "" && allowLocalBearerFallback {
		authorization = "Bearer local-chatgpt-go"
	}
	steps := []map[string]any{}
	post := func(id int, method string, params any) (map[string]any, error) {
		payload := map[string]any{"jsonrpc": "2.0", "id": id, "method": method}
		if params != nil {
			payload["params"] = params
		}
		body, _ := json.Marshal(payload)
		req, err := http.NewRequest(http.MethodPost, mcpURL, strings.NewReader(string(body)))
		if err != nil {
			return nil, err
		}
		if hostOverride != "" {
			req.Host = hostOverride
		}
		req.Header.Set("Accept", "application/json, text/event-stream")
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", authorization)
		resp, err := s.client.Do(req)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()
		respBody, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
		if err != nil {
			return nil, err
		}
		var rpc map[string]any
		if err := json.Unmarshal(respBody, &rpc); err != nil {
			return nil, err
		}
		steps = append(steps, map[string]any{"method": method, "status": resp.StatusCode, "response": rpc})
		if resp.StatusCode < 200 || resp.StatusCode > 299 {
			return nil, fmt.Errorf("%s from %s%s", resp.Status, method, httpErrorSuffix(rpc, respBody))
		}
		if _, ok := rpc["error"]; ok {
			return nil, errors.New("json-rpc error from " + method + rpcErrorSuffix(rpc["error"]))
		}
		return rpc, nil
	}
	if _, err := post(1, "initialize", map[string]any{"protocolVersion": "2025-06-18", "capabilities": map[string]any{}, "clientInfo": map[string]string{"name": "go-local-chatgpt", "version": "0.1.0"}}); err != nil {
		return nil, nil, "", err
	}
	tools, err := post(2, "tools/list", nil)
	if err != nil {
		return nil, nil, "", err
	}
	if toolName == "tools/list" {
		return steps, discoveredToolsResult(tools), toolName, nil
	}
	if !toolAdvertised(tools, toolName) {
		if requestedTool == "" || requestedTool == "auto" {
			toolName, args = chooseAdvertisedTool(tools, message)
			if toolName == "tools/list" {
				return steps, discoveredToolsResult(tools), toolName, nil
			}
		}
	}
	if !toolAdvertised(tools, toolName) {
		return nil, nil, "", errors.New("tool is not advertised: " + toolName)
	}
	result, err := post(3, "tools/call", map[string]any{"name": toolName, "arguments": args})
	if err != nil {
		return nil, nil, "", err
	}
	if resultMap, ok := result["result"].(map[string]any); ok {
		return steps, resultMap, toolName, nil
	}
	return steps, map[string]any{}, toolName, nil
}

func rpcErrorSuffix(value any) string {
	rpcError, ok := value.(map[string]any)
	if !ok {
		return ""
	}
	message := stringValue(rpcError["message"])
	if strings.TrimSpace(message) == "" {
		return ""
	}
	return ": " + message
}

func httpErrorSuffix(rpc map[string]any, body []byte) string {
	for _, key := range []string{"detail", "error", "message"} {
		if value := stringValue(rpc[key]); strings.TrimSpace(value) != "" {
			return ": " + value
		}
	}
	text := strings.TrimSpace(string(body))
	if text == "" {
		return ""
	}
	if len(text) > 240 {
		text = text[:240] + "..."
	}
	return ": " + text
}

func (s *server) resolveMCPURL(mcpURL string, internalURL string) string {
	if internalURL == "" {
		return mcpURL
	}
	parsed, err := url.Parse(mcpURL)
	if err != nil {
		return mcpURL
	}
	if parsed.Host == "" || strings.Contains(parsed.Host, "mcpserver.") || strings.Contains(parsed.Host, "mcp.") {
		return internalURL
	}
	return mcpURL
}

func (s *server) mcpHostOverride(mcpURL string, internalURL string) string {
	if internalURL == "" {
		return ""
	}
	parsed, err := url.Parse(mcpURL)
	if err != nil || parsed.Host == "" {
		return ""
	}
	if strings.Contains(parsed.Host, "mcpserver.") || strings.Contains(parsed.Host, "mcp.") {
		return parsed.Host
	}
	return ""
}

func outboundAuthorization(r *http.Request) string {
	if value := strings.TrimSpace(r.Header.Get("Authorization")); strings.HasPrefix(value, "Bearer ") {
		return value
	}
	for _, header := range []string{"X-Forwarded-Access-Token", "X-Auth-Request-Access-Token"} {
		if value := strings.TrimSpace(r.Header.Get(header)); value != "" {
			return "Bearer " + value
		}
	}
	return ""
}

func mcpTools() []map[string]any {
	names := []string{"whoami", "route_trace", "model_ping", "model_catalogue", "explain_route", "service_health", "security_posture", "collect_evidence", "infer"}
	tools := make([]map[string]any, 0, len(names))
	for _, name := range names {
		tools = append(tools, map[string]any{
			"name":        name,
			"title":       titleForTool(name),
			"description": "Local deterministic MCP demo tool.",
			"inputSchema": map[string]any{"type": "object", "properties": map[string]any{}},
			"annotations": map[string]any{"readOnlyHint": true, "destructiveHint": false, "openWorldHint": false},
			"_meta":       map[string]any{"securitySchemes": []map[string]any{{"type": "oauth2", "scopes": []string{"mcp.access"}}}},
		})
	}
	return tools
}

func toolResult(name string, args map[string]any) map[string]any {
	content := structuredContent(name, args)
	text, _ := json.MarshalIndent(content, "", "  ")
	return map[string]any{
		"content":           []map[string]any{{"type": "text", "text": string(text)}},
		"structuredContent": content,
		"isError":           false,
	}
}

func structuredContent(name string, args map[string]any) map[string]any {
	switch name {
	case "whoami":
		return map[string]any{"issuer": "go-local-mcp", "subject": "local-chatgpt-go-user", "audience": "go-local-mcp", "scopes": []string{"mcp.access"}, "client_id": "go-local-chatgpt"}
	case "route_trace":
		return routeEvidence()
	case "model_ping":
		return map[string]any{"provider": "deterministic-go", "deployment_name": "none", "latency_ms": 0.1, "response": "pong", "success": true}
	case "model_catalogue":
		return map[string]any{"targets": []any{}, "policy": map[string]any{"llm_backend": "not_configured", "mcp_results_only": true}}
	case "explain_route":
		return map[string]any{"decision": "allowed", "reason": "local deterministic route", "route": map[string]any{"adapter": "go-local"}, "constraints": map[string]any{"network": "local"}}
	case "service_health":
		return map[string]any{"status": "ok", "components": map[string]any{"mcp": "ok", "model": "deterministic"}}
	case "security_posture":
		return map[string]any{"token_policy": map[string]any{"mode": "local bearer required"}, "edge_trust": map[string]any{"required": false}, "apim": map[string]any{"present": false}, "inference": map[string]any{"llm_backend": false}}
	case "infer":
		return map[string]any{"status": "accepted", "adapter_path": "deterministic-go", "prompt": args["prompt"], "response_summary": "local MCP result, no LLM backend"}
	default:
		return map[string]any{"route": routeEvidence(), "model": map[string]any{"provider": "none"}, "security": map[string]any{"mode": "local"}}
	}
}

func routeEvidence() map[string]any {
	return map[string]any{"cloudflare": map[string]any{"present": false, "ray_id": ""}, "app_gateway": map[string]any{"present": false, "trace_id": ""}, "apim": map[string]any{"present": false, "validated": false}, "aca": map[string]any{"present": false, "revision": ""}}
}

func chooseTool(requested, message string) (string, map[string]any) {
	if requested != "" && requested != "auto" {
		return requested, argsForTool(requested, message)
	}
	lower := strings.ToLower(message)
	switch {
	case wantsDiscovery(lower):
		return "tools/list", nil
	case strings.Contains(lower, "who") || strings.Contains(lower, "identity"):
		return "whoami", nil
	case strings.Contains(lower, "route") || strings.Contains(lower, "path"):
		return "route_trace", nil
	case strings.Contains(lower, "security"):
		return "security_posture", nil
	case strings.Contains(lower, "health"):
		return "service_health", nil
	case strings.Contains(lower, "catalog") || strings.Contains(lower, "model"):
		return "model_catalogue", nil
	case strings.Contains(lower, "infer") || strings.Contains(lower, "prompt"):
		return "infer", argsForTool("infer", message)
	default:
		return "collect_evidence", nil
	}
}

func chooseAdvertisedTool(rpc map[string]any, message string) (string, map[string]any) {
	names := advertisedToolNames(rpc)
	has := func(candidates ...string) (string, bool) {
		for _, candidate := range candidates {
			for _, name := range names {
				if name == candidate {
					return name, true
				}
			}
		}
		return "", false
	}
	lower := strings.ToLower(message)
	switch {
	case wantsDiscovery(lower):
		return "tools/list", nil
	case strings.Contains(lower, "who") || strings.Contains(lower, "identity"):
		if name, ok := has("whoami", "identity", "user_info", "userinfo", "profile", "me"); ok {
			return name, argsForTool(name, message)
		}
		return "tools/list", nil
	case strings.Contains(lower, "route") || strings.Contains(lower, "path"):
		if name, ok := has("route_trace", "explain_route", "collect_evidence"); ok {
			return name, argsForTool(name, message)
		}
		return "tools/list", nil
	case strings.Contains(lower, "security"):
		if name, ok := has("security_posture", "collect_evidence"); ok {
			return name, argsForTool(name, message)
		}
		return "tools/list", nil
	case strings.Contains(lower, "health"):
		if name, ok := has("service_health"); ok {
			return name, argsForTool(name, message)
		}
		return "tools/list", nil
	case strings.Contains(lower, "catalog") || strings.Contains(lower, "model") || strings.Contains(lower, "infer") || strings.Contains(lower, "prompt"):
		if name, ok := has("model_catalogue", "model_ping", "infer"); ok {
			return name, argsForTool(name, message)
		}
	}
	if name, ok := has("model_ping", "infer", "collect_evidence"); ok {
		return name, argsForTool(name, message)
	}
	if len(names) > 0 {
		return names[0], argsForTool(names[0], message)
	}
	return "tools/list", nil
}

func wantsDiscovery(lower string) bool {
	if strings.Contains(lower, "what tools") ||
		strings.Contains(lower, "which tools") ||
		strings.Contains(lower, "tools did") ||
		strings.Contains(lower, "discovered") {
		return true
	}
	hasExampleVerb := strings.Contains(lower, "example") ||
		strings.Contains(lower, "list") ||
		strings.Contains(lower, "show") ||
		strings.Contains(lower, "give me")
	hasInventoryNoun := strings.Contains(lower, "route") ||
		strings.Contains(lower, "tool") ||
		strings.Contains(lower, "capabilit")
	return hasExampleVerb && hasInventoryNoun
}

func advertisedToolNames(rpc map[string]any) []string {
	result, _ := rpc["result"].(map[string]any)
	tools, _ := result["tools"].([]any)
	names := make([]string, 0, len(tools))
	for _, item := range tools {
		tool, _ := item.(map[string]any)
		if name := stringValue(tool["name"]); name != "" {
			names = append(names, name)
		}
	}
	return names
}

func argsForTool(tool, message string) map[string]any {
	if tool == "infer" {
		return map[string]any{"prompt": message, "model_class": "diagnostic", "data_residency": "eu", "purpose": "local-go-shell", "max_tokens": 128}
	}
	if tool == "model_ping" {
		return map[string]any{"prompt": message}
	}
	return map[string]any{}
}

func deterministicReply(tool string, result map[string]any) string {
	content, _ := result["structuredContent"].(map[string]any)
	switch tool {
	case "tools/list":
		return describeDiscoveredTools(content)
	case "whoami":
		subject := stringValue(content["subject"])
		if subject == "" {
			subject = "unidentified"
		}
		return "The Go MCP server accepted the local ChatGPT identity `" + subject + "`."
	case "route_trace":
		return "The Go MCP server returned local route evidence. The inspector shows the full JSON."
	case "infer":
		return "The Go MCP infer tool returned a deterministic result without calling an LLM backend."
	case "model_ping":
		var payload struct {
			Success bool   `json:"success"`
			Route   string `json:"route"`
			Model   string `json:"model"`
		}
		if err := json.Unmarshal([]byte(extractMCPText(result)), &payload); err == nil && payload.Success {
			route := payload.Route
			if route == "" {
				route = "agentgateway"
			}
			model := payload.Model
			if model == "" {
				model = "the discovered model"
			}
			return "Yes. The MCP server reached " + model + " through " + route + "."
		}
		return "The MCP server called model_ping; the inspector shows the full gateway result."
	default:
		return "The Go shell called `" + tool + "` and received deterministic MCP data."
	}
}

func discoveredToolsResult(rpc map[string]any) map[string]any {
	result, _ := rpc["result"].(map[string]any)
	tools, _ := result["tools"].([]any)
	summaries := make([]map[string]any, 0, len(tools))
	for _, item := range tools {
		tool, _ := item.(map[string]any)
		name := stringValue(tool["name"])
		if name == "" {
			continue
		}
		title := stringValue(tool["title"])
		description := stringValue(tool["description"])
		summaries = append(summaries, map[string]any{
			"name":        name,
			"title":       title,
			"description": description,
		})
	}
	text, _ := json.MarshalIndent(summaries, "", "  ")
	return map[string]any{
		"content":           []map[string]any{{"type": "text", "text": string(text)}},
		"structuredContent": map[string]any{"tools": summaries, "count": len(summaries)},
		"isError":           false,
	}
}

func describeDiscoveredTools(content map[string]any) string {
	names := []string{}
	switch tools := content["tools"].(type) {
	case []map[string]any:
		for _, tool := range tools {
			if name := stringValue(tool["name"]); name != "" {
				names = append(names, "`"+name+"`")
			}
		}
	case []any:
		for _, item := range tools {
			tool, _ := item.(map[string]any)
			if name := stringValue(tool["name"]); name != "" {
				names = append(names, "`"+name+"`")
			}
		}
	}
	if len(names) == 0 {
		return "I discovered the MCP server, but it did not advertise any tools."
	}
	return "I discovered " + fmt.Sprint(content["count"]) + " MCP tools: " + strings.Join(names, ", ") + ". I can choose one based on your next message or you can pick one from the tool selector."
}

func toolAdvertised(rpc map[string]any, toolName string) bool {
	result, _ := rpc["result"].(map[string]any)
	tools, _ := result["tools"].([]any)
	for _, item := range tools {
		tool, _ := item.(map[string]any)
		if tool["name"] == toolName {
			return true
		}
	}
	return false
}

func widgetResource() map[string]any {
	return map[string]any{"uri": "ui://pce-go/proof-panel.v1.html", "name": "go-proof-panel", "mimeType": "text/html;profile=mcp-app", "_meta": map[string]any{"openai/widgetCSP": map[string]any{"connect_domains": []string{}, "resource_domains": []string{}}}}
}

func titleForTool(name string) string {
	return strings.ReplaceAll(name, "_", " ")
}

func writeRPC(w http.ResponseWriter, id any, result any) {
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{"jsonrpc": "2.0", "id": id, "result": result})
}

func writeRPCError(w http.ResponseWriter, id any, code int, message string) {
	apphttp.WriteJSON(w, http.StatusOK, map[string]any{"jsonrpc": "2.0", "id": id, "error": map[string]any{"code": code, "message": message}})
}

func remarshal(in any, out any) error {
	data, err := json.Marshal(in)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, out)
}

func stringValue(value any) string {
	if text, ok := value.(string); ok {
		return strings.TrimSpace(text)
	}
	return ""
}

func callbackHTML(title string, body string) string {
	return `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>` + htmlEscape(title) + `</title><style>body{background:#101114;color:#f4f6f8;font-family:system-ui,sans-serif;margin:2rem}pre{white-space:pre-wrap;background:#17191f;border:1px solid #343946;border-radius:8px;padding:1rem}</style></head><body><h1>` + htmlEscape(title) + `</h1><pre>` + htmlEscape(body) + `</pre></body></html>`
}

func htmlEscape(value string) string {
	replacer := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;", "'", "&#39;")
	return replacer.Replace(value)
}

type rpcRequest struct {
	JSONRPC string `json:"jsonrpc"`
	ID      any    `json:"id"`
	Method  string `json:"method"`
	Params  any    `json:"params"`
}

type toolCallParams struct {
	Name      string         `json:"name"`
	Arguments map[string]any `json:"arguments"`
}

type chatRequest struct {
	Message     string `json:"message"`
	Tool        string `json:"tool"`
	ConnectorID string `json:"connector_id"`
}

const proofWidgetHTML = `<!doctype html><html><body><main>Go local proof widget</main></body></html>`

type connectorRequest struct {
	Name                         string   `json:"name"`
	URL                          string   `json:"url"`
	Auth                         string   `json:"auth"`
	OAuthClientMode              string   `json:"oauth_client_mode"`
	OAuthClientID                string   `json:"oauth_client_id"`
	OAuthClientSecret            string   `json:"oauth_client_secret"`
	OAuthTokenEndpointAuthMethod string   `json:"oauth_token_endpoint_auth_method"`
	OAuthRequestedScopesRaw      string   `json:"oauth_requested_scopes"`
	OAuthBaseScopesRaw           string   `json:"oauth_base_scopes"`
	OAuthAuthorizationURL        string   `json:"oauth_authorization_url"`
	OAuthTokenURL                string   `json:"oauth_token_url"`
	OAuthRegistrationURL         string   `json:"oauth_registration_url"`
	OAuthAuthorizationServerBase string   `json:"oauth_authorization_server_base"`
	OAuthResource                string   `json:"oauth_resource"`
	OAuthOIDCConfigurationURL    string   `json:"oauth_oidc_configuration_url"`
	OAuthOIDCUserinfoEndpoint    string   `json:"oauth_oidc_userinfo_endpoint"`
	OAuthOIDCScopesSupportedRaw  string   `json:"oauth_oidc_scopes_supported"`
	OAuthRequestedScopes         []string `json:"-"`
	OAuthBaseScopes              []string `json:"-"`
	OAuthOIDCScopesSupported     []string `json:"-"`
}

type connector struct {
	ID            string         `json:"id"`
	Name          string         `json:"name"`
	URL           string         `json:"url"`
	InternalURL   string         `json:"internal_url,omitempty"`
	Auth          string         `json:"auth"`
	Status        string         `json:"status"`
	ClientID      string         `json:"oauth_client_id,omitempty"`
	LoginURL      string         `json:"login_url,omitempty"`
	OAuth         map[string]any `json:"oauth,omitempty"`
	OAuthAdvanced map[string]any `json:"oauth_advanced,omitempty"`
	Discovery     map[string]any `json:"discovery,omitempty"`
	Error         string         `json:"error,omitempty"`
}

func (r *connectorRequest) normalizeOAuthAdvanced() {
	r.OAuthClientMode = appconfig.StringDefault(strings.TrimSpace(r.OAuthClientMode), "USER_DEFINED")
	r.OAuthClientID = strings.TrimSpace(r.OAuthClientID)
	r.OAuthClientSecret = strings.TrimSpace(r.OAuthClientSecret)
	r.OAuthTokenEndpointAuthMethod = strings.TrimSpace(r.OAuthTokenEndpointAuthMethod)
	r.OAuthRequestedScopes = parseScopeList(r.OAuthRequestedScopesRaw)
	r.OAuthBaseScopes = parseScopeList(r.OAuthBaseScopesRaw)
	r.OAuthAuthorizationURL = strings.TrimSpace(r.OAuthAuthorizationURL)
	r.OAuthTokenURL = strings.TrimSpace(r.OAuthTokenURL)
	r.OAuthRegistrationURL = strings.TrimSpace(r.OAuthRegistrationURL)
	r.OAuthAuthorizationServerBase = strings.TrimRight(strings.TrimSpace(r.OAuthAuthorizationServerBase), "/")
	r.OAuthResource = strings.TrimSpace(r.OAuthResource)
	r.OAuthOIDCConfigurationURL = strings.TrimSpace(r.OAuthOIDCConfigurationURL)
	r.OAuthOIDCUserinfoEndpoint = strings.TrimSpace(r.OAuthOIDCUserinfoEndpoint)
	r.OAuthOIDCScopesSupported = parseScopeList(r.OAuthOIDCScopesSupportedRaw)
}

func (r connectorRequest) loginScopes() []string {
	return dedupeStrings(append(append([]string{}, r.OAuthBaseScopes...), r.OAuthRequestedScopes...))
}

func (r connectorRequest) advancedSummary() map[string]any {
	out := map[string]any{
		"registration_method":        r.OAuthClientMode,
		"client_secret_configured":   r.OAuthClientSecret != "",
		"default_scopes":             r.OAuthRequestedScopes,
		"base_scopes":                r.OAuthBaseScopes,
		"oidc_scopes_supported":      r.OAuthOIDCScopesSupported,
		"oidc_configuration_url":     r.OAuthOIDCConfigurationURL,
		"oidc_userinfo_endpoint":     r.OAuthOIDCUserinfoEndpoint,
		"authorization_server_base":  r.OAuthAuthorizationServerBase,
		"resource":                   r.OAuthResource,
		"token_endpoint_auth_method": r.OAuthTokenEndpointAuthMethod,
	}
	if r.OAuthClientID == "" &&
		r.OAuthClientSecret == "" &&
		r.OAuthTokenEndpointAuthMethod == "" &&
		len(r.OAuthRequestedScopes) == 0 &&
		len(r.OAuthBaseScopes) == 0 &&
		r.OAuthAuthorizationURL == "" &&
		r.OAuthTokenURL == "" &&
		r.OAuthRegistrationURL == "" &&
		r.OAuthAuthorizationServerBase == "" &&
		r.OAuthResource == "" &&
		r.OAuthOIDCConfigurationURL == "" &&
		r.OAuthOIDCUserinfoEndpoint == "" &&
		len(r.OAuthOIDCScopesSupported) == 0 {
		return nil
	}
	return out
}

func parseScopeList(raw string) []string {
	fields := strings.FieldsFunc(raw, func(r rune) bool {
		return r == ',' || r == '\n' || r == '\r' || r == '\t' || r == ' '
	})
	return dedupeStrings(fields)
}

func dedupeStrings(values []string) []string {
	seen := map[string]bool{}
	out := []string{}
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" || seen[value] {
			continue
		}
		seen[value] = true
		out = append(out, value)
	}
	return out
}
