package main

import (
	"fmt"
	"os"
	"regexp"
	"strings"
)

func main() {
	if len(os.Args) != 8 {
		fmt.Fprintln(os.Stderr, "usage: render-kind-apiserver-oidc-manifest <source-path> <rendered-path> <issuer-url> <client-id> <ca-path> <dex-host> <gateway-ip>")
		os.Exit(2)
	}

	sourcePath := os.Args[1]
	renderedPath := os.Args[2]
	issuer := os.Args[3]
	clientID := os.Args[4]
	caPath := os.Args[5]
	dexHost := os.Args[6]
	gatewayIP := os.Args[7]

	data, err := os.ReadFile(sourcePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "read manifest: %v\n", err)
		os.Exit(1)
	}
	sourceLines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	renderedLines := make([]string, 0, len(sourceLines)+8)
	insertedOIDC := false
	insertedHostAliases := false
	seenHostNetwork := false

	oidcLine := regexp.MustCompile(`^\s*-\s*--oidc-(issuer-url|client-id|username-claim|groups-claim|ca-file)=`)
	serviceClusterIPRange := regexp.MustCompile(`^\s*-\s*--service-cluster-ip-range=`)
	topLevelSpecKey := regexp.MustCompile(`^  [A-Za-z0-9_-]+:`)
	hostNetwork := regexp.MustCompile(`^  hostNetwork:\s*(true|false)\s*$`)
	hostnameLine := regexp.MustCompile(`^\s*-\s+([^"'\s]+)\s*$`)
	managedSSOHostname := regexp.MustCompile(`^(dex|keycloak)\.`)

	for index := 0; index < len(sourceLines); {
		line := sourceLines[index]

		if oidcLine.MatchString(line) {
			index++
			continue
		}

		if line == "  hostAliases:" {
			blockLines := []string{line}
			index++
			for index < len(sourceLines) && !topLevelSpecKey.MatchString(sourceLines[index]) {
				blockLines = append(blockLines, sourceLines[index])
				index++
			}
			hostnames := []string{}
			for _, blockLine := range blockLines {
				matches := hostnameLine.FindStringSubmatch(blockLine)
				if len(matches) == 2 {
					hostnames = append(hostnames, strings.Trim(matches[1], `"'`))
				}
			}
			if len(hostnames) > 0 {
				allManaged := true
				for _, hostname := range hostnames {
					if hostname != dexHost && !managedSSOHostname.MatchString(hostname) {
						allManaged = false
						break
					}
				}
				if allManaged {
					continue
				}
			}
			fmt.Fprintf(os.Stderr, "unexpected existing kube-apiserver hostAliases block unrelated to %s; refusing to rewrite manifest automatically\n", dexHost)
			os.Exit(1)
		}

		if serviceClusterIPRange.MatchString(line) {
			renderedLines = append(renderedLines, line,
				fmt.Sprintf("    - --oidc-issuer-url=%s", issuer),
				fmt.Sprintf("    - --oidc-client-id=%s", clientID),
				"    - --oidc-username-claim=email",
				"    - --oidc-groups-claim=groups",
				fmt.Sprintf("    - --oidc-ca-file=%s", caPath),
			)
			insertedOIDC = true
			index++
			continue
		}

		if hostNetwork.MatchString(line) {
			if !insertedHostAliases {
				renderedLines = append(renderedLines,
					"  hostAliases:",
					fmt.Sprintf("  - ip: %q", gatewayIP),
					"    hostnames:",
					fmt.Sprintf("    - %s", dexHost),
				)
				insertedHostAliases = true
			}
			if seenHostNetwork {
				index++
				continue
			}
			renderedLines = append(renderedLines, line)
			seenHostNetwork = true
			index++
			continue
		}

		renderedLines = append(renderedLines, line)
		index++
	}

	if !insertedOIDC {
		fmt.Fprintln(os.Stderr, "failed to locate --service-cluster-ip-range= anchor while rendering kube-apiserver manifest")
		os.Exit(1)
	}
	if !seenHostNetwork {
		fmt.Fprintln(os.Stderr, "failed to locate hostNetwork stanza while rendering kube-apiserver manifest")
		os.Exit(1)
	}
	if err := os.WriteFile(renderedPath, []byte(strings.Join(renderedLines, "\n")+"\n"), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "write manifest: %v\n", err)
		os.Exit(1)
	}
}
