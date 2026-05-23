package app

import (
	"embed"
	"net/http"

	"platform.local/appshell"
)

//go:embed web/*
var web embed.FS

func (s *server) serveStatic(w http.ResponseWriter, r *http.Request) bool {
	return appshell.TryStaticFile(web, "web", w, r)
}

func (s *server) runtimeConfig(w http.ResponseWriter, r *http.Request) {
	appshell.WriteScriptConfigForRequest(w, r, "window.APIM_SIMULATOR_RUNTIME_CONFIG", map[string]string{"managementBasePath": "/apim/management"})
}

const apimFaviconSVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="10" fill="#17202a"/><path d="M12 19h40M12 32h40M12 45h40" stroke="#4f9d7e" stroke-width="6" stroke-linecap="round"/></svg>`
