"""Network diagnostics endpoints for SD-WAN deployments."""

from __future__ import annotations

import os
import re
import shlex
import subprocess
from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends

from ..auth_utils import get_current_user

router = APIRouter(prefix="/api/v1/network", tags=["network"])

_TRACEROUTE_HOP_RE = re.compile(r"^\s*\d+\s+([0-9]{1,3}(?:\.[0-9]{1,3}){3})\b")
_DIG_ANSWER_RE = re.compile(r"^[^;\s]+\s+\d+\s+IN\s+A\s+([0-9]{1,3}(?:\.[0-9]{1,3}){3})$")
_IP_ADDR_RE = re.compile(r"inet\s+([0-9]{1,3}(?:\.[0-9]{1,3}){3})/")


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None:
        return default

    try:
        return int(raw)
    except ValueError:
        return default


TRACE_TARGET = os.getenv("NETWORK_TRACE_TARGET", "api1.vanity.test")
TRACE_PORT = _env_int("NETWORK_TRACE_PORT", 443)
DNS_RESOLVER = os.getenv("DNS_IP", "10.10.1.10")


def _run_command(args: list[str], timeout_seconds: int) -> dict[str, Any]:
    command = " ".join(shlex.quote(arg) for arg in args)

    try:
        completed = subprocess.run(
            args,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
        )
        output = "\n".join(part.strip() for part in [completed.stdout, completed.stderr] if part).strip()
        return {
            "command": command,
            "exit_code": completed.returncode,
            "raw_output": output,
        }
    except subprocess.TimeoutExpired as exc:
        timeout_output = "\n".join(part.strip() for part in [exc.stdout or "", exc.stderr or ""] if part).strip()
        return {
            "command": command,
            "exit_code": 124,
            "raw_output": timeout_output or "command timed out",
        }
    except FileNotFoundError:
        return {
            "command": command,
            "exit_code": 127,
            "raw_output": "command not available",
        }


def _parse_dns_answers(output: str) -> list[str]:
    answers: list[str] = []
    in_answer_section = False

    for line in output.splitlines():
        if line.startswith(";; ANSWER SECTION:"):
            in_answer_section = True
            continue

        if in_answer_section and line.startswith(";;"):
            break

        if not in_answer_section:
            continue

        match = _DIG_ANSWER_RE.match(line.strip())
        if match:
            answers.append(match.group(1))

    return answers


def _parse_traceroute_hops(output: str) -> list[str]:
    hops: list[str] = []

    for line in output.splitlines():
        match = _TRACEROUTE_HOP_RE.match(line)
        if match:
            hops.append(match.group(1))

    return hops


def _parse_endpoint(endpoint: str) -> tuple[str | None, int | None]:
    if endpoint in {"", "(none)"}:
        return None, None

    if endpoint.startswith("[") and "]:" in endpoint:
        host, _, port = endpoint[1:].partition("]:")
    else:
        host, separator, port = endpoint.rpartition(":")
        if separator == "":
            return endpoint, None

    try:
        return host, int(port)
    except ValueError:
        return host, None


def _extract_tunnel_peer_ip(allowed_ips: list[str]) -> str | None:
    for cidr in allowed_ips:
        ip, _, prefix = cidr.partition("/")
        if prefix == "32":
            return ip
    return None


def _get_local_tunnel_ip() -> str | None:
    local_ip_result = _run_command(["ip", "-4", "-o", "addr", "show", "dev", "wg0"], timeout_seconds=3)
    if local_ip_result["exit_code"] != 0:
        return None

    match = _IP_ADDR_RE.search(local_ip_result["raw_output"])
    return match.group(1) if match else None


def _get_tunnel_peers() -> list[dict[str, Any]]:
    peers: list[dict[str, Any]] = []

    wg_result = _run_command(["wg", "show", "wg0", "dump"], timeout_seconds=3)
    if wg_result["exit_code"] != 0:
        return peers

    lines = [line for line in wg_result["raw_output"].splitlines() if line.strip()]
    if len(lines) < 2:
        return peers

    for line in lines[1:]:
        fields = line.split("\t")
        if len(fields) < 8:
            continue

        endpoint_ip, endpoint_port = _parse_endpoint(fields[2])
        allowed_ips = [ip.strip() for ip in fields[3].split(",") if ip.strip()]
        latest_handshake = int(fields[4]) if fields[4].isdigit() and fields[4] != "0" else None
        tunnel_peer_ip = _extract_tunnel_peer_ip(allowed_ips)

        peers.append(
            {
                "public_key": fields[0],
                "endpoint_ip": endpoint_ip,
                "endpoint_port": endpoint_port,
                "allowed_ips": allowed_ips,
                "tunnel_peer_ip": tunnel_peer_ip,
                "latest_handshake_unix": latest_handshake,
            }
        )

    return peers


@router.get("/diagnostics")
async def get_network_diagnostics(_current_user: str = Depends(get_current_user)):
    dns_result = _run_command(
        ["dig", "+time=2", "+tries=1", TRACE_TARGET, "A", f"@{DNS_RESOLVER}"],
        timeout_seconds=5,
    )
    dns_answers = _parse_dns_answers(dns_result["raw_output"])

    traceroute_result = _run_command(
        [
            "traceroute",
            "-n",
            "-T",
            "-p",
            str(TRACE_PORT),
            "-q",
            "1",
            "-w",
            "1",
            TRACE_TARGET,
        ],
        timeout_seconds=10,
    )
    traceroute_hops = _parse_traceroute_hops(traceroute_result["raw_output"])

    tunnel_peers = _get_tunnel_peers()
    peer_tunnel_ips = sorted({peer["tunnel_peer_ip"] for peer in tunnel_peers if peer["tunnel_peer_ip"]})
    peer_endpoint_ips = sorted({peer["endpoint_ip"] for peer in tunnel_peers if peer["endpoint_ip"]})

    return {
        "target": f"{TRACE_TARGET}:{TRACE_PORT}",
        "generated_at": datetime.now(UTC).isoformat(),
        "dns": {
            "resolver": DNS_RESOLVER,
            "answers": dns_answers,
            **dns_result,
        },
        "traceroute": {
            "hops": traceroute_hops,
            "hop_count": len(traceroute_hops),
            **traceroute_result,
        },
        "tunnel": {
            "interface": "wg0",
            "local_tunnel_ip": _get_local_tunnel_ip(),
            "peer_tunnel_ips": peer_tunnel_ips,
            "peer_endpoint_ips": peer_endpoint_ips,
            "peers": tunnel_peers,
        },
    }
