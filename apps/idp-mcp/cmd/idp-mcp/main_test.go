package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestToolDefinitionsExposeRegistry(t *testing.T) {
	definitions := toolDefinitions()
	if len(definitions) != 3 {
		t.Fatalf("len(toolDefinitions())=%d", len(definitions))
	}
	names := map[string]bool{}
	for _, definition := range definitions {
		names[definition["name"].(string)] = true
		if definition["description"] == "" {
			t.Fatalf("definition missing description: %#v", definition)
		}
		if definition["inputSchema"] == nil {
			t.Fatalf("definition missing schema: %#v", definition)
		}
	}
	for _, name := range []string{"platform_status", "catalog_list", "environment_create"} {
		if !names[name] {
			t.Fatalf("missing tool %s", name)
		}
	}
}

func TestInitializeMessage(t *testing.T) {
	response, ok := handleMessage(clientFromEnv(), []byte(`{"jsonrpc":"2.0","id":1,"method":"initialize"}`))
	if !ok {
		t.Fatal("expected response")
	}
	encoded, _ := json.Marshal(response)
	text := string(encoded)
	for _, fragment := range []string{`"protocolVersion":"2024-11-05"`, `"name":"platform-idp-mcp"`, `"tools":{}`} {
		if !strings.Contains(text, fragment) {
			t.Fatalf("response missing %s: %s", fragment, text)
		}
	}
}

func TestUnknownToolReturnsError(t *testing.T) {
	_, err := handleToolCall(clientFromEnv(), []byte(`{"name":"missing","arguments":{}}`))
	if err == nil || err.Error() != "unsupported tool: missing" {
		t.Fatalf("err=%v", err)
	}
}
