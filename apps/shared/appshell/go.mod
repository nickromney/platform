module platform.local/appshell

go 1.26

require platform.local/apphttp v0.0.0

require platform.local/apphealth v0.0.0-00010101000000-000000000000 // indirect

replace platform.local/apphttp => ../apphttp

replace platform.local/appconfig => ../appconfig

replace platform.local/apphealth => ../apphealth
