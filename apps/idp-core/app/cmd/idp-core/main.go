package main

import (
	"log"

	"platform.local/appconfig"
	"platform.local/apphealth"
	"platform.local/apphttp"
	"platform.local/idp-core/internal/app"
)

func main() {
	if apphealth.HandleHealthcheckCommand(appconfig.Env("PORT", "8080"), "/health") {
		return
	}
	addr := appconfig.NormalizeAddr(appconfig.Env("PORT", "8080"))
	server, err := app.NewServer(app.Config{
		AuditPath:   appconfig.Env("IDP_AUDIT_PATH", "/tmp/idp-core/audit.jsonl"),
		CatalogPath: appconfig.Env("IDP_CATALOG_PATH", "/app/catalog/platform-apps.json"),
		Runtime:     appconfig.Env("IDP_RUNTIME", "kind"),
	})
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("idp-core listening on %s", addr)
	if err := apphttp.ListenAndServe(addr, server); err != nil {
		log.Fatal(err)
	}
}
