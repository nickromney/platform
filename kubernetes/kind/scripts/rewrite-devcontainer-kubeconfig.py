#!/usr/bin/env python3

import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: rewrite-devcontainer-kubeconfig.py <kubeconfig-path> <host-alias> <tls-server-name>"
        )

    path = Path(sys.argv[1])
    host_alias = sys.argv[2]
    tls_server_name = sys.argv[3]
    text = path.read_text()

    # kind exports a host-loopback endpoint such as 127.0.0.1:6443. Inside a
    # host-socket devcontainer, that loopback resolves to the container, not the
    # host, so the API server must be addressed via host.docker.internal while the
    # TLS hostname remains "localhost".
    text = re.sub(r"^\s*tls-server-name:\s+.*\n?", "", text, flags=re.MULTILINE)
    text, count = re.subn(
        r"^(?P<indent>\s*)server:\s+https://(?:127\.0\.0\.1|localhost):(?P<port>\d+)\s*$",
        lambda match: (
            f"{match.group('indent')}server: https://{host_alias}:{match.group('port')}\n"
            f"{match.group('indent')}tls-server-name: {tls_server_name}"
        ),
        text,
        flags=re.MULTILINE,
    )

    if count:
        path.write_text(text)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
