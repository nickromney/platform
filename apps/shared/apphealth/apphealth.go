package apphealth

import (
	"net/http"
	"os"
	"strings"
	"time"
)

const DefaultHealthcheckTimeout = time.Second

const DependencyFootprintGoSharedIDPAuth = "go-plus-shared-idpauth"

const FrontendDependencyFootprintVanilla = "vanilla"

func BrowserAppHealth(payload map[string]any) map[string]any {
	health := make(map[string]any, len(payload)+4)
	for key, value := range payload {
		health[key] = value
	}
	health["dependency_footprint"] = DependencyFootprintGoSharedIDPAuth
	health["frontend_dependency_footprint"] = FrontendDependencyFootprintVanilla
	health["transitive_javascript_packages"] = 0
	health["transitive_python_packages"] = 0
	return health
}

func CheckHealthURL(rawURL string, timeout time.Duration) bool {
	if timeout <= 0 {
		timeout = DefaultHealthcheckTimeout
	}
	client := http.Client{Timeout: timeout}
	resp, err := client.Get(rawURL)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode >= http.StatusOK && resp.StatusCode < http.StatusMultipleChoices
}

func LocalHealthURL(port string, path string) string {
	port = strings.TrimPrefix(strings.TrimSpace(port), ":")
	if port == "" {
		port = "8080"
	}
	path = strings.TrimSpace(path)
	if path == "" {
		path = "/health"
	}
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}
	return "http://127.0.0.1:" + port + path
}

func CheckLocalHealth(port string, path string) bool {
	return CheckHealthURL(LocalHealthURL(port, path), DefaultHealthcheckTimeout)
}

func HealthcheckCommand(args []string) bool {
	return len(args) == 2 && args[1] == "healthcheck"
}

func HandleHealthcheckCommand(port string, path string) bool {
	if !HealthcheckCommand(os.Args) {
		return false
	}
	if !CheckLocalHealth(port, path) {
		os.Exit(1)
	}
	return true
}
