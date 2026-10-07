package main

import (
	"fmt"
	"os"

	"github.com/santhosh-tekuri/jsonschema/v6"
)

// One explicitly supplied schema owns this invocation. Internal definitions and
// built-in metaschemas work; external file/network references never load.
type closedLoader struct{}

func (closedLoader) Load(_ string) (any, error) {
	return nil, fmt.Errorf("external_refs_disabled: supply a self-contained schema")
}

func loadJSON(path string) (any, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	return jsonschema.UnmarshalJSON(file)
}

func validate(schema, payload any) error {
	compiler := jsonschema.NewCompiler()
	compiler.UseLoader(closedLoader{})
	compiler.DefaultDraft(jsonschema.Draft2020)
	const identity = "https://platform.invalid/validation/schema.json"
	if err := compiler.AddResource(identity, schema); err != nil {
		return fmt.Errorf("invalid_schema: %w", err)
	}
	compiled, err := compiler.Compile(identity)
	if err != nil {
		return fmt.Errorf("invalid_schema: %w", err)
	}
	if err := compiled.Validate(payload); err != nil {
		return fmt.Errorf("invalid_payload: %w", err)
	}
	return nil
}

func run(args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: validate-json-schema SCHEMA.json PAYLOAD.json")
	}
	schema, err := loadJSON(args[0])
	if err != nil {
		return fmt.Errorf("invalid_schema_json: %w", err)
	}
	payload, err := loadJSON(args[1])
	if err != nil {
		return fmt.Errorf("invalid_payload_json: %w", err)
	}
	return validate(schema, payload)
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "FAIL", err)
		os.Exit(1)
	}
	fmt.Printf("OK   %s validates against %s\n", os.Args[2], os.Args[1])
}
