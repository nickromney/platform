module platform.local/idp-core

go 1.26

require (
	platform.local/appconfig v0.0.0-00010101000000-000000000000
	platform.local/apphealth v0.0.0-00010101000000-000000000000
	platform.local/apphttp v0.0.0
)

replace platform.local/apphttp => ../../shared/apphttp

replace platform.local/appconfig => ../../shared/appconfig

replace platform.local/apphealth => ../../shared/apphealth
