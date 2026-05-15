from __future__ import annotations

import argparse
import json
import os
import platform
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

APP_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = APP_DIR.parents[1]
SENTIMENT_DIR = REPO_ROOT / "apps" / "sentiment"
RUN_DIR = APP_DIR / ".run" / "llamacpp"
DOWNLOAD_DIR = RUN_DIR / "downloads"
RUNTIME_ROOT = RUN_DIR / "runtime"
MODEL_DIR = RUN_DIR / "models"
PID_FILE = RUN_DIR / "llama-server.pid"
LOG_FILE = RUN_DIR / "llama-server.log"
MEMORY_LOG_FILE = RUN_DIR / "llama-server-memory.jsonl"

LLAMACPP_RELEASES_LATEST_URL = "https://api.github.com/repos/ggerganov/llama.cpp/releases/latest"
DEFAULT_MODEL_NAME = "qwen2.5-0.5b-instruct-q4_k_m"
DEFAULT_MODEL_FILENAME = f"{DEFAULT_MODEL_NAME}.gguf"
DEFAULT_MODEL_URL = (
    "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
)
DEFAULT_PORT = 8087


class LlamaCppGatewayError(RuntimeError):
    pass


@dataclass
class RuntimeAsset:
    tag: str
    asset_name: str
    download_url: str


@dataclass
class MemorySampler:
    pid: int
    log_path: Path = MEMORY_LOG_FILE
    interval_seconds: float = 0.5
    samples: list[int] = field(default_factory=list)
    _stop: threading.Event = field(default_factory=threading.Event)
    _thread: threading.Thread | None = None

    def __enter__(self) -> MemorySampler:
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        self._thread = threading.Thread(target=self._run, name="llamacpp-memory-sampler", daemon=True)
        self._thread.start()
        return self

    def __exit__(self, *_exc: object) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=2)

    @property
    def peak_kib(self) -> int:
        return max(self.samples, default=0)

    @property
    def final_kib(self) -> int:
        return self.samples[-1] if self.samples else 0

    def _run(self) -> None:
        with self.log_path.open("a", encoding="utf-8") as log_file:
            while not self._stop.is_set():
                rss = rss_kib(self.pid)
                if rss is not None:
                    self.samples.append(rss)
                    log_file.write(json.dumps({"ts": time.time(), "pid": self.pid, "rss_kib": rss}) + "\n")
                    log_file.flush()
                self._stop.wait(self.interval_seconds)


def main() -> int:
    parser = argparse.ArgumentParser(description="Manage a host llama.cpp server behind the APIM AI gateway example.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("ensure", "start", "stop", "status", "memory", "up", "down", "smoke"):
        subparsers.add_parser(command)

    args = parser.parse_args()
    if args.command == "ensure":
        command_ensure()
    elif args.command == "start":
        command_start()
    elif args.command == "stop":
        command_stop()
    elif args.command == "status":
        command_status()
    elif args.command == "memory":
        command_memory()
    elif args.command == "up":
        command_up()
    elif args.command == "down":
        command_down()
    elif args.command == "smoke":
        command_smoke()
    return 0


def command_ensure() -> tuple[Path, Path]:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    runtime = ensure_runtime()
    model = ensure_model()
    print(f"llama.cpp runtime: {runtime}")
    print(f"llama.cpp model:   {model} ({format_bytes(model.stat().st_size)})")
    return runtime, model


def command_start() -> None:
    server, model = command_ensure()
    pid = current_managed_pid()
    if pid is not None:
        wait_for_llama_server(pid)
        print_server_status(pid, "llama-server already running")
        return

    guard_unmanaged_port()
    pid = launch_server(server, model)
    wait_for_llama_server(pid)
    print_server_status(pid, "llama-server started")


def command_stop() -> None:
    stop_server()


def command_status() -> None:
    pid = read_pid_file()
    if pid is None:
        print("llama-server: not managed by this helper")
        print(f"runtime dir:  {RUNTIME_ROOT}")
        print(f"model dir:    {MODEL_DIR}")
        return
    if not process_alive(pid):
        print(f"llama-server: stale pid file ({pid})")
        print(f"log:          {LOG_FILE}")
        return
    print_server_status(pid, "llama-server running")


def command_memory() -> None:
    pid = require_managed_pid()
    rss = rss_kib(pid)
    if rss is None:
        raise LlamaCppGatewayError(f"could not read RSS for pid {pid}")
    print(f"llama-server rss: {format_kib(rss)} ({rss} KiB)")
    print(f"memory log:       {MEMORY_LOG_FILE}")


def command_up() -> None:
    command_start()
    compose_up()
    wait_for_apim_gateway()
    print(f"APIM AI gateway: {apim_base_url()}/ai/v1/chat/completions")


def command_down() -> None:
    compose_down()
    stop_server()


def command_smoke() -> None:
    server, model = command_ensure()
    compose_down()
    stop_server(quiet=True)
    guard_unmanaged_port()

    pid = launch_server(server, model)
    keep_running = env_bool("LLAMACPP_KEEP_RUNNING_AFTER_SMOKE", default=False)
    try:
        with MemorySampler(pid) as sampler:
            wait_for_llama_server(pid)
            compose_up()
            wait_for_apim_gateway()
            check_apim_model_request()
            check_apim_chat_request()
            run_sentiment_smoke()
    finally:
        compose_down()
        if not keep_running:
            stop_server(quiet=True)

    print("llama.cpp APIM AI gateway smoke passed")
    print_memory_summary(sampler)


def ensure_runtime() -> Path:
    asset = resolve_runtime_asset()
    runtime_dir = RUNTIME_ROOT / asset.tag
    existing = find_llama_server(runtime_dir)
    if existing is not None:
        return existing

    archive_path = DOWNLOAD_DIR / asset.asset_name
    download_file(asset.download_url, archive_path, label=f"llama.cpp {asset.tag} runtime")
    if runtime_dir.exists():
        shutil.rmtree(runtime_dir)
    runtime_dir.mkdir(parents=True, exist_ok=True)
    safe_extract_tar(archive_path, runtime_dir)

    server = find_llama_server(runtime_dir)
    if server is None:
        raise LlamaCppGatewayError(f"could not find llama-server after extracting {archive_path}")
    server.chmod(server.stat().st_mode | 0o111)
    return server


def resolve_runtime_asset() -> RuntimeAsset:
    requested_tag = os.getenv("LLAMACPP_RELEASE_TAG", "").strip()
    release_url = (
        f"https://api.github.com/repos/ggerganov/llama.cpp/releases/tags/{requested_tag}"
        if requested_tag
        else LLAMACPP_RELEASES_LATEST_URL
    )
    release = get_json(release_url)
    tag = str(release.get("tag_name") or requested_tag or "").strip()
    if not tag:
        raise LlamaCppGatewayError(f"could not resolve llama.cpp release tag from {release_url}")

    suffix = platform_asset_suffix()
    assets = release.get("assets") or []
    for asset in assets:
        name = str(asset.get("name") or "")
        if name.endswith(suffix):
            url = str(asset.get("browser_download_url") or "")
            if not url:
                break
            return RuntimeAsset(tag=tag, asset_name=name, download_url=url)

    available = ", ".join(str(asset.get("name") or "") for asset in assets)
    raise LlamaCppGatewayError(f"no llama.cpp release asset ending with {suffix!r}; available assets: {available}")


def platform_asset_suffix() -> str:
    system = platform.system().lower()
    machine = platform.machine().lower()
    if machine in {"arm64", "aarch64"}:
        arch = "arm64"
    elif machine in {"x86_64", "amd64"}:
        arch = "x64"
    else:
        raise LlamaCppGatewayError(f"unsupported CPU architecture for prebuilt llama.cpp runtime: {machine}")

    if system == "darwin":
        return f"bin-macos-{arch}.tar.gz"
    if system == "linux":
        return f"bin-ubuntu-{arch}.tar.gz"
    raise LlamaCppGatewayError(f"unsupported OS for prebuilt llama.cpp runtime: {system}")


def ensure_model() -> Path:
    configured_model_path = os.getenv("LLAMACPP_MODEL_PATH", "").strip()
    if configured_model_path:
        model_path = Path(configured_model_path).expanduser().resolve()
        if not model_path.exists():
            raise LlamaCppGatewayError(f"LLAMACPP_MODEL_PATH does not exist: {model_path}")
        return model_path

    model_url = os.getenv("LLAMACPP_MODEL_URL", DEFAULT_MODEL_URL)
    model_filename = os.getenv("LLAMACPP_MODEL_FILENAME", DEFAULT_MODEL_FILENAME)
    model_path = MODEL_DIR / model_filename
    download_file(model_url, model_path, label="llama.cpp GGUF model")
    return model_path


def download_file(url: str, destination: Path, *, label: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and destination.stat().st_size > 0:
        print(f"{label}: already present at {destination} ({format_bytes(destination.stat().st_size)})")
        return

    part_path = destination.with_suffix(destination.suffix + ".part")
    if part_path.exists():
        part_path.unlink()

    print(f"{label}: downloading {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "apim-simulator-llamacpp-helper"})
    started = time.monotonic()
    last_report = started
    written = 0
    with urllib.request.urlopen(request, timeout=60) as response, part_path.open("wb") as file:
        total = int(response.headers.get("content-length") or 0)
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            file.write(chunk)
            written += len(chunk)
            now = time.monotonic()
            if now - last_report >= 5:
                print_download_progress(label, written, total, started)
                last_report = now
    os.replace(part_path, destination)
    print_download_progress(label, written, destination.stat().st_size, started, final=True)


def print_download_progress(label: str, written: int, total: int, started: float, *, final: bool = False) -> None:
    elapsed = max(time.monotonic() - started, 0.001)
    rate = written / elapsed
    if total:
        pct = min(100.0, (written / total) * 100)
        status = "downloaded" if final else "downloading"
        print(f"{label}: {status} {format_bytes(written)} / {format_bytes(total)} ({pct:.1f}%, {format_bytes(rate)}/s)")
        return
    status = "downloaded" if final else "downloading"
    print(f"{label}: {status} {format_bytes(written)} ({format_bytes(rate)}/s)")


def safe_extract_tar(archive_path: Path, destination: Path) -> None:
    destination_root = destination.resolve()
    with tarfile.open(archive_path, "r:gz") as archive:
        for member in archive.getmembers():
            target = (destination / member.name).resolve()
            if destination_root != target and destination_root not in target.parents:
                raise LlamaCppGatewayError(f"unsafe path in tar archive: {member.name}")
        archive.extractall(destination)


def find_llama_server(runtime_dir: Path) -> Path | None:
    if not runtime_dir.exists():
        return None
    candidates = sorted(
        (path for path in runtime_dir.rglob("llama-server") if path.is_file()),
        key=lambda path: (len(path.parts), str(path)),
    )
    return candidates[0] if candidates else None


def launch_server(server: Path, model: Path) -> int:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    command = llama_server_command(server, model)
    with LOG_FILE.open("ab") as log_file:
        log_file.write((f"\n==> {' '.join(shlex.quote(part) for part in command)}\n").encode())
        process = subprocess.Popen(  # noqa: S603
            command,
            cwd=APP_DIR,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    PID_FILE.write_text(str(process.pid), encoding="utf-8")
    print(f"llama-server pid: {process.pid}")
    print(f"llama-server log: {LOG_FILE}")
    return process.pid


def llama_server_command(server: Path, model: Path) -> list[str]:
    command = [
        str(server),
        "-m",
        str(model),
        "--host",
        os.getenv("LLAMACPP_HOST", "127.0.0.1"),
        "--port",
        str(llamacpp_port()),
        "-c",
        os.getenv("LLAMACPP_CTX_SIZE", "1024"),
        "-ngl",
        os.getenv("LLAMACPP_N_GPU_LAYERS", "0"),
    ]
    threads = os.getenv("LLAMACPP_THREADS", "").strip()
    if threads:
        command.extend(["-t", threads])
    extra_args = os.getenv("LLAMACPP_EXTRA_ARGS", "").strip()
    if extra_args:
        command.extend(shlex.split(extra_args))
    return command


def wait_for_llama_server(pid: int) -> None:
    timeout = float(os.getenv("LLAMACPP_READY_TIMEOUT_SECONDS", "180"))
    deadline = time.monotonic() + timeout
    url = f"http://127.0.0.1:{llamacpp_port()}/v1/models"
    last_error = ""
    while time.monotonic() < deadline:
        if not process_alive(pid):
            raise LlamaCppGatewayError(f"llama-server exited before readiness.\n{tail_log(LOG_FILE)}")
        try:
            payload = request_json("GET", url, timeout=3)
            if isinstance(payload, dict):
                return
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
        time.sleep(1)
    raise LlamaCppGatewayError(f"timed out waiting for llama-server at {url}: {last_error}\n{tail_log(LOG_FILE)}")


def stop_server(*, quiet: bool = False) -> None:
    pid = read_pid_file()
    if pid is None:
        if not quiet:
            print("llama-server: no managed pid file")
        return
    if not process_alive(pid):
        PID_FILE.unlink(missing_ok=True)
        if not quiet:
            print(f"llama-server: removed stale pid file ({pid})")
        return

    terminate_process_group(pid, signal.SIGTERM)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if not process_alive(pid):
            PID_FILE.unlink(missing_ok=True)
            if not quiet:
                print(f"llama-server stopped: {pid}")
            return
        time.sleep(0.5)

    terminate_process_group(pid, signal.SIGKILL)
    PID_FILE.unlink(missing_ok=True)
    if not quiet:
        print(f"llama-server killed: {pid}")


def terminate_process_group(pid: int, sig: signal.Signals) -> None:
    try:
        os.killpg(pid, sig)
    except ProcessLookupError:
        return
    except OSError:
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            return


def guard_unmanaged_port() -> None:
    if url_responds(f"http://127.0.0.1:{llamacpp_port()}/v1/models"):
        raise LlamaCppGatewayError(
            f"port {llamacpp_port()} already has an unmanaged OpenAI-compatible server; "
            "stop it or set LLAMACPP_PORT before using this helper"
        )


def current_managed_pid() -> int | None:
    pid = read_pid_file()
    if pid is None:
        return None
    if process_alive(pid):
        return pid
    PID_FILE.unlink(missing_ok=True)
    return None


def require_managed_pid() -> int:
    pid = current_managed_pid()
    if pid is None:
        raise LlamaCppGatewayError("llama-server is not running under this helper")
    return pid


def read_pid_file() -> int | None:
    try:
        value = PID_FILE.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def process_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def rss_kib(pid: int) -> int | None:
    result = subprocess.run(  # noqa: S603
        ["ps", "-o", "rss=", "-p", str(pid)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    value = result.stdout.strip()
    if not value:
        return None
    try:
        return int(value.splitlines()[0].strip())
    except ValueError:
        return None


def compose_up() -> None:
    run_checked(compose_command("up", "--build", "-d"), cwd=APP_DIR)


def compose_down() -> None:
    run_checked(compose_command("down", "--remove-orphans"), cwd=APP_DIR)


def compose_command(*args: str) -> list[str]:
    command = shlex.split(os.getenv("COMPOSE_CMD") or os.getenv("COMPOSE") or "docker compose")
    project_args = shlex.split(os.getenv("LLAMACPP_COMPOSE_PROJECT_ARGS", ""))
    for compose_file in ("compose.yml", "compose.public.yml", "compose.ai-gateway.llamacpp.yml"):
        command.extend(["-f", compose_file])
    command.extend(project_args)
    command.extend(args)
    return command


def run_checked(command: Sequence[str], *, cwd: Path, env: dict[str, str] | None = None) -> None:
    print(f"+ {' '.join(shlex.quote(part) for part in command)}")
    subprocess.run(command, cwd=cwd, env=env, check=True)  # noqa: S603


def wait_for_apim_gateway() -> None:
    wait_for_http_json(f"{apim_base_url()}/apim/health", label="APIM simulator health")
    wait_for_http_json(f"{apim_base_url()}/ai/v1/models", label="APIM llama.cpp models")


def wait_for_http_json(url: str, *, label: str) -> None:
    deadline = time.monotonic() + float(os.getenv("APIM_LLAMACPP_READY_TIMEOUT_SECONDS", "120"))
    last_error = ""
    while time.monotonic() < deadline:
        try:
            request_json("GET", url, timeout=5)
            return
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
            time.sleep(2)
    raise LlamaCppGatewayError(f"timed out waiting for {label} ({url}): {last_error}")


def check_apim_model_request() -> None:
    payload = request_json("GET", f"{apim_base_url()}/ai/v1/models", timeout=15)
    data = payload.get("data") if isinstance(payload, dict) else None
    if not isinstance(data, list):
        raise LlamaCppGatewayError(f"unexpected /v1/models payload through APIM: {payload}")
    print(f"APIM /v1/models returned {len(data)} model record(s)")


def check_apim_chat_request() -> None:
    payload = {
        "model": model_name(),
        "temperature": 0,
        "max_tokens": 64,
        "messages": [
            {
                "role": "system",
                "content": (
                    'You are a sentiment classifier. Return only compact JSON with keys "label" and "confidence". '
                    'The "label" value must be exactly "positive", "negative", or "neutral". '
                    'Example: {"label":"positive","confidence":0.9}.'
                ),
            },
            {"role": "user", "content": "I love how small and fast this is."},
        ],
    }
    response = request_json("POST", f"{apim_base_url()}/ai/v1/chat/completions", payload=payload, timeout=90)
    choices = response.get("choices") if isinstance(response, dict) else None
    if not isinstance(choices, list) or not choices:
        raise LlamaCppGatewayError(f"unexpected chat completion payload through APIM: {response}")
    content = str((choices[0].get("message") or {}).get("content") or choices[0].get("text") or "").strip()
    if not content:
        raise LlamaCppGatewayError(f"empty chat completion content through APIM: {response}")
    print(f"APIM chat completion returned: {content[:160]}")


def run_sentiment_smoke() -> None:
    env = os.environ.copy()
    env["APIM_AI_GATEWAY_BASE_URL"] = apim_base_url()
    env["SENTIMENT_APIM_AI_GATEWAY_URL"] = env.get("SENTIMENT_APIM_AI_GATEWAY_URL") or sentiment_container_ai_url()
    env["SENTIMENT_APIM_AI_GATEWAY_MODEL"] = env.get("SENTIMENT_APIM_AI_GATEWAY_MODEL") or model_name()
    env["SENTIMENT_APIM_AI_GATEWAY_TIMEOUT_MS"] = env.get("SENTIMENT_APIM_AI_GATEWAY_TIMEOUT_MS") or "60000"

    comments_path = SENTIMENT_DIR / "data" / "comments.csv"
    comments_snapshot = comments_path.read_bytes() if comments_path.exists() else None
    try:
        run_checked(["make", "-C", str(SENTIMENT_DIR), "smoke-apim-ai-gateway"], cwd=REPO_ROOT, env=env)
    finally:
        if env_bool("LLAMACPP_RESTORE_SENTIMENT_DATA", default=True):
            if comments_snapshot is None:
                comments_path.unlink(missing_ok=True)
            else:
                comments_path.write_bytes(comments_snapshot)


def request_json(method: str, url: str, *, payload: dict[str, Any] | None = None, timeout: float) -> dict[str, Any]:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read()
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise LlamaCppGatewayError(f"{method} {url} returned HTTP {exc.code}: {body[:500]}") from exc
    try:
        parsed = json.loads(body.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise LlamaCppGatewayError(f"{method} {url} returned non-JSON: {body[:500]!r}") from exc
    if not isinstance(parsed, dict):
        raise LlamaCppGatewayError(f"{method} {url} returned non-object JSON: {parsed!r}")
    return parsed


def url_responds(url: str) -> bool:
    try:
        request_json("GET", url, timeout=1)
    except Exception:  # noqa: BLE001
        return False
    return True


def get_json(url: str) -> dict[str, Any]:
    request = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "apim-simulator"})
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if not isinstance(payload, dict):
        raise LlamaCppGatewayError(f"expected object JSON from {url}")
    return payload


def print_server_status(pid: int, label: str) -> None:
    rss = rss_kib(pid)
    print(label)
    print(f"pid:      {pid}")
    print(f"rss:      {format_kib(rss) if rss is not None else 'unknown'}")
    print(f"endpoint: http://127.0.0.1:{llamacpp_port()}/v1/chat/completions")
    print(f"log:      {LOG_FILE}")


def print_memory_summary(sampler: MemorySampler) -> None:
    current_pid = read_pid_file()
    current_rss = rss_kib(current_pid) if current_pid is not None and process_alive(current_pid) else None
    print(f"- memory samples: {len(sampler.samples)}")
    print(f"- peak RSS:       {format_kib(sampler.peak_kib)}")
    print(f"- final RSS:      {format_kib(sampler.final_kib)}")
    if current_rss is not None:
        print(f"- current RSS:    {format_kib(current_rss)}")
    print(f"- memory log:     {sampler.log_path}")


def apim_base_url() -> str:
    return os.getenv("SMOKE_AI_GATEWAY_BASE_URL", "http://127.0.0.1:8000").rstrip("/")


def sentiment_container_ai_url() -> str:
    parsed = urllib.parse.urlparse(apim_base_url())
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    return f"http://host.docker.internal:{port}/ai/v1/chat/completions"


def model_name() -> str:
    return os.getenv("SENTIMENT_APIM_AI_GATEWAY_MODEL", DEFAULT_MODEL_NAME)


def llamacpp_port() -> int:
    return int(os.getenv("LLAMACPP_PORT", str(DEFAULT_PORT)))


def env_bool(name: str, *, default: bool) -> bool:
    value = os.getenv(name)
    if value is None or value == "":
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def format_bytes(value: int | float) -> str:
    units = ("B", "KiB", "MiB", "GiB")
    amount = float(value)
    for unit in units:
        if amount < 1024 or unit == units[-1]:
            return f"{amount:.1f} {unit}" if unit != "B" else f"{int(amount)} {unit}"
        amount /= 1024
    return f"{amount:.1f} GiB"


def format_kib(value: int | None) -> str:
    if value is None:
        return "unknown"
    return format_bytes(value * 1024)


def tail_log(path: Path, *, lines: int = 80) -> str:
    try:
        content = path.read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return f"log not found: {path}"
    selected = "\n".join(content.splitlines()[-lines:])
    return f"last {lines} log lines from {path}:\n{selected}"


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except LlamaCppGatewayError as exc:
        print(f"llamacpp-ai-gateway: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
