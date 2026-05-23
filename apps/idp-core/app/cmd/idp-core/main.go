package main

import (
	"log"

	"platform.local/apphttp"
	"platform.local/idp-core/internal/app"
)

func main() {
	if apphttp.HandleHealthcheckCommand("8080", "/health") {
		return
	}
	addr := apphttp.NormalizeAddr(apphttp.Env("PORT", "8080"))
	server, err := app.NewServer(app.Config{
		AuditPath:   apphttp.Env("IDP_AUDIT_PATH", "/tmp/idp-core/audit.jsonl"),
		CatalogPath: apphttp.Env("IDP_CATALOG_PATH", "/app/catalog/platform-apps.json"),
		Runtime:     apphttp.Env("IDP_RUNTIME", "kind"),
	})
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("idp-core listening on %s", addr)
	if err := apphttp.ListenAndServe(addr, server); err != nil {
		log.Fatal(err)
	}
}
