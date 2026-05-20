package appshell

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
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
	for _, text := range []string{`body > main`, `padding-top: 32px`, `padding-bottom: 32px`, `[hidden]`, `display: none !important`, `align-items: center`, `header h1`, `font-size: 2.25rem`, `line-height: 1.15`, `header p`, `.header-actions`, `.auth-state`, `.theme-toggle`, `.sign-in-link`, `min-height: 42px`} {
		if !strings.Contains(rec.Body.String(), text) {
			t.Fatalf("stylesheet missing %q: %s", text, rec.Body.String())
		}
	}
}
