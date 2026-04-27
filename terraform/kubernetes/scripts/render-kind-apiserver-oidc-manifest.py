#!/usr/bin/env python3

import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 8:
        raise SystemExit(
            "usage: render-kind-apiserver-oidc-manifest.py "
            "<source-path> <rendered-path> <issuer-url> <client-id> <ca-path> <dex-host> <gateway-ip>"
        )

    source_path = Path(sys.argv[1])
    rendered_path = Path(sys.argv[2])
    issuer = sys.argv[3]
    client_id = sys.argv[4]
    ca_path = sys.argv[5]
    dex_host = sys.argv[6]
    gateway_ip = sys.argv[7]

    source_lines = source_path.read_text().splitlines()
    rendered_lines = []
    inserted_oidc = False
    inserted_host_aliases = False
    seen_host_network = False

    oidc_line = re.compile(r"^\s*-\s*--oidc-(issuer-url|client-id|username-claim|groups-claim|ca-file)=")
    service_cluster_ip_range = re.compile(r"^\s*-\s*--service-cluster-ip-range=")
    top_level_spec_key = re.compile(r"^  [A-Za-z0-9_-]+:")
    host_network = re.compile(r"^  hostNetwork:\s*(true|false)\s*$")
    hostname_line = re.compile(r"^\s*-\s+([^\"'\s]+)\s*$")
    managed_sso_hostname = re.compile(r"^(dex|keycloak)\.")

    index = 0
    while index < len(source_lines):
        line = source_lines[index]

        if oidc_line.match(line):
            index += 1
            continue

        if line == "  hostAliases:":
            block_lines = [line]
            index += 1
            while index < len(source_lines) and not top_level_spec_key.match(source_lines[index]):
                block_lines.append(source_lines[index])
                index += 1
            hostnames = []
            for block_line in block_lines:
                match = hostname_line.match(block_line)
                if match:
                    hostnames.append(match.group(1).strip("\"'"))
            if hostnames and all(
                hostname == dex_host or managed_sso_hostname.match(hostname)
                for hostname in hostnames
            ):
                continue
            raise SystemExit(
                f"unexpected existing kube-apiserver hostAliases block unrelated to {dex_host}; "
                "refusing to rewrite manifest automatically"
            )

        if service_cluster_ip_range.match(line):
            rendered_lines.append(line)
            rendered_lines.extend(
                [
                    f"    - --oidc-issuer-url={issuer}",
                    f"    - --oidc-client-id={client_id}",
                    "    - --oidc-username-claim=email",
                    "    - --oidc-groups-claim=groups",
                    f"    - --oidc-ca-file={ca_path}",
                ]
            )
            inserted_oidc = True
            index += 1
            continue

        if host_network.match(line):
            if not inserted_host_aliases:
                rendered_lines.extend(
                    [
                        "  hostAliases:",
                        f'  - ip: "{gateway_ip}"',
                        "    hostnames:",
                        f"    - {dex_host}",
                    ]
                )
                inserted_host_aliases = True
            if seen_host_network:
                index += 1
                continue
            rendered_lines.append(line)
            seen_host_network = True
            index += 1
            continue

        rendered_lines.append(line)
        index += 1

    if not inserted_oidc:
        raise SystemExit(
            "failed to locate --service-cluster-ip-range= anchor while rendering kube-apiserver manifest"
        )

    if not seen_host_network:
        raise SystemExit("failed to locate hostNetwork stanza while rendering kube-apiserver manifest")

    rendered_path.write_text("\n".join(rendered_lines) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
