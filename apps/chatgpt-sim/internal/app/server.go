package app

import (
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

//go:embed web/*
var web embed.FS

type HTTPDoer interface {
	Do(*http.Request) (*http.Response, error)
}

type server struct {
	cfg        Config
	client     HTTPDoer
	mu         sync.Mutex
	connectors []connector
	nextID     int
}

func NewServer(cfg Config, client HTTPDoer) http.Handler {
	if client == nil {
		client = http.DefaultClient
	}
	s := &server{cfg: cfg, client: client, nextID: 2}
	if cfg.MCPURL != "" {
		s.connectors = []connector{{
			ID:     "default",
			Name:   "Local Go MCP",
			URL:    cfg.MCPURL,
			Auth:   "local_bearer",
			Status: "configured",
		}}
	}
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
		mux.HandleFunc("GET /api/discovery", s.shellDiscovery)
		mux.HandleFunc("GET /api/connectors", s.listConnectors)
		mux.HandleFunc("POST /api/connectors", s.addConnector)
		mux.HandleFunc("DELETE /api/connectors/{id}", s.deleteConnector)
		mux.HandleFunc("POST /api/chat", s.shellChat)
		mux.HandleFunc("GET /runtime-config.js", s.runtimeConfig)
		mux.HandleFunc("GET /favicon.ico", s.favicon)
		mux.HandleFunc("GET /oauth/callback", s.oauthCallback)
		mux.HandleFunc("/", s.static)
	}
	return logMiddleware(mux)
}

func (s *server) mcpHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok", "service": "go-local-mcp"})
}

func (s *server) llmHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok", "service": "go-local-openai-compatible-llm"})
}

func (s *server) llmModels(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"object": "list",
		"data": []map[string]any{{
			"id":       s.localLLMModel(),
			"object":   "model",
			"owned_by": "platform",
		}},
	})
}

func (s *server) shellHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":         "ok",
		"service":        "chatgpt-sim-shell",
		"mcp_url":        s.cfg.MCPURL,
		"model_provider": s.modelProvider(),
		"dependencies":   "go-stdlib-only",
	})
}

func (s *server) llmChatCompletions(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Model    string `json:"model"`
		Messages []struct {
			Role    string `json:"role"`
			Content string `json:"content"`
		} `json:"messages"`
	}
	if !decodeJSON(w, r, &req) {
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
	subject := "unknown"
	if strings.Contains(mcpContext, "local-chatgpt-go-user") {
		subject = "local-chatgpt-go-user"
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"model": req.Model,
		"choices": []map[string]any{{
			"index": 0,
			"message": map[string]string{
				"role":    "assistant",
				"content": "OpenAI-compatible local model saw `" + userMessage + "` and the MCP subject `" + subject + "`.",
			},
			"finish_reason": "stop",
		}},
	})
}

func (s *server) protectedResourceMetadata(w http.ResponseWriter, r *http.Request) {
	baseURL := s.publicBaseURL(r)
	writeJSON(w, http.StatusOK, map[string]any{
		"resource":                 baseURL + "/mcp",
		"authorization_servers":    []string{baseURL},
		"scopes_supported":         []string{"mcp.access"},
		"bearer_methods_supported": []string{"header"},
	})
}

func (s *server) oauthAuthorizationServer(w http.ResponseWriter, r *http.Request) {
	baseURL := s.publicBaseURL(r)
	writeJSON(w, http.StatusOK, map[string]any{
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
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing bearer token"})
		return
	}
	var req rpcRequest
	if !decodeJSON(w, r, &req) {
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
	discovery, err := s.discover(conn.URL, outboundAuthorization(r))
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, discovery)
}

func (s *server) shellChat(w http.ResponseWriter, r *http.Request) {
	var req chatRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	req.Message = strings.TrimSpace(req.Message)
	if req.Message == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "message is required"})
		return
	}
	conn, ok := s.connectorByID(req.ConnectorID)
	if !ok {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "connector not found"})
		return
	}
	discovery, err := s.discover(conn.URL, outboundAuthorization(r))
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
	toolName, args := chooseTool(req.Tool, req.Message)
	steps, result, selectedTool, err := s.callMCP(conn.URL, toolName, args, req.Tool, req.Message, outboundAuthorization(r))
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
		return
	}
	toolName = selectedTool
	assistant := deterministicReply(toolName, result)
	model := map[string]string{"provider": "deterministic", "model": "go-local-rule"}
	if s.cfg.LLMURL != "" {
		var modelName string
		assistant, modelName, err = s.completeWithLLM(req.Message, toolName, result)
		if err != nil {
			writeJSON(w, http.StatusBadGateway, map[string]string{"error": err.Error()})
			return
		}
		if isUnusableAssistantText(assistant) {
			assistant = deterministicReply(toolName, result)
		}
		model = map[string]string{"provider": "openai-compatible", "model": modelName, "route": "agentgateway"}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"assistant":      assistant,
		"connector":      conn,
		"model":          model,
		"selected_tool":  toolName,
		"tool_arguments": args,
		"tool_result":    result,
		"discovery":      discovery,
		"mcp_steps":      steps,
	})
}

func (s *server) completeWithLLM(message string, toolName string, toolResult map[string]any) (string, string, error) {
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
				"content": "You are ChatGPT Sim. The platform shell has already executed the selected MCP tool. Answer the user from the observed MCP tool result. Do not say you need to call the tool, and do not invent tool results.",
			},
			{"role": "user", "content": message},
			{
				"role": "user",
				"content": "Observed MCP tool result.\nSelected MCP tool: " + toolName +
					"\nMCP tool result text: " + toolText +
					"\nMCP tool result JSON: " + string(contextJSON),
			},
		},
		"max_tokens": 256,
	}
	body, _ := json.Marshal(payload)
	req, err := http.NewRequest(http.MethodPost, s.cfg.LLMURL, strings.NewReader(string(body)))
	if err != nil {
		return "", "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	resp, err := s.client.Do(req)
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
	if err := json.NewDecoder(resp.Body).Decode(&completion); err != nil {
		return "", "", err
	}
	if len(completion.Choices) == 0 || strings.TrimSpace(completion.Choices[0].Message.Content) == "" {
		return "", "", errors.New("empty LLM completion")
	}
	return cleanAssistantText(completion.Choices[0].Message.Content), modelName, nil
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
	if err := json.NewDecoder(resp.Body).Decode(&models); err != nil {
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
	return "go-local-openai-compatible"
}

func (s *server) listConnectors(w http.ResponseWriter, _ *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]any{"items": s.connectors})
}

func (s *server) addConnector(w http.ResponseWriter, r *http.Request) {
	var req connectorRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	req.URL = normalizeConnectorURL(req.URL)
	if req.URL == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "mcp url is required"})
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
		writeJSON(w, http.StatusConflict, map[string]any{"error": "connector already exists", "connector": existing})
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
	writeJSON(w, http.StatusOK, conn)
}

func (s *server) deleteConnector(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.PathValue("id"))
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "connector id is required"})
		return
	}
	if id == "default" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "default connector cannot be deleted"})
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
	writeJSON(w, http.StatusNotFound, map[string]string{"error": "connector not found"})
}

func (s *server) runtimeConfig(w http.ResponseWriter, _ *http.Request) {
	setFrontendCacheHeaders(w)
	w.Header().Set("Content-Type", "application/javascript")
	_, _ = w.Write([]byte("window.PCE_CHATGPT_GO_CONFIG = "))
	_ = json.NewEncoder(w).Encode(map[string]any{
		"mcpUrl":        s.cfg.MCPURL,
		"modelProvider": s.modelProvider(),
		"dependencies":  "go-stdlib-only",
	})
}

func (s *server) modelProvider() string {
	if s.cfg.LLMURL != "" {
		return "openai-compatible via agentgateway"
	}
	return "deterministic"
}

func (s *server) oauthCallback(w http.ResponseWriter, r *http.Request) {
	setFrontendCacheHeaders(w)
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

func (s *server) static(w http.ResponseWriter, r *http.Request) {
	sub, err := fs.Sub(web, "web")
	if err != nil {
		http.Error(w, "static assets unavailable", http.StatusInternalServerError)
		return
	}
	setFrontendCacheHeaders(w)
	http.FileServer(http.FS(sub)).ServeHTTP(w, r)
}

func (s *server) favicon(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "image/svg+xml")
	_, _ = w.Write([]byte(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="10" fill="#14171d"/><path d="M16 18h32M16 32h22M16 46h28" stroke="#79d89f" stroke-width="6" stroke-linecap="round"/></svg>`))
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

func (s *server) discover(mcpURL string, authorization string) (map[string]any, error) {
	resolvedURL := s.resolveMCPURL(mcpURL)
	hostOverride := s.mcpHostOverride(mcpURL)
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
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
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
			if endpoint := stringValue(metadata["authorization_endpoint"]); endpoint != "unknown" {
				return endpoint
			}
		}
	}
	return ""
}

func loginScopesFromDiscovery(discovery map[string]any) []string {
	if protected, ok := discovery["protected_resource"].(map[string]any); ok {
		if scopes, ok := protected["scopes_supported"].([]any); ok && len(scopes) > 0 {
			if scope := stringValue(scopes[0]); scope != "unknown" {
				return []string{scope}
			}
		}
	}
	if metadata, ok := discovery["oauth_authorization_server"].(map[string]any); ok {
		if scopes, ok := metadata["scopes_supported"].([]any); ok && len(scopes) > 0 {
			if scope := stringValue(scopes[0]); scope != "unknown" {
				return []string{scope}
			}
		}
	}
	return []string{"openid"}
}

func (s *server) callMCP(mcpURL string, toolName string, args map[string]any, requestedTool string, message string, authorization string) ([]map[string]any, map[string]any, string, error) {
	hostOverride := s.mcpHostOverride(mcpURL)
	mcpURL = s.resolveMCPURL(mcpURL)
	if authorization == "" {
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
		var rpc map[string]any
		if err := json.NewDecoder(resp.Body).Decode(&rpc); err != nil {
			return nil, err
		}
		steps = append(steps, map[string]any{"method": method, "status": resp.StatusCode, "response": rpc})
		if resp.StatusCode < 200 || resp.StatusCode > 299 {
			return nil, errors.New(resp.Status)
		}
		if _, ok := rpc["error"]; ok {
			return nil, errors.New("json-rpc error from " + method)
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

func (s *server) resolveMCPURL(mcpURL string) string {
	if s.cfg.MCPInternalURL == "" {
		return mcpURL
	}
	parsed, err := url.Parse(mcpURL)
	if err != nil {
		return mcpURL
	}
	if parsed.Host == "" || strings.Contains(parsed.Host, "mcpserver.") || strings.Contains(parsed.Host, "mcp.") {
		return s.cfg.MCPInternalURL
	}
	return mcpURL
}

func (s *server) mcpHostOverride(mcpURL string) string {
	if s.cfg.MCPInternalURL == "" {
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
	case strings.Contains(lower, "what tools") || strings.Contains(lower, "which tools") || strings.Contains(lower, "tools did") || strings.Contains(lower, "discovered"):
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
	case strings.Contains(lower, "what tools") || strings.Contains(lower, "which tools") || strings.Contains(lower, "tools did") || strings.Contains(lower, "discovered"):
		return "tools/list", nil
	case strings.Contains(lower, "who") || strings.Contains(lower, "identity"):
		if name, ok := has("whoami", "identity", "user_info", "userinfo", "profile", "me", "model_ping"); ok {
			return name, argsForTool(name, message)
		}
	case strings.Contains(lower, "route") || strings.Contains(lower, "path"):
		if name, ok := has("route_trace", "explain_route", "collect_evidence", "model_ping"); ok {
			return name, argsForTool(name, message)
		}
	case strings.Contains(lower, "security"):
		if name, ok := has("security_posture", "collect_evidence", "model_ping"); ok {
			return name, argsForTool(name, message)
		}
	case strings.Contains(lower, "health"):
		if name, ok := has("service_health", "model_ping"); ok {
			return name, argsForTool(name, message)
		}
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

func advertisedToolNames(rpc map[string]any) []string {
	result, _ := rpc["result"].(map[string]any)
	tools, _ := result["tools"].([]any)
	names := make([]string, 0, len(tools))
	for _, item := range tools {
		tool, _ := item.(map[string]any)
		if name := stringValue(tool["name"]); name != "unknown" {
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
		return "The Go MCP server accepted the local ChatGPT identity `" + stringValue(content["subject"]) + "`."
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
			if name := stringValue(tool["name"]); name != "unknown" {
				names = append(names, "`"+name+"`")
			}
		}
	case []any:
		for _, item := range tools {
			tool, _ := item.(map[string]any)
			if name := stringValue(tool["name"]); name != "unknown" {
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
	writeJSON(w, http.StatusOK, map[string]any{"jsonrpc": "2.0", "id": id, "result": result})
}

func writeRPCError(w http.ResponseWriter, id any, code int, message string) {
	writeJSON(w, http.StatusOK, map[string]any{"jsonrpc": "2.0", "id": id, "error": map[string]any{"code": code, "message": message}})
}

func decodeJSON(w http.ResponseWriter, r *http.Request, out any) bool {
	defer r.Body.Close()
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(out); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON body"})
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func setFrontendCacheHeaders(w http.ResponseWriter) {
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate, max-age=0")
	w.Header().Set("Pragma", "no-cache")
	w.Header().Set("Expires", "0")
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
		return text
	}
	return "unknown"
}

func callbackHTML(title string, body string) string {
	return `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>` + htmlEscape(title) + `</title><style>body{background:#101114;color:#f4f6f8;font-family:system-ui,sans-serif;margin:2rem}pre{white-space:pre-wrap;background:#17191f;border:1px solid #343946;border-radius:8px;padding:1rem}</style></head><body><h1>` + htmlEscape(title) + `</h1><pre>` + htmlEscape(body) + `</pre></body></html>`
}

func htmlEscape(value string) string {
	replacer := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;", "'", "&#39;")
	return replacer.Replace(value)
}

func logMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		next.ServeHTTP(w, r)
		_ = started
	})
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
	r.OAuthClientMode = defaultString(strings.TrimSpace(r.OAuthClientMode), "USER_DEFINED")
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

func defaultString(value string, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}
