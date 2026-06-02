module platform.local/idpauth

go 1.26

require (
	github.com/coreos/go-oidc/v3 v3.17.0
	platform.local/appconfig v0.0.0-00010101000000-000000000000
	platform.local/apphttp v0.0.0
)

require (
	github.com/go-jose/go-jose/v4 v4.1.4 // indirect
	golang.org/x/oauth2 v0.28.0 // indirect
	platform.local/apphealth v0.0.0-00010101000000-000000000000 // indirect
)

replace platform.local/apphttp => ../apphttp

replace platform.local/appconfig => ../appconfig

replace platform.local/apphealth => ../apphealth
