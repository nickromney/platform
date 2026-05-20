package appshell

import (
	_ "embed"
	"net/http"
)

//go:embed app-shell.css
var css []byte

func Stylesheet(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate, max-age=0")
	w.Header().Set("Pragma", "no-cache")
	w.Header().Set("Expires", "0")
	w.Header().Set("Content-Type", "text/css; charset=utf-8")
	_, _ = w.Write(css)
}
