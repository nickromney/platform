package main

import (
	"encoding/json"
	"fmt"
	"os"
)

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "FAIL "+format+"\n", args...)
	os.Exit(1)
}

func loadJSON(path string) any {
	data, err := os.ReadFile(path)
	if err != nil {
		fail("could not read JSON %s: %v", path, err)
	}
	var value any
	if err := json.Unmarshal(data, &value); err != nil {
		fail("could not read JSON %s: %v", path, err)
	}
	return value
}

func requireKeys(schema map[string]any, payload any, path string) {
	object, ok := payload.(map[string]any)
	if !ok {
		fail("%s is not an object", path)
	}

	if required, ok := schema["required"].([]any); ok {
		for _, keyValue := range required {
			key, ok := keyValue.(string)
			if !ok {
				continue
			}
			if _, exists := object[key]; !exists {
				fail("%s.%s is required", path, key)
			}
		}
	}

	properties, ok := schema["properties"].(map[string]any)
	if !ok {
		return
	}
	for key, rawPropertySchema := range properties {
		propertySchema, ok := rawPropertySchema.(map[string]any)
		if !ok {
			continue
		}
		expected, hasConst := propertySchema["const"]
		actual, exists := object[key]
		if exists && hasConst && !jsonEqual(actual, expected) {
			fail("%s.%s must equal %q", path, key, expected)
		}
	}
}

func jsonEqual(a, b any) bool {
	encodedA, errA := json.Marshal(a)
	encodedB, errB := json.Marshal(b)
	return errA == nil && errB == nil && string(encodedA) == string(encodedB)
}

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "Usage: validate-json-schema SCHEMA.json PAYLOAD.json")
		os.Exit(2)
	}

	schema, ok := loadJSON(os.Args[1]).(map[string]any)
	if !ok {
		fail("schema must be a JSON object")
	}
	payload := loadJSON(os.Args[2])
	requireKeys(schema, payload, "$")
	fmt.Printf("OK   %s validates against %s\n", os.Args[2], os.Args[1])
}
