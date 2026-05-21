package app

import (
	"embed"
	"net/http"
	"path"
	"strings"
)

//go:embed web/*
var web embed.FS

func (s *server) serveStatic(w http.ResponseWriter, r *http.Request) bool {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		return false
	}
	name := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
	if name == "." || name == "" {
		name = "index.html"
	}
	if strings.HasPrefix(name, "apim/") || strings.HasPrefix(name, "api/") || strings.HasPrefix(name, "mcp") || strings.HasPrefix(name, "a2a") {
		return false
	}
	data, err := web.ReadFile("web/" + name)
	if err != nil {
		return false
	}
	w.Header().Set("Content-Type", contentTypeFor(name))
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate, max-age=0")
	_, _ = w.Write(data)
	return true
}

func (s *server) runtimeConfig(w http.ResponseWriter, _ *http.Request) {
	writeScriptConfig(w, "window.APIM_SIMULATOR_RUNTIME_CONFIG = {\"managementBasePath\":\"/apim/management\"};\n")
}

func (s *server) favicon(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "image/svg+xml")
	_, _ = w.Write([]byte(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="10" fill="#17202a"/><path d="M12 19h40M12 32h40M12 45h40" stroke="#4f9d7e" stroke-width="6" stroke-linecap="round"/></svg>`))
}

func writeScriptConfig(w http.ResponseWriter, body string) {
	w.Header().Set("Content-Type", "application/javascript")
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate, max-age=0")
	_, _ = w.Write([]byte(body))
}
