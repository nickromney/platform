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
	// ListenAndServe was in apphttp but it used NewServer which was moved.
	// Wait, ListenAndServe is still in apphttp in my write_file? 
	// No, I moved NewServer and ListenAndServe should probably move to a server helper or stay in apphttp if it's generic.
	// Actually, I removed NewServer from apphttp in my last write_file.
	if err := apphttp.ListenAndServe(addr, server); err != nil {
		log.Fatal(err)
	}
}
