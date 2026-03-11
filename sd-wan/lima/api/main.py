from datetime import UTC, datetime
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
import httpx
import os
import re
import shlex
import subprocess
import time

app = FastAPI()

CLOUD_NAME = os.environ.get("CLOUD_NAME", "unknown")
CLOUD_IP = os.environ.get("CLOUD_IP", "unknown")
DNS_IP = os.environ.get("DNS_IP", "10.10.1.10")
TRACE_TARGET = os.environ.get("NETWORK_TRACE_TARGET", "api1.vanity.test")
TRACE_PORT = int(os.environ.get("NETWORK_TRACE_PORT", "443"))

HTML_PAGE = (
    """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>SD-WAN API</title>
    <style>
        body { font-family: monospace; background: #0d1117; color: #e6edf3; padding: 20px; }
        h1 { color: #58a6ff; }
        .box { background: #161b22; border: 1px solid #30363d; padding: 15px; margin: 15px 0; border-radius: 6px; }
        .label { color: #8b949e; font-size: 12px; text-transform: uppercase; }
        .value { color: #7ee787; font-size: 14px; margin-top: 5px; }
        code { background: #21262d; padding: 2px 6px; border-radius: 3px; color: #f0883e; }
        a { color: #58a6ff; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>SD-WAN API - """
    + CLOUD_NAME
    + """</h1>
    <div class="box"><div class="label">Cloud IP</div><div class="value">"""
    + CLOUD_IP
    + """</div></div>
    <div class="box">
        <div class="label">Endpoints</div>
        <ul>
            <li><a href="/info">/info</a> - Service info (JSON)</li>
            <li><a href="/dns-raw?domain=api1.vanity.test">/dns-raw?domain=api1.vanity.test</a> - DNS query</li>
        </ul>
    </div>
</body>
</html>"""
)

_TRACEROUTE_HOP_RE = re.compile(r"^\s*\d+\s+([0-9]{1,3}(?:\.[0-9]{1,3}){3})\b")
_DIG_ANSWER_RE = re.compile(r"^[^;\s]+\s+\d+\s+IN\s+A\s+([0-9]{1,3}(?:\.[0-9]{1,3}){3})$")
_IP_ADDR_RE = re.compile(r"inet\s+([0-9]{1,3}(?:\.[0-9]{1,3}){3})/")


def _run_command(args: list[str], timeout_seconds: int):
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


def _parse_dns_answers(output: str):
    answers = []
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


def _parse_traceroute_hops(output: str):
    hops = []

    for line in output.splitlines():
        match = _TRACEROUTE_HOP_RE.match(line)
        if match:
            hops.append(match.group(1))

    return hops


def _parse_endpoint(endpoint: str):
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


def _extract_tunnel_peer_ip(allowed_ips: list[str]):
    for cidr in allowed_ips:
        ip, _, prefix = cidr.partition("/")
        if prefix == "32":
            return ip
    return None


def _get_local_tunnel_ip():
    local_ip_result = _run_command(["ip", "-4", "-o", "addr", "show", "dev", "wg0"], timeout_seconds=3)
    if local_ip_result["exit_code"] != 0:
        return None

    match = _IP_ADDR_RE.search(local_ip_result["raw_output"])
    return match.group(1) if match else None


def _get_tunnel_peers():
    peers = []

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


@app.get("/", response_class=HTMLResponse)
async def root(request: Request):
    return HTML_PAGE


@app.get("/proxy/{system}")
async def proxy_call(system: str, request: Request):
    # Use DNS-resolved external VIPs instead of hardcoded IPs
    targets = {
        "cloud1": "https://inbound.cloud1.test",
        "cloud2": "https://api1.vanity.test",
        "cloud3": "https://inbound.cloud3.test",
    }
    if system not in targets:
        return {"error": "Unknown system", "available": list(targets.keys())}

    # Use mTLS client certs if available
    cert = None
    pki_dir = "/etc/pki"
    client_cert = os.path.join(pki_dir, "client.crt")
    client_key = os.path.join(pki_dir, "client.key")
    ca_cert = os.path.join(pki_dir, "root-ca.crt")
    if os.path.exists(client_cert) and os.path.exists(client_key):
        cert = (client_cert, client_key)

    verify = ca_cert if os.path.exists(ca_cert) else False

    try:
        async with httpx.AsyncClient(
            timeout=10.0, cert=cert, verify=verify
        ) as client:
            resp = await client.get(f"{targets[system]}/info")
            return {
                "this_system": CLOUD_NAME,
                "this_ip": CLOUD_IP,
                "called_system": system,
                "called_url": targets[system],
                "status": resp.status_code,
                "response": resp.json(),
                "client_ip": request.client.host if request.client else "unknown",
            }
    except Exception as e:
        return {"this_system": CLOUD_NAME, "called_system": system, "error": str(e)}


@app.get("/dns")
async def dns_query(request: Request, domain: str = "app1.cloud1.test"):
    import struct, socket

    # Use local DNS resolver (10.10.1.10 or 172.31.1.10)
    dns_ip = DNS_IP
    try:
        txn_id = 0x1234
        header = struct.pack("!HHHHHH", txn_id, 0x0100, 1, 0, 0, 0)
        qname = (
            b"".join(bytes([len(p)]) + p.encode() for p in domain.split(".")) + b"\x00"
        )
        dns_packet = header + qname + struct.pack("!HH", 1, 1)

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(5.0)
        sock.sendto(dns_packet, (dns_ip, 53))
        response, _ = sock.recvfrom(512)
        sock.close()

        return {
            "query": domain,
            "resolver": dns_ip,
            "result": "resolved (see /dns-raw)",
        }
    except Exception as e:
        return {"query": domain, "resolver": dns_ip, "error": str(e)}


@app.get("/dns-raw")
async def dns_raw(
    request: Request, domain: str = "app1.cloud1.test", enhanced: bool = False
):
    import struct, socket

    dns_ip, dns_port = DNS_IP, 53
    txn_id = 0x1234
    header = struct.pack("!HHHHHH", txn_id, 0x0100, 1, 0, 0, 0)
    qname = b"".join(bytes([len(p)]) + p.encode() for p in domain.split(".")) + b"\x00"
    dns_packet = header + qname + struct.pack("!HH", 1, 1)

    raw_req = f";; QUESTION: {domain}. IN A\n"
    if enhanced:
        raw_req += f";; bytes: {dns_packet.hex()[:64]}...\n"

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(5.0)
        sock.sendto(dns_packet, (dns_ip, dns_port))
        response, _ = sock.recvfrom(512)
        sock.close()

        # Parse response header
        ancount = struct.unpack("!HHHHHH", response[:12])[3]

        result_info = f"ANSWERS: {ancount}"
        if enhanced and len(response) > 20:
            result_info += f" | bytes: {response.hex()[:64]}..."

        raw_resp = f""";; {result_info}
"""
    except Exception as e:
        raw_resp = f";; ERROR: {e}"

    return {
        "query": domain,
        "resolver": f"{dns_ip}:{dns_port}",
        "this_system": CLOUD_NAME,
        "wire": {"request": raw_req, "response": raw_resp},
    }


@app.get("/info")
async def info(request: Request):
    headers = dict(request.headers)
    return {
        "system": CLOUD_NAME,
        "ip": CLOUD_IP,
        "client_ip": request.client.host if request.client else "unknown",
        "ingress_cloud": headers.get("x-ingress-cloud"),
        "egress_cloud": headers.get("x-egress-cloud"),
        "client_cn": headers.get("x-client-cn"),
        "client_verify": headers.get("x-client-verify"),
    }


@app.get("/network/diagnostics")
async def network_diagnostics():
    dns_result = _run_command(
        ["dig", "+time=2", "+tries=1", TRACE_TARGET, "A", f"@{DNS_IP}"],
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
        "viewpoint": CLOUD_NAME,
        "target": f"{TRACE_TARGET}:{TRACE_PORT}",
        "generated_at": datetime.now(UTC).isoformat(),
        "dns": {
            "resolver": DNS_IP,
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
