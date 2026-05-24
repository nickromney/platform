module platform.local/apphttp

go 1.26

require (
	platform.local/appconfig v0.0.0-00010101000000-000000000000
	platform.local/apphealth v0.0.0-00010101000000-000000000000
)

replace platform.local/appconfig => ../appconfig

replace platform.local/apphealth => ../apphealth
