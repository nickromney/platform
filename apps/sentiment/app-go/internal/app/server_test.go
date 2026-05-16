package app

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHealthAndStaticFrontend(t *testing.T) {
	srv := NewServer(Config{RuntimeRole: "all", DataDir: t.TempDir()})

	req := httptest.NewRequest(http.MethodGet, "/api/v1/health", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("health returned %d: %s", rec.Code, rec.Body.String())
	}
	if strings.TrimSpace(rec.Body.String()) != `{"status":"ok"}` {
		t.Fatalf("unexpected health body: %s", rec.Body.String())
	}

	req = httptest.NewRequest(http.MethodGet, "/", nil)
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("frontend returned %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "<title>Sentiment (Authenticated)</title>") {
		t.Fatalf("frontend title missing: %s", rec.Body.String())
	}
}

func TestCommentsPersistAndReturnNewestFirst(t *testing.T) {
	srv := NewServer(Config{RuntimeRole: "backend", DataDir: t.TempDir()})

	post(t, srv, "/api/v1/comments", `{"text":"I love how small and fast this is."}`, http.StatusOK)
	post(t, srv, "/api/v1/comments", `{"text":"I am disappointed and frustrated."}`, http.StatusOK)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/comments?limit=1", nil)
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("list returned %d: %s", rec.Code, rec.Body.String())
	}

	var payload struct {
		Items []Comment `json:"items"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if len(payload.Items) != 1 {
		t.Fatalf("items length=%d", len(payload.Items))
	}
	if payload.Items[0].Text != "I am disappointed and frustrated." || payload.Items[0].Label != Negative {
		t.Fatalf("unexpected newest record: %#v", payload.Items[0])
	}
}

func TestClassifyDoesNotPersistAndRejectsEmptyText(t *testing.T) {
	srv := NewServer(Config{RuntimeRole: "backend", DataDir: t.TempDir()})

	rec := post(t, srv, "/api/v1/sentiment/classify", `{"text":"Some parts are fine, but overall I am disappointed and frustrated."}`, http.StatusOK)
	if !strings.Contains(rec.Body.String(), `"label":"neutral"`) {
		t.Fatalf("mixed wording should classify neutral: %s", rec.Body.String())
	}

	rec = post(t, srv, "/api/v1/comments", `{"text":"   "}`, http.StatusBadRequest)
	if strings.TrimSpace(rec.Body.String()) != `{"error":"text is required"}` {
		t.Fatalf("unexpected empty text body: %s", rec.Body.String())
	}

	req := httptest.NewRequest(http.MethodGet, "/api/v1/comments?limit=25", nil)
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, req)
	if strings.TrimSpace(rec.Body.String()) != `{"items":[]}` {
		t.Fatalf("classify persisted a comment or empty POST changed state: %s", rec.Body.String())
	}
}

func TestRuntimeRolesKeepFrontendAndBackendSeparate(t *testing.T) {
	backend := NewServer(Config{RuntimeRole: "backend", DataDir: t.TempDir()})
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()
	backend.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("backend role served frontend with status %d", rec.Code)
	}

	frontend := NewServer(Config{RuntimeRole: "frontend", BackendURL: "http://backend.example.test"})
	req = httptest.NewRequest(http.MethodGet, "/api/v1/health", nil)
	rec = httptest.NewRecorder()
	frontend.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("frontend role handled API locally with status %d", rec.Code)
	}

	req = httptest.NewRequest(http.MethodGet, "/", nil)
	rec = httptest.NewRecorder()
	frontend.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("frontend role did not serve static assets: %d", rec.Code)
	}
}

func post(t *testing.T, handler http.Handler, path string, body string, want int) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != want {
		t.Fatalf("%s returned %d, want %d: %s", path, rec.Code, want, rec.Body.String())
	}
	return rec
}
