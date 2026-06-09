package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

const defaultIDPAPIBaseURL = "https://portal-api.127.0.0.1.sslip.io"

var idpAPIPaths = map[string]string{
	"runtime":           "/api/v1/runtime",
	"status":            "/api/v1/status",
	"catalogApps":       "/api/v1/catalog/apps",
	"deployments":       "/api/v1/deployments",
	"secrets":           "/api/v1/secrets",
	"scorecards":        "/api/v1/scorecards",
	"actions":           "/api/v1/actions",
	"environments":      "/api/v1/environments",
	"deploymentPromote": "/api/v1/deployments/promote",
}

type idpAPIClient struct {
	baseURL string
	client  *http.Client
}

type toolSpec struct {
	Description string                                           `json:"description"`
	InputSchema map[string]any                                   `json:"inputSchema"`
	Handler     func(*idpAPIClient, map[string]any) (any, error) `json:"-"`
}

var tools = map[string]toolSpec{
	"platform_status": {
		Description: "Read the platform status through the HTTP API.",
		InputSchema: map[string]any{"type": "object", "properties": map[string]any{}},
		Handler: func(client *idpAPIClient, _ map[string]any) (any, error) {
			return client.request("GET", idpAPIPaths["status"], nil)
		},
	},
	"catalog_list": {
		Description: "Read the platform IDP service catalog through the HTTP API.",
		InputSchema: map[string]any{"type": "object", "properties": map[string]any{}},
		Handler: func(client *idpAPIClient, _ map[string]any) (any, error) {
			return client.request("GET", idpAPIPaths["catalogApps"], nil)
		},
	},
	"environment_create": {
		Description: "Dry-run an application environment request through the HTTP API.",
		InputSchema: map[string]any{
			"type":     "object",
			"required": []any{"app", "environment"},
			"properties": map[string]any{
				"app":         map[string]any{"type": "string"},
				"environment": map[string]any{"type": "string"},
				"runtime":     map[string]any{"type": "string"},
			},
		},
		Handler: func(client *idpAPIClient, args map[string]any) (any, error) {
			payload := map[string]any{"runtime": "kind"}
			for key, value := range args {
				payload[key] = value
			}
			return client.request("POST", idpAPIPaths["environments"]+"?dry_run=true", payload)
		},
	},
}

type rpcMessage struct {
	JSONRPC string          `json:"jsonrpc,omitempty"`
	ID      any             `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
}

func main() {
	client := clientFromEnv()
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		response, ok := handleMessage(client, []byte(line))
		if !ok {
			continue
		}
		encoded, _ := json.Marshal(response)
		fmt.Println(string(encoded))
	}
	if err := scanner.Err(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func clientFromEnv() *idpAPIClient {
	baseURL := strings.TrimRight(os.Getenv("IDP_API_BASE_URL"), "/")
	if baseURL == "" {
		baseURL = defaultIDPAPIBaseURL
	}
	return &idpAPIClient{baseURL: baseURL, client: &http.Client{Timeout: 10 * time.Second}}
}

func (c *idpAPIClient) request(method, path string, payload map[string]any) (map[string]any, error) {
	var body io.Reader
	if payload != nil {
		encoded, err := json.Marshal(payload)
		if err != nil {
			return nil, err
		}
		body = bytes.NewReader(encoded)
	}
	request, err := http.NewRequest(method, c.baseURL+path, body)
	if err != nil {
		return nil, err
	}
	request.Header.Set("content-type", "application/json")
	request.Header.Set("accept", "application/json")
	response, err := c.client.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	responseBody, _ := io.ReadAll(response.Body)
	if response.StatusCode >= 400 {
		return nil, fmt.Errorf("Portal API %d: %s", response.StatusCode, string(responseBody))
	}
	if len(bytes.TrimSpace(responseBody)) == 0 {
		return map[string]any{}, nil
	}
	var result map[string]any
	if err := json.Unmarshal(responseBody, &result); err != nil {
		return nil, err
	}
	return result, nil
}

func handleMessage(client *idpAPIClient, data []byte) (map[string]any, bool) {
	var message rpcMessage
	if err := json.Unmarshal(data, &message); err != nil {
		return rpcError(nil, -32700, err.Error()), true
	}
	switch message.Method {
	case "initialize":
		return map[string]any{
			"jsonrpc": "2.0",
			"id":      message.ID,
			"result": map[string]any{
				"protocolVersion": "2024-11-05",
				"serverInfo":      map[string]any{"name": "platform-idp-mcp", "version": "0.1.0"},
				"capabilities":    map[string]any{"tools": map[string]any{}},
			},
		}, true
	case "tools/list":
		return map[string]any{"jsonrpc": "2.0", "id": message.ID, "result": map[string]any{"tools": toolDefinitions()}}, true
	case "tools/call":
		result, err := handleToolCall(client, message.Params)
		if err != nil {
			return rpcError(message.ID, -32603, err.Error()), true
		}
		return map[string]any{"jsonrpc": "2.0", "id": message.ID, "result": result}, true
	default:
		if message.ID == nil {
			return nil, false
		}
		return rpcError(message.ID, -32601, "method not found: "+message.Method), true
	}
}

func toolDefinitions() []map[string]any {
	names := []string{"platform_status", "catalog_list", "environment_create"}
	definitions := make([]map[string]any, 0, len(names))
	for _, name := range names {
		spec := tools[name]
		definitions = append(definitions, map[string]any{
			"name":        name,
			"description": spec.Description,
			"inputSchema": spec.InputSchema,
		})
	}
	return definitions
}

func handleToolCall(client *idpAPIClient, params json.RawMessage) (map[string]any, error) {
	var payload struct {
		Name      string         `json:"name"`
		Arguments map[string]any `json:"arguments"`
	}
	if err := json.Unmarshal(params, &payload); err != nil {
		return nil, err
	}
	spec, ok := tools[payload.Name]
	if !ok {
		return nil, fmt.Errorf("unsupported tool: %s", payload.Name)
	}
	if payload.Arguments == nil {
		payload.Arguments = map[string]any{}
	}
	result, err := spec.Handler(client, payload.Arguments)
	if err != nil {
		return nil, err
	}
	encoded, _ := json.MarshalIndent(result, "", "  ")
	return map[string]any{"content": []map[string]string{{"type": "text", "text": string(encoded)}}}, nil
}

func rpcError(id any, code int, message string) map[string]any {
	return map[string]any{"jsonrpc": "2.0", "id": id, "error": map[string]any{"code": code, "message": message}}
}
