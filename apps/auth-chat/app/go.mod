module platform.local/auth-chat

go 1.26

require (
	platform.local/appconfig v0.0.0-00010101000000-000000000000
	platform.local/apphttp v0.0.0
	platform.local/appshell v0.0.0
	platform.local/idpauth v0.0.0
)

require (
	github.com/coreos/go-oidc/v3 v3.17.0 // indirect
	github.com/go-jose/go-jose/v4 v4.1.4 // indirect
	golang.org/x/oauth2 v0.28.0 // indirect
	platform.local/apphealth v0.0.0-00010101000000-000000000000 // indirect
)

replace platform.local/apphttp => ../../shared/apphttp

replace platform.local/appshell => ../../shared/appshell

replace platform.local/idpauth => ../../shared/idpauth

replace platform.local/appconfig => ../../shared/appconfig

replace platform.local/apphealth => ../../shared/apphealth
