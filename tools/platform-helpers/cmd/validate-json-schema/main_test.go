package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func decoded(t *testing.T, value string) any {
	t.Helper()
	var result any
	if err := json.Unmarshal([]byte(value), &result); err != nil {
		t.Fatal(err)
	}
	return result
}

func TestNestedTypesRequiredAndReferences(t *testing.T) {
	schema := decoded(t, `{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":["applications"],"properties":{"applications":{"type":"array","items":{"$ref":"#/$defs/app"}}},"$defs":{"app":{"type":"object","required":["name"],"properties":{"name":{"type":"string","minLength":1}}}}}`)
	for _, input := range []string{`{"applications":false}`, `{"applications":[{}]}`, `{"applications":[{"name":false}]}`, `{"applications":[{"name":""}]}`} {
		if err := validate(schema, decoded(t, input)); err == nil || !strings.Contains(err.Error(), "invalid_payload") {
			t.Fatalf("incorrect acceptance of %s: %v", input, err)
		}
	}
	if err := validate(schema, decoded(t, `{"applications":[{"name":"one"}]}`)); err != nil {
		t.Fatal(err)
	}
}

func TestExternalReferencesNeverFetch(t *testing.T) {
	calls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { calls++; _, _ = w.Write([]byte(`{"type":"object"}`)) }))
	defer server.Close()
	for _, reference := range []string{server.URL + "/schema", "file:///etc/passwd", "missing.json"} {
		schema := map[string]any{"$ref": reference}
		if err := validate(schema, map[string]any{}); err == nil || !strings.Contains(err.Error(), "external_refs_disabled") {
			t.Fatalf("external reference was accepted: %v", err)
		}
	}
	if calls != 0 {
		t.Fatalf("validator performed %d network requests", calls)
	}
}

func TestSchemaAndPayloadRefusals(t *testing.T) {
	for _, schema := range []any{map[string]any{"type": 17}, false} {
		if err := validate(schema, map[string]any{}); err == nil {
			t.Fatalf("invalid/false schema accepted: %#v", schema)
		}
	}
	if err := validate(true, map[string]any{}); err != nil {
		t.Fatal(err)
	}
}
