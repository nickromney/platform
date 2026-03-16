package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

type runtimeField struct {
	Key      string
	EnvNames []string
	Default  string
	Derived  func(values map[string]string) string
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

func renderRuntimeConfig(outputPath string) error {
	fields := []runtimeField{
		{Key: "AUTH_METHOD", EnvNames: []string{"AUTH_METHOD", "AUTH_MODE", "VITE_AUTH_METHOD"}, Default: "none"},
		{Key: "AUTH_ENABLED", EnvNames: []string{"AUTH_ENABLED", "VITE_AUTH_ENABLED"}, Derived: func(values map[string]string) string {
			switch values["AUTH_METHOD"] {
			case "", "none":
				return "false"
			default:
				return "true"
			}
		}},
		{Key: "API_BASE_URL", EnvNames: []string{"API_BASE_URL", "VITE_API_BASE_URL", "VITE_API_URL"}},
		{Key: "API_PROXY_ENABLED", EnvNames: []string{"API_PROXY_ENABLED", "VITE_API_PROXY_ENABLED"}, Default: "false"},
		{Key: "JWT_USERNAME", EnvNames: []string{"JWT_USERNAME", "VITE_JWT_USERNAME"}},
		{Key: "JWT_PASSWORD", EnvNames: []string{"JWT_PASSWORD", "VITE_JWT_PASSWORD"}},
		{Key: "AZURE_CLIENT_ID", EnvNames: []string{"AZURE_CLIENT_ID", "VITE_AZURE_CLIENT_ID"}},
		{Key: "AZURE_TENANT_ID", EnvNames: []string{"AZURE_TENANT_ID", "VITE_AZURE_TENANT_ID"}, Default: "common"},
		{Key: "AZURE_REDIRECT_URI", EnvNames: []string{"AZURE_REDIRECT_URI", "VITE_AZURE_REDIRECT_URI"}},
		{Key: "EASYAUTH_RESOURCE_ID", EnvNames: []string{"EASYAUTH_RESOURCE_ID", "VITE_EASYAUTH_RESOURCE_ID"}},
		{Key: "OIDC_AUTHORITY", EnvNames: []string{"OIDC_AUTHORITY", "VITE_OIDC_AUTHORITY"}},
		{Key: "OIDC_CLIENT_ID", EnvNames: []string{"OIDC_CLIENT_ID", "VITE_OIDC_CLIENT_ID"}},
		{Key: "OIDC_REDIRECT_URI", EnvNames: []string{"OIDC_REDIRECT_URI", "VITE_OIDC_REDIRECT_URI"}},
		{Key: "OIDC_AUTO_LOGIN", EnvNames: []string{"OIDC_AUTO_LOGIN", "VITE_OIDC_AUTO_LOGIN"}, Default: "false"},
		{Key: "OIDC_PROMPT", EnvNames: []string{"OIDC_PROMPT", "VITE_OIDC_PROMPT"}},
		{Key: "OIDC_FORCE_REAUTH", EnvNames: []string{"OIDC_FORCE_REAUTH", "VITE_OIDC_FORCE_REAUTH"}, Default: "false"},
		{Key: "APIM_SUBSCRIPTION_KEY", EnvNames: []string{"APIM_SUBSCRIPTION_KEY", "VITE_APIM_SUBSCRIPTION_KEY"}},
		{Key: "SHOW_NETWORK_PATH", EnvNames: []string{"SHOW_NETWORK_PATH", "VITE_SHOW_NETWORK_PATH"}, Default: "false"},
		{Key: "NETWORK_HOPS", EnvNames: []string{"NETWORK_HOPS", "VITE_NETWORK_HOPS"}},
		{Key: "NETWORK_DIAGNOSTICS_LABEL", EnvNames: []string{"NETWORK_DIAGNOSTICS_LABEL", "VITE_NETWORK_DIAGNOSTICS_LABEL"}},
		{Key: "SECONDARY_NETWORK_DIAGNOSTICS_LABEL", EnvNames: []string{"SECONDARY_NETWORK_DIAGNOSTICS_LABEL", "VITE_SECONDARY_NETWORK_DIAGNOSTICS_LABEL"}},
		{Key: "SECONDARY_NETWORK_DIAGNOSTICS_PATH", EnvNames: []string{"SECONDARY_NETWORK_DIAGNOSTICS_PATH", "VITE_SECONDARY_NETWORK_DIAGNOSTICS_PATH"}},
		{Key: "FRONTEND_STATUS_LABEL", EnvNames: []string{"FRONTEND_STATUS_LABEL", "VITE_FRONTEND_STATUS_LABEL"}},
		{Key: "API_INGRESS_STATUS_LABEL", EnvNames: []string{"API_INGRESS_STATUS_LABEL", "VITE_API_INGRESS_STATUS_LABEL"}},
		{Key: "BACKEND_PATH_STATUS_LABEL", EnvNames: []string{"BACKEND_PATH_STATUS_LABEL", "VITE_BACKEND_PATH_STATUS_LABEL"}},
		{Key: "BACKEND_PATH_STATUS_DETAIL", EnvNames: []string{"BACKEND_PATH_STATUS_DETAIL", "VITE_BACKEND_PATH_STATUS_DETAIL"}},
	}

	values := make(map[string]string, len(fields))
	for _, field := range fields {
		values[field.Key] = envValue(field.EnvNames, field.Default)
	}

	for _, field := range fields {
		if values[field.Key] == "" && field.Derived != nil {
			values[field.Key] = field.Derived(values)
		}
	}

	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		return err
	}

	var builder strings.Builder
	builder.WriteString("window.RUNTIME_CONFIG = Object.assign({}, window.RUNTIME_CONFIG || {}, {\n")
	for index, field := range fields {
		builder.WriteString("  ")
		builder.WriteString(field.Key)
		builder.WriteString(": ")
		builder.WriteString(strconv.Quote(values[field.Key]))
		if index < len(fields)-1 {
			builder.WriteString(",")
		}
		builder.WriteString("\n")
	}
	builder.WriteString("});\n")

	return os.WriteFile(outputPath, []byte(builder.String()), 0o644)
}

func main() {
	outputPath := firstNonEmpty(os.Getenv("RUNTIME_CONFIG_OUT"), "/usr/share/nginx/html/runtime-config.js")
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
