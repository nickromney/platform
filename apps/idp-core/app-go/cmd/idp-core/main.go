package main

import (
	"log"
	"net/http"
	"os"

	"platform.local/idp-core/internal/app"
)

func main() {
	addr := ":" + env("PORT", "8080")
	server, err := app.NewServer(app.Config{
		AuditPath:   env("IDP_AUDIT_PATH", "/tmp/idp-core/audit.jsonl"),
		CatalogPath: env("IDP_CATALOG_PATH", "/app/catalog/platform-apps.json"),
		Runtime:     env("IDP_RUNTIME", "kind"),
	})
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("idp-core listening on %s", addr)
	if err := http.ListenAndServe(addr, server); err != nil {
		log.Fatal(err)
	}
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
