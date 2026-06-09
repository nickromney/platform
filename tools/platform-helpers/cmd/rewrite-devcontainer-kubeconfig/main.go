package main

import (
	"fmt"
	"os"
	"regexp"
)

func main() {
	if len(os.Args) != 4 {
		fmt.Fprintln(os.Stderr, "usage: rewrite-devcontainer-kubeconfig <kubeconfig-path> <host-alias> <tls-server-name>")
		os.Exit(2)
	}

	path := os.Args[1]
	hostAlias := os.Args[2]
	tlsServerName := os.Args[3]

	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "read kubeconfig: %v\n", err)
		os.Exit(1)
	}
	text := string(data)
	text = regexp.MustCompile(`(?m)^\s*tls-server-name:\s+.*\n?`).ReplaceAllString(text, "")
	serverLine := regexp.MustCompile(`(?m)^(\s*)server:\s+https://(?:127\.0\.0\.1|localhost):(\d+)\s*$`)
	changed := false
	text = serverLine.ReplaceAllStringFunc(text, func(line string) string {
		matches := serverLine.FindStringSubmatch(line)
		if len(matches) != 3 {
			return line
		}
		changed = true
		return fmt.Sprintf("%sserver: https://%s:%s\n%stls-server-name: %s", matches[1], hostAlias, matches[2], matches[1], tlsServerName)
	})
	if !changed {
		return
	}
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "write kubeconfig: %v\n", err)
		os.Exit(1)
	}
}
