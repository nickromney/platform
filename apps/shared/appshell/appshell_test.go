package appshell

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/fstest"
)

func TestStylesheetServesSharedAppShellRules(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/app-shell.css", nil)
	rec := httptest.NewRecorder()

	Stylesheet(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Content-Type"); got != "text/css; charset=utf-8" {
		t.Fatalf("Content-Type=%q", got)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("Cache-Control=%q", got)
	}
	for _, text := range []string{`body > header`, `body > main`, `--app-shell-width`, `padding-top: 32px`, `padding-bottom: 32px`, `.skip-link`, `.skip-link:focus`, `.sr-only`, `:focus-visible`, `[hidden]`, `display: none !important`, `align-items: center`, `header h1`, `font-size: var(--desktop-heading-03`, `line-height: var(--lh-desktop-heading-03`, `header p`, `.header-actions`, `.header-actions a`, `.auth-state`, `.theme-toggle`, `.sign-in-link`, `min-height: 42px`, `.app-panel`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`--background`, `--card`, `--foreground`, `--muted-foreground`, `--primary`, `--destructive`, `--app-shell-panel-shadow`, `--app-shell-control-shadow`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing 5H3LL token integration %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`--focus-ring`, `outline: 3px solid var(--focus-ring`, `box-shadow: 0 0 0 2px var(--surface`, `scroll-margin-top: 24px`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing keyboard navigation polish %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`min-width: 0`, `max-width: min(100%, 360px)`, `text-wrap: balance`, `transition:`, `@media (max-width: 520px)`, `flex: 1 1 160px`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing responsive polish %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`touch-action: manipulation`, `user-select: none`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing touch control polish %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`@media (pointer: coarse)`, `min-height: 44px`, `min-width: 44px`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing coarse-pointer target polish %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`aspect-ratio: 1`, `flex-basis: 44px`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing stable theme toggle dimensions %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`button:not(:disabled):hover`, `button:disabled`, `cursor: not-allowed`, `opacity: 0.55`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing disabled control polish %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`button[aria-busy="true"]`, `cursor: progress`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing busy control affordance %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`--success`, `--warning`, `.success`, `.warning`, `color: var(--success`, `color: var(--warning`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing shared status color %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`button:not(:disabled)`, `cursor: pointer`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing enabled control affordance %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`:where(label)`, `margin-bottom: 8px`, `font-weight: 700`, `:where(textarea)`, `resize: vertical`, `line-height: 1.4`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing shared form rhythm %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`:where(pre, code)`, `ui-monospace`, `overflow-wrap: anywhere`, `:where(pre)`, `overflow: auto`, `padding: 12px`, `border: 1px solid var(--border`, `border-radius: 6px`, `background: var(--field`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing shared code block surface %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`@media (hover: hover) and (pointer: fine)`, `translateY(-1px)`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing hover-capable control polish %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`button:not(:disabled):active`, `.header-actions a:active`, `translateY(0)`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing pressed control feedback %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`@media (prefers-reduced-motion: reduce)`, `transition-duration: 0.01ms`, `transform: none`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing reduced-motion rule %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`@media (forced-colors: active)`, `forced-color-adjust: none`, `border-color: ButtonText`, `background: ButtonFace`, `color: ButtonText`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing high-contrast rule %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`@media (prefers-contrast: more)`, `border-width: 2px`, `text-decoration-thickness: 2px`, `.network-path`, `.hop-arrow`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing increased-contrast rule %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{`@media print`, `color-scheme: light`, `max-width: none`, `.header-actions`, `display: none !important`, `break-inside: avoid`, `text-decoration: underline`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing print/readout rule %q: %s", text, rec.Body.String())
		}
	}
}

func TestScriptServesSharedThemeHelpers(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/app-shell.js", nil)
	rec := httptest.NewRecorder()

	Script(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Content-Type"); got != "application/javascript; charset=utf-8" {
		t.Fatalf("Content-Type=%q", got)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("Cache-Control=%q", got)
	}
	for _, text := range []string{
		"PlatformAppShell",
		"initializeTheme",
		"initializeAuthStateRegion",
		"toggleTheme",
		"initializeSignedOutRedirect",
		"readThemeCookie",
		"writeThemeCookie",
		"ensureThemeSwitcherIcons",
		"themeIconElement",
		"document.createElementNS",
		"switcher.prepend(",
		"themeBound",
		"themeMediaBound",
		`"data-theme-icon": theme`,
		`themeIconElement("system")`,
		`themeIconElement("light")`,
		`themeIconElement("dark")`,
		"themePreference",
		"resolvedThemeIsDark",
		"classList.toggle(\"dark\"",
		"enhanceVendoredClasses",
		"btn-icon-outline",
		"btn-secondary",
		"select",
		"field",
		"requireElement",
		"optionalElement",
		"requireSelector",
		"requireSelectorAll",
		"buttonElement",
		"buttonSelector",
		"formElement",
		"inputElement",
		"selectElement",
		"textAreaElement",
		"renderNetworkPath",
		"networkPathElement",
		"renderNetworkPathInto",
		"container.replaceChildren(networkPathElement(hops))",
		"renderKeyValueTable",
		`scope="row"`,
		"String(value ?? \"\")",
		"keyValueArticleElement",
		"article.append(heading, keyValueTableElement(rows), ...children);",
		"resolveNetworkHops",
		"shouldShowNetworkPath",
		"readRuntimeConfig",
		"apiTraceHeaders",
		"apiJSONHeaders",
		"decodeAPIMTrace",
		"parseJSONResponse",
		"fetchJSON",
		"fetchJSONWithTiming",
		"error.status = response.status",
		"error.payload = data",
		"buildAPITiming",
		"apiTimingRows",
		"errorMessage",
		`typeof error === "object"`,
		`error !== null`,
		`typeof error.message`,
		"prettyJSON",
		"setText",
		"setTextDefault",
		"normalizeStatusTone",
		"ensureStatusRegion",
		"renderListInto",
		"document.createElement(\"li\")",
		`response.headers.get("x-apim-trace-id")`,
		`typeof errorPayload.detail === "string"`,
		`typeof errorPayload.error === "string"`,
		"withButtonBusy",
		"withSubmitterBusy",
		"submitter instanceof HTMLButtonElement",
		"previousDisabled",
		"button.disabled = previousDisabled",
		"aria-busy",
		"Network Path",
		"escapeHTML",
		"escapeAttr",
		"aria-live",
		"aria-atomic",
		"role",
		"status",
		"pce-theme",
		"matchMedia",
	} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("script missing %q: %s", text, rec.Body.String())
		}
	}
	if strings.Count(rec.Body.String(), "function apiTimingRows(") != 1 {
		t.Fatalf("script should centralize API timing row assembly once: %s", rec.Body.String())
	}
	for _, text := range []string{
		"renderAPITiming(timing, options = {}) {\n\t\tconst rows = apiTimingRows(timing, options);",
		"apiTimingElement(timing, options = {}) {\n\t\tconst rows = apiTimingRows(timing, options);",
	} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("script timing renderer should use shared row builder %q: %s", text, rec.Body.String())
		}
	}
	if !strings.Contains(rec.Body.String(), `return isJSONObject(value) ? value : {};`) {
		t.Fatalf("script should read runtime config globals defensively: %s", rec.Body.String())
	}
	for _, text := range []string{
		`function textDefault(value, fallback)`,
		`value === null || value === undefined || value === ""`,
		`return text == null ? "" : String(text);`,
		`function setTextDefault(node, value, fallback)`,
		`setText(node, textDefault(value, fallback));`,
		`setTextDefault,`,
		`textDefault,`,
	} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("script missing shared text fallback helper %q: %s", text, rec.Body.String())
		}
	}
	for _, text := range []string{
		`return tone === true ? "error" : tone || "";`,
		`node.setAttribute("role", "status");`,
		`node.setAttribute("aria-live", "polite");`,
		`node.setAttribute("aria-atomic", "true");`,
		`node.classList.toggle("success", normalizedTone === "success");`,
		`node.classList.toggle("warning", normalizedTone === "warning");`,
		`node.classList.toggle("error", normalizedTone === "error");`,
	} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("script missing shared status tone handling %q: %s", text, rec.Body.String())
		}
	}
}

func TestSharedAssetHandlersRespectHTTPMethods(t *testing.T) {
	for _, tc := range []struct {
		name        string
		path        string
		handler     http.HandlerFunc
		contentType string
	}{
		{
			name:        "stylesheet",
			path:        "/app-shell.css",
			handler:     Stylesheet,
			contentType: "text/css; charset=utf-8",
		},
		{
			name:        "script",
			path:        "/app-shell.js",
			handler:     Script,
			contentType: "application/javascript; charset=utf-8",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			headReq := httptest.NewRequest(http.MethodHead, tc.path, nil)
			headRec := httptest.NewRecorder()
			tc.handler(headRec, headReq)

			if headRec.Code != http.StatusOK {
				t.Fatalf("HEAD status=%d body=%s", headRec.Code, headRec.Body.String())
			}
			if got := headRec.Header().Get("Content-Type"); got != tc.contentType {
				t.Fatalf("HEAD Content-Type=%q", got)
			}
			if got := headRec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
				t.Fatalf("HEAD Cache-Control=%q", got)
			}
			if headRec.Body.Len() != 0 {
				t.Fatalf("HEAD returned body=%s", headRec.Body.String())
			}

			postReq := httptest.NewRequest(http.MethodPost, tc.path, nil)
			postRec := httptest.NewRecorder()
			tc.handler(postRec, postReq)

			if postRec.Code != http.StatusMethodNotAllowed {
				t.Fatalf("POST status=%d body=%s", postRec.Code, postRec.Body.String())
			}
			if got := postRec.Header().Get("Allow"); got != "GET, HEAD" {
				t.Fatalf("POST Allow=%q", got)
			}
		})
	}
}

func TestRegisterSharedAssetsMountsBrowserBundles(t *testing.T) {
	mux := http.NewServeMux()

	RegisterSharedAssets(mux, func(w http.ResponseWriter, _ *http.Request) {
		NoCacheHeaders(w)
		w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
		_, _ = w.Write([]byte("window.PlatformIdpAuth = {};"))
	})

	for _, tc := range []struct {
		path        string
		contentType string
		body        string
	}{
		{path: "/app-shell.css", contentType: "text/css; charset=utf-8", body: ".theme-toggle"},
		{path: "/app-shell.js", contentType: "application/javascript; charset=utf-8", body: "PlatformAppShell"},
		{path: "/idpauth.js", contentType: "application/javascript; charset=utf-8", body: "PlatformIdpAuth"},
	} {
		req := httptest.NewRequest(http.MethodGet, tc.path, nil)
		rec := httptest.NewRecorder()

		mux.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("%s status=%d body=%s", tc.path, rec.Code, rec.Body.String())
		}
		if got := rec.Header().Get("Content-Type"); got != tc.contentType {
			t.Fatalf("%s Content-Type=%q", tc.path, got)
		}
		if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
			t.Fatalf("%s Cache-Control=%q", tc.path, got)
		}
		if !strings.Contains(rec.Body.String(), tc.body) {
			t.Fatalf("%s body missing %q: %s", tc.path, tc.body, rec.Body.String())
		}
	}
}

func TestWriteScriptConfigEmitsNoCacheJavaScriptAssignment(t *testing.T) {
	rec := httptest.NewRecorder()

	WriteScriptConfig(rec, "window.DEMO_RUNTIME_CONFIG", map[string]any{
		"apiBasePath": "/api/v1",
		"enabled":     true,
	})

	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Content-Type"); got != "application/javascript; charset=utf-8" {
		t.Fatalf("Content-Type=%q", got)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("Cache-Control=%q", got)
	}
	for _, text := range []string{`window.DEMO_RUNTIME_CONFIG = {`, `"apiBasePath":"/api/v1"`, `"enabled":true`, `};`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("script config missing %q: %s", text, rec.Body.String())
		}
	}
}

func TestWriteScriptConfigForRequestRespectsHTTPMethods(t *testing.T) {
	for _, method := range []string{http.MethodGet, http.MethodHead} {
		req := httptest.NewRequest(method, "/runtime-config.js", nil)
		rec := httptest.NewRecorder()

		WriteScriptConfigForRequest(rec, req, "window.DEMO_RUNTIME_CONFIG", map[string]string{"status": "ok"})

		if rec.Code != http.StatusOK {
			t.Fatalf("%s status=%d body=%s", method, rec.Code, rec.Body.String())
		}
		if got := rec.Header().Get("Content-Type"); got != "application/javascript; charset=utf-8" {
			t.Fatalf("%s Content-Type=%q", method, got)
		}
		if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
			t.Fatalf("%s Cache-Control=%q", method, got)
		}
		if method == http.MethodGet && !strings.Contains(rec.Body.String(), `window.DEMO_RUNTIME_CONFIG = {"status":"ok"};`) {
			t.Fatalf("GET body=%s", rec.Body.String())
		}
		if method == http.MethodHead && rec.Body.Len() != 0 {
			t.Fatalf("HEAD returned body=%s", rec.Body.String())
		}
	}

	req := httptest.NewRequest(http.MethodPost, "/runtime-config.js", nil)
	rec := httptest.NewRecorder()

	WriteScriptConfigForRequest(rec, req, "window.DEMO_RUNTIME_CONFIG", map[string]string{"status": "ok"})

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("POST status=%d body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Allow"); got != "GET, HEAD" {
		t.Fatalf("POST Allow=%q", got)
	}
}

func TestWriteScriptConfigRejectsInvalidAssignmentTarget(t *testing.T) {
	rec := httptest.NewRecorder()

	WriteScriptConfig(rec, `window.DEMO_CONFIG;window.alert("bad")`, map[string]string{"status": "ok"})

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "window.alert") {
		t.Fatalf("response included unsafe assignment target: %s", rec.Body.String())
	}
}

func TestRuntimeConfigPayloadAppliesSharedNetworkAndRedirectDefaults(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "https://demo.example.test/runtime-config.js", nil)

	payload := RuntimeConfigPayload(req, RuntimeConfigOptions{
		Base: map[string]any{
			"authMethod": "oidc",
		},
		IncludeOIDCRedirect: true,
		ShowNetworkPath:     "",
		NetworkHopsJSON:     `[{"label":"Browser","detail":"https://demo.example.test","role":"User agent"}]`,
	})

	if payload["authMethod"] != "oidc" {
		t.Fatalf("authMethod=%#v", payload["authMethod"])
	}
	if payload["oidcRedirect"] != "https://demo.example.test/" {
		t.Fatalf("oidcRedirect=%#v", payload["oidcRedirect"])
	}
	if payload["showNetworkPath"] != true {
		t.Fatalf("showNetworkPath=%#v", payload["showNetworkPath"])
	}
	hops, ok := payload["networkHops"].([]any)
	if !ok || len(hops) != 1 {
		t.Fatalf("networkHops=%#v", payload["networkHops"])
	}
}

func TestRuntimeConfigPayloadHonorsExplicitValuesAndIgnoresInvalidHops(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "http://demo.example.test/runtime-config.js", nil)

	payload := RuntimeConfigPayload(req, RuntimeConfigOptions{
		Base: map[string]any{
			"backendURL": "http://backend.example.test",
		},
		OIDCRedirect:        "https://external.example.test/callback",
		IncludeOIDCRedirect: true,
		ShowNetworkPath:     "false",
		NetworkHopsJSON:     `{`,
	})

	if payload["oidcRedirect"] != "https://external.example.test/callback" {
		t.Fatalf("oidcRedirect=%#v", payload["oidcRedirect"])
	}
	if payload["showNetworkPath"] != false {
		t.Fatalf("showNetworkPath=%#v", payload["showNetworkPath"])
	}
	if _, ok := payload["networkHops"]; ok {
		t.Fatalf("invalid networkHops should be ignored: %#v", payload["networkHops"])
	}
}

func TestSignedOutPageServesSharedGatewayLogoutScreen(t *testing.T) {
	handler := SignedOutPage(SignedOutPageConfig{
		AppName:     "Demo Console",
		Tagline:     "A small Go app.",
		SessionName: "demo console",
		Stylesheet:  "/style.css",
		Favicon:     "/favicon.ico",
	})
	req := httptest.NewRequest(http.MethodGet, "/signed-out.html", nil)
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Content-Type"); got != "text/html; charset=utf-8" {
		t.Fatalf("Content-Type=%q", got)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("Cache-Control=%q", got)
	}
	for _, text := range []string{
		`<html lang="en" data-theme="system">`,
		`<title>Signed out - Demo Console</title>`,
		`<link rel="icon" href="/favicon.ico">`,
		`https://cdn.jsdelivr.net/npm/@social-5h3ll/5h3ll-ui@0.1.4/dist/5h3ll_ui.cdn.min.css`,
		`https://cdn.jsdelivr.net/npm/@social-5h3ll/5h3ll-ui@0.1.4/dist/js/all.min.js`,
		`<link rel="stylesheet" href="/app-shell.css">`,
		`<link rel="stylesheet" href="/style.css">`,
		`<h1>Demo Console</h1>`,
		`A small Go app.`,
		`id="login-link"`,
		`href="/.auth/login/sso"`,
		`id="theme-switcher"`,
		`class="theme-toggle"`,
		`Your demo console session has ended.`,
		`id="redirect-delay"`,
		`window.PlatformAppShell.initializeSignedOutRedirect();`,
	} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("signed-out page missing %q: %s", text, rec.Body.String())
		}
	}
	if strings.Index(rec.Body.String(), `/app-shell.css`) > strings.Index(rec.Body.String(), `/style.css`) {
		t.Fatalf("signed-out page should load shared app shell before app stylesheet: %s", rec.Body.String())
	}
}

func TestSignedOutPageRejectsUnsupportedMethodsWithAllowHeader(t *testing.T) {
	handler := SignedOutPage(SignedOutPageConfig{AppName: "Demo Console"})
	req := httptest.NewRequest(http.MethodPost, "/signed-out.html", nil)
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Allow"); got != "GET, HEAD" {
		t.Fatalf("Allow=%q", got)
	}
}

func TestSVGFaviconServesNoCacheBrowserIcon(t *testing.T) {
	handler := SVGFavicon(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8"><rect width="8" height="8"/></svg>`)

	for _, method := range []string{http.MethodGet, http.MethodHead} {
		req := httptest.NewRequest(method, "/favicon.ico", nil)
		rec := httptest.NewRecorder()

		handler(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("%s status=%d body=%s", method, rec.Code, rec.Body.String())
		}
		if got := rec.Header().Get("Content-Type"); got != "image/svg+xml" {
			t.Fatalf("%s Content-Type=%q", method, got)
		}
		if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
			t.Fatalf("%s Cache-Control=%q", method, got)
		}
		if method == http.MethodGet && !strings.Contains(rec.Body.String(), `<rect width="8" height="8"/>`) {
			t.Fatalf("GET body=%s", rec.Body.String())
		}
		if method == http.MethodHead && rec.Body.Len() != 0 {
			t.Fatalf("HEAD returned body=%s", rec.Body.String())
		}
	}
}

func TestSVGFaviconRejectsUnsupportedMethodsWithAllowHeader(t *testing.T) {
	handler := SVGFavicon(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8"><rect width="8" height="8"/></svg>`)
	req := httptest.NewRequest(http.MethodPost, "/favicon.ico", nil)
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Allow"); got != "GET, HEAD" {
		t.Fatalf("Allow=%q", got)
	}
}

func TestStaticFilesServesEmbeddedWebAssetsWithNoCacheHeaders(t *testing.T) {
	handler := StaticFiles(fstest.MapFS{
		"web/index.html": &fstest.MapFile{Data: []byte("<main>ok</main>")},
	}, "web")
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("Cache-Control=%q", got)
	}
	if !strings.Contains(rec.Body.String(), "<main>ok</main>") {
		t.Fatalf("body=%s", rec.Body.String())
	}
}

func TestStaticFilesRejectsUnsupportedMethodsWithAllowHeader(t *testing.T) {
	handler := StaticFiles(fstest.MapFS{
		"web/index.html": &fstest.MapFile{Data: []byte("<main>ok</main>")},
	}, "web")
	req := httptest.NewRequest(http.MethodPost, "/", nil)
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Allow"); got != "GET, HEAD" {
		t.Fatalf("Allow=%q", got)
	}
	if rec.Body.Len() != 0 {
		t.Fatalf("body=%q", rec.Body.String())
	}
}

func TestStaticFilesLeavesUnmatchedUnsupportedRoutesAsNotFound(t *testing.T) {
	handler := StaticFiles(fstest.MapFS{
		"web/index.html": &fstest.MapFile{Data: []byte("<main>ok</main>")},
	}, "web")
	req := httptest.NewRequest(http.MethodPost, "/api/v1/removed", nil)
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Allow"); got != "" {
		t.Fatalf("Allow=%q", got)
	}
}

func TestTryStaticFileServesExistingAssetAndReportsFallthrough(t *testing.T) {
	files := fstest.MapFS{
		"web/index.html": &fstest.MapFile{Data: []byte("<main>ok</main>")},
		"web/app.js":     &fstest.MapFile{Data: []byte("console.log('ok');")},
	}

	req := httptest.NewRequest(http.MethodHead, "/", nil)
	rec := httptest.NewRecorder()
	if !TryStaticFile(files, "web", rec, req) {
		t.Fatal("expected index route to be handled")
	}
	if rec.Code != http.StatusOK {
		t.Fatalf("index HEAD status=%d body=%s", rec.Code, rec.Body.String())
	}
	if rec.Body.Len() != 0 {
		t.Fatalf("index HEAD returned body: %s", rec.Body.String())
	}
	if got := rec.Header().Get("Content-Type"); !strings.Contains(got, "text/html") {
		t.Fatalf("index Content-Type=%q", got)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("index Cache-Control=%q", got)
	}

	req = httptest.NewRequest(http.MethodGet, "/api/v1/missing", nil)
	rec = httptest.NewRecorder()
	if TryStaticFile(files, "web", rec, req) {
		t.Fatal("expected non-static API route to fall through")
	}

	req = httptest.NewRequest(http.MethodPost, "/app.js", nil)
	rec = httptest.NewRecorder()
	if !TryStaticFile(files, "web", rec, req) {
		t.Fatal("expected unsupported method for existing static asset to be handled")
	}
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("app.js POST status=%d body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Allow"); got != "GET, HEAD" {
		t.Fatalf("Allow=%q", got)
	}
}

func TestNoCacheHeadersAppliesSharedFrontendPolicy(t *testing.T) {
	rec := httptest.NewRecorder()

	NoCacheHeaders(rec)

	if got := rec.Header().Get("Cache-Control"); got != "no-cache, no-store, must-revalidate, max-age=0" {
		t.Fatalf("Cache-Control=%q", got)
	}
	if got := rec.Header().Get("Pragma"); got != "no-cache" {
		t.Fatalf("Pragma=%q", got)
	}
	if got := rec.Header().Get("Expires"); got != "0" {
		t.Fatalf("Expires=%q", got)
	}
}
