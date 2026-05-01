#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import socket
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


HTML = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Platform Workflow</title>
  <link rel="icon" href="/favicon.ico" sizes="any">
  <style>
    :root {
      color-scheme: light;
      --ink: #18201c;
      --muted: #637069;
      --paper: #f7f3ea;
      --panel: #fffdfa;
      --line: #c9d5cb;
      --accent: #0f766e;
      --accent-strong: #0b4f4a;
      --warn: #9f3a1f;
      --code: #10231f;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: ui-sans-serif, "Avenir Next", "Segoe UI", sans-serif;
      color: var(--ink);
      background:
        linear-gradient(90deg, rgba(24,32,28,.055) 1px, transparent 1px),
        linear-gradient(rgba(24,32,28,.055) 1px, transparent 1px),
        var(--paper);
      background-size: 28px 28px;
    }
    main {
      width: min(1180px, calc(100vw - 32px));
      margin: 0 auto;
      padding: 28px 0;
    }
    header {
      display: flex;
      justify-content: space-between;
      gap: 24px;
      align-items: end;
      border-bottom: 2px solid var(--ink);
      padding-bottom: 18px;
      margin-bottom: 22px;
    }
    h1 {
      margin: 0;
      font-family: Georgia, "Times New Roman", serif;
      font-size: clamp(2rem, 5vw, 4.7rem);
      line-height: .9;
      letter-spacing: 0;
    }
    .status {
      min-width: 220px;
      padding: 10px 12px;
      border: 1px solid var(--line);
      background: var(--panel);
      font-family: ui-monospace, "SFMono-Regular", Menlo, monospace;
      font-size: .85rem;
    }
    .layout {
      display: grid;
      grid-template-columns: minmax(320px, 440px) 1fr;
      gap: 22px;
      align-items: start;
    }
    section {
      background: var(--panel);
      border: 1px solid var(--line);
      box-shadow: 0 10px 0 rgba(24,32,28,.1);
    }
    .form { padding: 18px; }
    .preview { padding: 18px; min-height: 420px; }
    .instructions {
      margin: 0 0 16px;
      color: var(--muted);
      font-size: .95rem;
      line-height: 1.45;
    }
    label {
      display: grid;
      gap: 6px;
      margin-bottom: 14px;
      color: var(--muted);
      font-size: .78rem;
      font-weight: 700;
      text-transform: uppercase;
    }
    select, button {
      width: 100%;
      min-height: 42px;
      border: 1px solid var(--ink);
      background: #fff;
      color: var(--ink);
      font: inherit;
      padding: 8px 10px;
    }
    button {
      cursor: pointer;
      background: var(--accent);
      color: white;
      font-weight: 800;
      border-color: var(--accent-strong);
    }
    button:hover { background: var(--accent-strong); }
    .grid2 {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
    }
    .summary {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 10px;
      margin-bottom: 18px;
    }
    .metric {
      border: 1px solid var(--line);
      padding: 10px;
      background: #fbfaf4;
      min-height: 68px;
    }
    .metric span {
      display: block;
      color: var(--muted);
      font-size: .72rem;
      text-transform: uppercase;
      font-weight: 800;
    }
    .metric strong {
      display: block;
      margin-top: 7px;
      overflow-wrap: anywhere;
    }
    .command-head {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 12px;
      margin-bottom: 8px;
    }
    .command-head h2 {
      margin: 0;
      font-size: .78rem;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0;
    }
    .copy-button {
      width: auto;
      min-height: 34px;
      padding: 6px 12px;
      font-size: .85rem;
    }
    pre {
      margin: 0;
      padding: 14px;
      background: var(--code);
      color: #e5fff7;
      white-space: pre-wrap;
      overflow-wrap: anywhere;
      min-height: 168px;
      font-size: .88rem;
      line-height: 1.45;
    }
    .error { color: var(--warn); font-weight: 800; }
    @media (max-width: 850px) {
      header, .layout, .summary, .grid2 { grid-template-columns: 1fr; display: grid; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>Platform<br>Workflow</h1>
      <div class="status" id="status">loading options</div>
    </header>
    <div class="layout">
      <section class="form" aria-label="Workflow choices">
        <p class="instructions">
          Choose the target, stage, action, and app toggles. This page generates the Make command to run in a terminal; it does not apply changes from the browser.
        </p>
        <label>Target
          <select id="target"></select>
        </label>
        <label>Stage
          <select id="stage"></select>
        </label>
        <label>Action
          <select id="action"></select>
        </label>
        <div class="grid2">
          <label>Sentiment
            <select id="sentiment"></select>
          </label>
          <label>Subnetcalc
            <select id="subnetcalc"></select>
          </label>
        </div>
        <button id="preview" type="button">Generate Terminal Command</button>
      </section>
      <section class="preview" aria-live="polite">
        <div class="summary">
          <div class="metric"><span>Target</span><strong id="m-target">-</strong></div>
          <div class="metric"><span>Stage</span><strong id="m-stage">-</strong></div>
          <div class="metric"><span>Action</span><strong id="m-action">-</strong></div>
        </div>
        <div class="command-head">
          <h2>Terminal Command</h2>
          <button class="copy-button" id="copy-command" type="button">Copy</button>
        </div>
        <pre id="command">Select options to generate the exact command.</pre>
      </section>
    </div>
  </main>
  <script>
    const $ = (id) => document.getElementById(id);
    const controls = ["target", "stage", "action", "sentiment", "subnetcalc"].map($);
    const commandPlaceholder = "Select options to generate the exact command.";

    function setOptions(select, values, render) {
      select.innerHTML = "";
      values.forEach((value) => {
        const option = document.createElement("option");
        const rendered = render ? render(value) : { value, label: value };
        option.value = rendered.value;
        option.textContent = rendered.label;
        select.append(option);
      });
    }

    function appStageDefault(stage, app) {
      if (stage === "950-local-idp") {
        return app === "sentiment";
      }
      return ["700", "800", "900"].includes(stage);
    }

    function updateAppToggleOptions() {
      const stage = $("stage").value;
      ["sentiment", "subnetcalc"].forEach((app) => {
        const select = $(app);
        const previous = select.value;
        const enabledByDefault = appStageDefault(stage, app);
        setOptions(select, [
          {
            value: "",
            label: `${enabledByDefault ? "Enable" : "Disable"} (stage default)`
          },
          {
            value: enabledByDefault ? "off" : "on",
            label: enabledByDefault ? "Disable" : "Enable"
          }
        ], (option) => option);
        select.value = [...select.options].some((option) => option.value === previous) ? previous : "";
      });
    }

    async function loadOptions() {
      const response = await fetch("/api/options");
      const options = await response.json();
      setOptions($("target"), options.targets);
      setOptions($("stage"), options.stages, (stage) => ({ value: stage.id, label: `${stage.id} ${stage.label}` }));
      setOptions($("action"), options.actions);
      $("stage").value = "900";
      $("action").value = "apply";
      $("target").value = "kind";
      updateAppToggleOptions();
      $("sentiment").value = "off";
      $("status").textContent = "command current";
      await preview();
    }

    async function preview() {
      $("status").textContent = "generating command";
      $("command").textContent = "Loading...";
      const payload = {
        target: $("target").value,
        stage: $("stage").value,
        action: $("action").value,
        sentiment: $("sentiment").value,
        subnetcalc: $("subnetcalc").value,
        auto_approve: $("action").value === "apply"
      };
      const response = await fetch("/api/preview", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(payload)
      });
      const result = await response.json();
      if (!response.ok) {
        $("status").textContent = "error";
        $("command").innerHTML = `<span class="error">${result.error || "Preview failed"}</span>`;
        return;
      }
      $("m-target").textContent = result.target;
      $("m-stage").textContent = result.stage;
      $("m-action").textContent = result.action;
      $("command").textContent = result.command;
      $("status").textContent = "command current";
    }

    async function copyCommand() {
      const command = $("command").textContent.trim();
      if (!command || command === commandPlaceholder || command === "Loading...") {
        $("status").textContent = "nothing to copy";
        return;
      }
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(command);
      } else {
        const textarea = document.createElement("textarea");
        textarea.value = command;
        textarea.setAttribute("readonly", "");
        textarea.style.position = "fixed";
        textarea.style.left = "-9999px";
        document.body.append(textarea);
        textarea.select();
        document.execCommand("copy");
        textarea.remove();
      }
      $("status").textContent = "copied command";
    }

    $("preview").addEventListener("click", preview);
    $("copy-command").addEventListener("click", () => {
      copyCommand().catch((error) => {
        $("status").textContent = "copy failed";
        $("command").textContent = error.message;
      });
    });
    $("stage").addEventListener("change", updateAppToggleOptions);
    controls.forEach((control) => control.addEventListener("change", preview));
    loadOptions().catch((error) => {
      $("status").textContent = "error";
      $("command").textContent = error.message;
    });
  </script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    repo_root: Path

    def log_message(self, format: str, *args: Any) -> None:
        return

    def write_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, indent=2).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path == "/health":
            self.write_json(200, {"status": "ok"})
            return
        if self.path == "/api/options":
            self.run_workflow(["options", "--execute", "--output", "json"])
            return
        if self.path == "/favicon.ico":
            favicon_path = self.repo_root / "sites" / "docs" / "app" / "favicon.ico"
            if not favicon_path.is_file():
                self.write_json(404, {"error": "favicon not found"})
                return
            body = favicon_path.read_bytes()
            self.send_response(200)
            self.send_header("content-type", "image/x-icon")
            self.send_header("cache-control", "public, max-age=3600")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path == "/" or self.path == "/index.html":
            body = HTML.encode()
            self.send_response(200)
            self.send_header("content-type", "text/html; charset=utf-8")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.write_json(404, {"error": "not found"})

    def do_POST(self) -> None:
        if self.path != "/api/preview":
            self.write_json(404, {"error": "not found"})
            return

        length = int(self.headers.get("content-length", "0"))
        payload = json.loads(self.rfile.read(length) or b"{}")
        args = [
            "preview",
            "--execute",
            "--output",
            "json",
            "--target",
            str(payload.get("target") or "kind"),
            "--stage",
            str(payload.get("stage") or "900"),
            "--action",
            str(payload.get("action") or "apply"),
        ]
        for app in ("sentiment", "subnetcalc"):
            value = payload.get(app)
            if value:
                args.extend(["--app", f"{app}={value}"])
        if payload.get("auto_approve"):
            args.append("--auto-approve")
        self.run_workflow(args)

    def run_workflow(self, args: list[str]) -> None:
        command = [str(self.repo_root / "scripts" / "platform-workflow.sh"), *args]
        result = subprocess.run(command, cwd=self.repo_root, text=True, capture_output=True, check=False)
        if result.returncode != 0:
            self.write_json(400, {"error": result.stderr.strip() or result.stdout.strip()})
            return
        self.send_response(200)
        body = result.stdout.encode()
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class LocalThreadingHTTPServer(ThreadingHTTPServer):
    def server_bind(self) -> None:
        if self.allow_reuse_address and hasattr(socket, "SO_REUSEADDR"):
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.socket.bind(self.server_address)
        self.server_name = str(self.server_address[0])
        self.server_port = int(self.server_address[1])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--repo-root", required=True)
    args = parser.parse_args()

    Handler.repo_root = Path(args.repo_root)
    server = LocalThreadingHTTPServer((args.host, args.port), Handler)
    print(f"platform workflow UI listening on http://{args.host}:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
