package appshell

import (
	_ "embed"
	"encoding/json"
	"html/template"
	"io/fs"
	"mime"
	"net/http"
	"path"
	"regexp"
	"strings"

	"platform.local/apphttp"
)

//go:embed app-shell.css
var css []byte

//go:embed app-shell.js
var js []byte

var scriptAssignmentTargetPattern = regexp.MustCompile(`^window\.[A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)*$`)

func Stylesheet(w http.ResponseWriter, r *http.Request) {
	if !allowGetHead(w, r) {
		return
	}
	NoCacheHeaders(w)
	w.Header().Set("Content-Type", "text/css; charset=utf-8")
	if r.Method == http.MethodHead {
		return
	}
	_, _ = w.Write(css)
}

func Script(w http.ResponseWriter, r *http.Request) {
	if !allowGetHead(w, r) {
		return
	}
	NoCacheHeaders(w)
	w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
	if r.Method == http.MethodHead {
		return
	}
	_, _ = w.Write(js)
}

func RegisterSharedAssets(mux *http.ServeMux, idpAuthScript http.HandlerFunc) {
	mux.HandleFunc("GET /idpauth.js", idpAuthScript)
	mux.HandleFunc("GET /app-shell.css", Stylesheet)
	mux.HandleFunc("GET /app-shell.js", Script)
}

func WriteScriptConfig(w http.ResponseWriter, globalName string, payload any) {
	writeScriptConfigBody(w, globalName, payload)
}

func WriteScriptConfigForRequest(w http.ResponseWriter, r *http.Request, globalName string, payload any) {
	if !allowGetHead(w, r) {
		return
	}
	if r.Method == http.MethodHead {
		writeScriptConfigHeaders(w, globalName)
		return
	}
	writeScriptConfigBody(w, globalName, payload)
}

type RuntimeConfigOptions struct {
	Base                map[string]any
	OIDCRedirect        string
	IncludeOIDCRedirect bool
	ShowNetworkPath     string
	NetworkHopsJSON     string
}

func RuntimeConfigPayload(r *http.Request, options RuntimeConfigOptions) map[string]any {
	payload := map[string]any{}
	for key, value := range options.Base {
		payload[key] = value
	}
	if options.IncludeOIDCRedirect {
		redirect := options.OIDCRedirect
		if redirect == "" {
			redirect = requestRootURL(r)
		}
		payload["oidcRedirect"] = redirect
	}
	payload["showNetworkPath"] = parseBoolDefault(options.ShowNetworkPath, true)
	if options.NetworkHopsJSON != "" {
		var hops any
		if err := json.Unmarshal([]byte(options.NetworkHopsJSON), &hops); err == nil {
			payload["networkHops"] = hops
		}
	}
	return payload
}

func requestRootURL(r *http.Request) string {
	scheme := "http"
	if r.TLS != nil {
		scheme = "https"
	}
	return scheme + "://" + r.Host + "/"
}

func parseBoolDefault(value string, fallback bool) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "":
		return fallback
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}

func writeScriptConfigBody(w http.ResponseWriter, globalName string, payload any) {
	if !scriptAssignmentTargetPattern.MatchString(globalName) {
		http.Error(w, "runtime config assignment target unavailable", http.StatusInternalServerError)
		return
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		http.Error(w, "runtime config unavailable", http.StatusInternalServerError)
		return
	}
	NoCacheHeaders(w)
	w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
	_, _ = w.Write([]byte(globalName + " = "))
	_, _ = w.Write(encoded)
	_, _ = w.Write([]byte(";\n"))
}

func writeScriptConfigHeaders(w http.ResponseWriter, globalName string) {
	if !scriptAssignmentTargetPattern.MatchString(globalName) {
		http.Error(w, "runtime config assignment target unavailable", http.StatusInternalServerError)
		return
	}
	NoCacheHeaders(w)
	w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
}

type SignedOutPageConfig struct {
	AppName     string
	Tagline     string
	SessionName string
	Stylesheet  string
	Favicon     string
	LoginPath   string
	PanelClass  string
}

func SignedOutPage(config SignedOutPageConfig) http.HandlerFunc {
	if config.AppName == "" {
		config.AppName = "Platform App"
	}
	if config.SessionName == "" {
		config.SessionName = config.AppName
	}
	if config.Stylesheet == "" {
		config.Stylesheet = "/style.css"
	}
	if config.LoginPath == "" {
		config.LoginPath = "/.auth/login/sso"
	}
	return func(w http.ResponseWriter, r *http.Request) {
		if !allowGetHead(w, r) {
			return
		}
		NoCacheHeaders(w)
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		if r.Method == http.MethodHead {
			return
		}
		_ = signedOutTemplate.Execute(w, config)
	}
}

func SVGFavicon(svg string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !allowGetHead(w, r) {
			return
		}
		NoCacheHeaders(w)
		w.Header().Set("Content-Type", "image/svg+xml")
		if r.Method == http.MethodHead {
			return
		}
		_, _ = w.Write([]byte(svg))
	}
}

func StaticFiles(files fs.FS, dir string) http.Handler {
	sub, err := fs.Sub(files, dir)
	if err != nil {
		return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			http.Error(w, "static assets unavailable", http.StatusInternalServerError)
		})
	}
	fileServer := http.FileServer(http.FS(sub))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !allowStaticMethod(w, r, sub) {
			return
		}
		NoCacheHeaders(w)
		fileServer.ServeHTTP(w, r)
	})
}

func TryStaticFile(files fs.FS, dir string, w http.ResponseWriter, r *http.Request) bool {
	sub, err := fs.Sub(files, dir)
	if err != nil {
		http.Error(w, "static assets unavailable", http.StatusInternalServerError)
		return true
	}
	name := staticAssetName(r.URL.Path)
	info, err := fs.Stat(sub, name)
	if err != nil || info.IsDir() {
		return false
	}
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		apphttp.MethodNotAllowed(w, http.MethodGet, http.MethodHead)
		return true
	}
	data, err := fs.ReadFile(sub, name)
	if err != nil {
		http.Error(w, "static asset unavailable", http.StatusInternalServerError)
		return true
	}
	NoCacheHeaders(w)
	w.Header().Set("Content-Type", contentTypeForStaticAsset(name))
	if r.Method == http.MethodHead {
		return true
	}
	_, _ = w.Write(data)
	return true
}

func NoCacheHeaders(w http.ResponseWriter) {
	apphttp.NoCacheHeaders(w)
}

func allowGetHead(w http.ResponseWriter, r *http.Request) bool {
	if r.Method == http.MethodGet || r.Method == http.MethodHead {
		return true
	}
	apphttp.MethodNotAllowed(w, http.MethodGet, http.MethodHead)
	return false
}

func allowStaticMethod(w http.ResponseWriter, r *http.Request, files fs.FS) bool {
	if r.Method == http.MethodGet || r.Method == http.MethodHead {
		return true
	}
	if staticAssetExists(files, r.URL.Path) {
		apphttp.MethodNotAllowed(w, http.MethodGet, http.MethodHead)
		return false
	}
	return true
}

func staticAssetExists(files fs.FS, requestPath string) bool {
	name := staticAssetName(requestPath)
	info, err := fs.Stat(files, name)
	return err == nil && !info.IsDir()
}

func staticAssetName(requestPath string) string {
	name := strings.TrimPrefix(path.Clean(requestPath), "/")
	if name == "." || name == "" {
		return "index.html"
	}
	return name
}

func contentTypeForStaticAsset(name string) string {
	if contentType := mime.TypeByExtension(path.Ext(name)); contentType != "" {
		return contentType
	}
	return "application/octet-stream"
}

var signedOutTemplate = template.Must(template.New("signed-out").Parse(`<!doctype html>
<html lang="en" data-theme="system">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Signed out - {{.AppName}}</title>
    {{if .Favicon}}<link rel="icon" href="{{.Favicon}}">{{end}}
    <link rel="stylesheet" href="{{.Stylesheet}}">
    <link rel="stylesheet" href="/app-shell.css">
  </head>
  <body>
    <main>
      <header>
        <div>
          <h1>{{.AppName}}</h1>
          {{if .Tagline}}<p>{{.Tagline}}</p>{{end}}
        </div>
        <div class="header-actions">
          <a id="login-link" class="sign-in-link" href="{{.LoginPath}}">Sign in now</a>
          <button id="theme-switcher" class="theme-toggle" type="button" aria-label="Theme: system. Switch to light theme." title="Theme: system. Switch to light theme." data-theme-choice="system"></button>
        </div>
      </header>
      <section{{if .PanelClass}} class="{{.PanelClass}}"{{end}}>
        <h2>Signed out</h2>
        <p>Your {{.SessionName}} session has ended.</p>
        <p id="redirect-delay">Redirecting to sign in in 5 seconds.</p>
      </section>
    </main>
    <script src="/app-shell.js"></script>
    <script>
      window.PlatformAppShell.initializeSignedOutRedirect();
    </script>
  </body>
</html>
`))
