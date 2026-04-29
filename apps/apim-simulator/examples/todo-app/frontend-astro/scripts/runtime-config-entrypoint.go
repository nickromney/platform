package main

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"syscall"
)

type runtimeField struct {
	key        string
	envNames   []string
	defaultVal string
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}

	return ""
}

func envValue(names []string, fallback string) string {
	for _, name := range names {
		if value := os.Getenv(name); value != "" {
			return value
		}
	}

	return fallback
}

func writeRuntimeConfigField(file *os.File, key string, value string, last bool) error {
	rendered := fmt.Sprintf("  %s: %s", key, strconv.Quote(value))
	if len(rendered) <= 80 {
		if !last {
			rendered += ","
		}
		rendered += "\n"
		_, err := file.WriteString(rendered)
		return err
	}

	if _, err := file.WriteString(fmt.Sprintf("  %s:\n    %s", key, strconv.Quote(value))); err != nil {
		return err
	}
	if !last {
		if _, err := file.WriteString(","); err != nil {
			return err
		}
	}
	_, err := file.WriteString("\n")
	return err
}

func renderRuntimeConfig(outputPath string) error {
	fields := []runtimeField{
		{key: "API_BASE_URL", envNames: []string{"API_BASE_URL"}, defaultVal: "http://localhost:8000"},
		{key: "APIM_SUBSCRIPTION_KEY", envNames: []string{"APIM_SUBSCRIPTION_KEY"}, defaultVal: "todo-demo-key"},
		{key: "GRAFANA_BASE_URL", envNames: []string{"GRAFANA_BASE_URL"}, defaultVal: "https://lgtm.apim.127.0.0.1.sslip.io:8443"},
		{
			key:        "OBSERVABILITY_DASHBOARD_URL",
			envNames:   []string{"OBSERVABILITY_DASHBOARD_URL"},
			defaultVal: "https://lgtm.apim.127.0.0.1.sslip.io:8443/d/apim-simulator-overview/apim-simulator-overview",
		},
	}

	if err := os.MkdirAll("/tmp", 0o1777); err != nil {
		return err
	}

	file, err := os.OpenFile(outputPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	defer file.Close()

	if _, err := file.WriteString("window.RUNTIME_CONFIG = {\n"); err != nil {
		return err
	}
	for index, field := range fields {
		value := envValue(field.envNames, field.defaultVal)
		if err := writeRuntimeConfigField(file, field.key, value, index == len(fields)-1); err != nil {
			return err
		}
	}
	if _, err := file.WriteString("};\n"); err != nil {
		return err
	}

	return nil
}

func main() {
	outputPath := firstNonEmpty(os.Getenv("RUNTIME_CONFIG_OUT"), "/tmp/runtime-config.js")
	if err := renderRuntimeConfig(outputPath); err != nil {
		fmt.Fprintf(os.Stderr, "runtime-config-entrypoint: %v\n", err)
		os.Exit(1)
	}

	command := os.Args[1:]
	if len(command) == 0 {
		command = []string{"nginx", "-g", "daemon off;"}
	}

	executable, err := exec.LookPath(command[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "runtime-config-entrypoint: %v\n", err)
		os.Exit(1)
	}

	if err := syscall.Exec(executable, command, os.Environ()); err != nil {
		fmt.Fprintf(os.Stderr, "runtime-config-entrypoint: %v\n", err)
		os.Exit(1)
	}
}
