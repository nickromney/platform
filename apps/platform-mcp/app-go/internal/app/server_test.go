package app

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestMCPInitializeAndToolsList(t *testing.T) {
	srv := NewServer(Config{PublicBaseURL: "https://mcpserver.dev.127.0.0.1.sslip.io"})

	req := httptest.NewRequest(http.MethodPost, "/mcp", strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"initialize"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("initialize returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"protocolVersion"`) || !strings.Contains(rec.Body.String(), `"platform-mcp"`) {
		t.Fatalf("initialize response missing MCP server info: %s", rec.Body.String())
	}

	req = httptest.NewRequest(http.MethodPost, "/mcp", strings.NewReader(`{"jsonrpc":"2.0","id":2,"method":"tools/list"}`))
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("tools/list returned %d: %s", rec.Code, rec.Body.String())
	}
	for _, want := range []string{`"model_ping"`, `"d2_validate"`, `"d2_render"`} {
		if !strings.Contains(rec.Body.String(), want) {
			t.Fatalf("tools/list missing %s tool: %s", want, rec.Body.String())
		}
	}
}

func TestWellKnownOAuthMetadataAliasesExposeProtectedResource(t *testing.T) {
	srv := NewServer(Config{PublicBaseURL: "https://mcpserver.dev.127.0.0.1.sslip.io"})

	for _, path := range []string{
		"/.well-known",
		"/.well-known/oauth-protected-resource",
		"/.well-known/oauth-protected-resource/mcp",
	} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		rec := httptest.NewRecorder()
		srv.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("%s returned %d: %s", path, rec.Code, rec.Body.String())
		}
		body := rec.Body.String()
		if !strings.Contains(body, `"resource":"https://mcpserver.dev.127.0.0.1.sslip.io/mcp"`) {
			t.Fatalf("%s metadata missing resource: %s", path, body)
		}
		if !strings.Contains(body, `"authorization_servers"`) {
			t.Fatalf("%s metadata missing authorization_servers: %s", path, body)
		}
	}
}

func TestA2AAgentCardAdvertisesJSONRPCModelPing(t *testing.T) {
	srv := NewServer(Config{PublicBaseURL: "https://mcpserver.dev.127.0.0.1.sslip.io"})

	for _, path := range []string{"/.well-known/agent-card.json", "/a2a/.well-known/agent-card.json"} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		rec := httptest.NewRecorder()
		srv.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("%s agent card returned %d: %s", path, rec.Code, rec.Body.String())
		}
		body := rec.Body.String()
		for _, want := range []string{
			`"protocolVersion"`,
			`"url":"https://mcpserver.dev.127.0.0.1.sslip.io/a2a"`,
			`"preferredTransport":"JSONRPC"`,
			`"model_ping"`,
			`"agentgateway"`,
		} {
			if !strings.Contains(body, want) {
				t.Fatalf("%s agent card missing %s: %s", path, want, body)
			}
		}
	}
}

func TestA2AMessageSendUsesOpenAICompatibleEndpointThroughAgentgateway(t *testing.T) {
	var seenPath string
	var seenModel string
	llm := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"object":"list","data":[{"id":"a2a-served-model"}]}`))
		case "/v1/chat/completions":
			seenPath = r.URL.Path
			var payload map[string]any
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				t.Fatal(err)
			}
			seenModel, _ = payload["model"].(string)
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"a2a agentgateway ok"}}],"model":"a2a-served-model"}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer llm.Close()

	srv := NewServer(Config{LLMBaseURL: llm.URL + "/v1"})
	req := httptest.NewRequest(http.MethodPost, "/a2a", strings.NewReader(`{"jsonrpc":"2.0","id":"a2a-1","method":"message/send","params":{"message":{"role":"user","parts":[{"kind":"text","text":"can you reach the model gateway?"}]}}}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("a2a message/send returned %d: %s", rec.Code, rec.Body.String())
	}
	if seenPath != "/v1/chat/completions" {
		t.Fatalf("llm path=%q", seenPath)
	}
	if seenModel != "a2a-served-model" {
		t.Fatalf("llm model=%q", seenModel)
	}
	body := rec.Body.String()
	for _, want := range []string{`"kind":"message"`, `"role":"agent"`, `a2a agentgateway ok`, `\"route\": \"agentgateway\"`} {
		if !strings.Contains(body, want) {
			t.Fatalf("a2a response missing %s: %s", want, body)
		}
	}
}

func TestModelPingUsesOpenAICompatibleEndpointThroughAgentgateway(t *testing.T) {
	var seenPath string
	var seenModel string
	var seenMaxTokens float64
	llm := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seenPath = r.URL.Path
		if r.Method != http.MethodPost {
			t.Fatalf("llm method=%s", r.Method)
		}
		if r.Header.Get("Content-Type") != "application/json" {
			t.Fatalf("llm content-type=%q", r.Header.Get("Content-Type"))
		}
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatal(err)
		}
		seenModel, _ = payload["model"].(string)
		seenMaxTokens, _ = payload["max_tokens"].(float64)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"agentgateway ok"}}],"model":"configured-test-model"}`))
	}))
	defer llm.Close()

	srv := NewServer(Config{
		LLMBaseURL: llm.URL + "/v1",
		LLMModel:   "configured-test-model",
	})
	req := httptest.NewRequest(http.MethodPost, "/mcp", strings.NewReader(`{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"model_ping","arguments":{"prompt":"hello"}}}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("tools/call returned %d: %s", rec.Code, rec.Body.String())
	}
	if seenPath != "/v1/chat/completions" {
		t.Fatalf("llm path=%q", seenPath)
	}
	if seenModel != "configured-test-model" {
		t.Fatalf("llm model=%q", seenModel)
	}
	if seenMaxTokens != 64 {
		t.Fatalf("llm max_tokens=%v", seenMaxTokens)
	}
	if !strings.Contains(rec.Body.String(), "agentgateway ok") {
		t.Fatalf("tool result did not include model response: %s", rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `\"success\": true`) || !strings.Contains(rec.Body.String(), `\"route\": \"agentgateway\"`) {
		t.Fatalf("tool result did not include structured model_ping success envelope: %s", rec.Body.String())
	}
}

func TestModelPingDiscoversOpenAICompatibleModelWhenNotConfigured(t *testing.T) {
	var seenModel string
	llm := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"object":"list","data":[{"id":"served-platform-model"}]}`))
		case "/v1/chat/completions":
			var payload map[string]any
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				t.Fatal(err)
			}
			seenModel, _ = payload["model"].(string)
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"agentgateway ok"}}],"model":"served-platform-model"}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer llm.Close()

	srv := NewServer(Config{LLMBaseURL: llm.URL + "/v1"})
	req := httptest.NewRequest(http.MethodPost, "/mcp", strings.NewReader(`{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"model_ping","arguments":{"prompt":"hello"}}}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("tools/call returned %d: %s", rec.Code, rec.Body.String())
	}
	if seenModel != "served-platform-model" {
		t.Fatalf("llm model=%q", seenModel)
	}
}

func TestD2RenderReturnsSVGArtifactForMCPInspectorSmoke(t *testing.T) {
	srv := NewServer(Config{PublicBaseURL: "https://mcpserver.dev.127.0.0.1.sslip.io"})

	req := httptest.NewRequest(http.MethodPost, "/mcp", strings.NewReader(`{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"d2_render","arguments":{"source":"a -> b","output_format":"svg"}}}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("tools/call returned %d: %s", rec.Code, rec.Body.String())
	}
	var rpc struct {
		Result struct {
			Content []struct {
				Text string `json:"text"`
			} `json:"content"`
		} `json:"result"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &rpc); err != nil {
		t.Fatalf("decode rpc response: %v", err)
	}
	if len(rpc.Result.Content) == 0 {
		t.Fatalf("d2_render missing text content: %s", rec.Body.String())
	}
	var payload struct {
		Status string `json:"status"`
		Data   struct {
			Artifact string `json:"artifact"`
		} `json:"data"`
	}
	if err := json.Unmarshal([]byte(rpc.Result.Content[0].Text), &payload); err != nil {
		t.Fatalf("decode d2 payload: %v", err)
	}
	if payload.Status != "ok" {
		t.Fatalf("d2_render status=%q", payload.Status)
	}
	if !strings.Contains(payload.Data.Artifact, "<svg") {
		t.Fatalf("d2_render artifact missing svg: %s", payload.Data.Artifact)
	}
}

func TestModelPingEmitsOpenLLMetryCompatibleOTLPSpan(t *testing.T) {
	spans := make(chan map[string]any, 1)
	collector := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/traces" {
			t.Fatalf("collector path=%q", r.URL.Path)
		}
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatalf("decode otlp body: %v", err)
		}
		spans <- body
		w.WriteHeader(http.StatusAccepted)
	}))
	defer collector.Close()

	llm := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"observed"}}],"model":"configured-test-model"}`))
	}))
	defer llm.Close()

	srv := NewServer(Config{
		LLMBaseURL:       llm.URL + "/v1",
		LLMModel:         "configured-test-model",
		OTLPEndpoint:     collector.URL,
		ServiceName:      "platform-mcp",
		ServiceNamespace: "platform",
	})
	req := httptest.NewRequest(http.MethodPost, "/mcp", strings.NewReader(`{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"model_ping","arguments":{"prompt":"trace me"}}}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("tools/call returned %d: %s", rec.Code, rec.Body.String())
	}
	payload := <-spans
	encoded, _ := json.Marshal(payload)
	text := string(encoded)
	for _, want := range []string{
		"openllmetry",
		"llm.openai.chat.completions",
		"gen_ai.system",
		"gen_ai.request.model",
		"configured-test-model",
		"mcp.tool.name",
		"model_ping",
		"agentgateway",
	} {
		if !strings.Contains(text, want) {
			t.Fatalf("OTLP span payload missing %q: %s", want, text)
		}
	}
}
