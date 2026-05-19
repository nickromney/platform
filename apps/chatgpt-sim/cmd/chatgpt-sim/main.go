package main

import (
	"log"
	"net/http"
	"os"

	"platform.local/chatgpt-sim/internal/app"
)

func main() {
	cfg := app.ConfigFromEnv()
	log.Printf("starting role=%s addr=:%s", cfg.Role, cfg.Port)
	if err := http.ListenAndServe(":"+cfg.Port, app.NewServer(cfg, http.DefaultClient)); err != nil {
		log.Fatal(err)
	}
	_ = os.Stdout.Sync()
}
