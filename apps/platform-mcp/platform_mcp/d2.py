from __future__ import annotations

import asyncio
import os
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


class D2ExecutionError(Exception):
    def __init__(
        self,
        code: str,
        message: str,
        *,
        recoverable: bool = True,
        data: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.recoverable = recoverable
        self.data = data or {}


@dataclass(frozen=True)
class D2Runner:
    binary: str = "d2"
    max_source_bytes: int = 32_768
    timeout_seconds: float = 5

    @classmethod
    def from_env(cls) -> "D2Runner":
        return cls(
            binary=os.environ.get("D2_BINARY", os.environ.get("D2_BIN", "d2")),
            max_source_bytes=int(os.environ.get("D2_MAX_SOURCE_BYTES", "32768")),
            timeout_seconds=float(os.environ.get("D2_TIMEOUT_SECONDS", "5")),
        )

    async def validate(self, source: str) -> dict[str, Any]:
        await self._render_to_file(source, output_format="svg", layout="elk")
        return {"status": "ok", "source_size": len(source.encode("utf-8"))}

    async def format(self, source: str) -> dict[str, Any]:
        self._validate_source_size(source)
        executable = self._resolve_binary()

        with tempfile.TemporaryDirectory(prefix="platform-mcp-d2-") as tmp:
            source_path = Path(tmp) / "diagram.d2"
            source_path.write_text(source, encoding="utf-8")
            await self._run([executable, "fmt", str(source_path)], stdin=None)
            return {
                "status": "ok",
                "source": source_path.read_text(encoding="utf-8"),
                "source_size": len(source.encode("utf-8")),
            }

    async def render(self, source: str, *, output_format: str = "svg", layout: str = "elk") -> dict[str, Any]:
        output = await self._render_to_file(source, output_format=output_format, layout=layout)
        return {
            "status": "ok",
            "format": output_format,
            "layout": layout,
            "content": output,
            "source_size": len(source.encode("utf-8")),
        }

    async def _render_to_file(self, source: str, *, output_format: str, layout: str) -> str:
        self._validate_source_size(source)
        self._validate_render_options(output_format=output_format, layout=layout)
        executable = self._resolve_binary()

        with tempfile.TemporaryDirectory(prefix="platform-mcp-d2-") as tmp:
            source_path = Path(tmp) / "diagram.d2"
            output_path = Path(tmp) / f"diagram.{output_format}"
            source_path.write_text(source, encoding="utf-8")
            await self._run([executable, "--layout", layout, str(source_path), str(output_path)], stdin=None)
            if not output_path.exists():
                raise D2ExecutionError(
                    "D2_COMMAND_FAILED",
                    "D2 command completed without producing the requested output file.",
                    data={"output_format": output_format, "layout": layout},
                )
            return output_path.read_text(encoding="utf-8")

    def _validate_source_size(self, source: str) -> None:
        size = len(source.encode("utf-8"))
        if size > self.max_source_bytes:
            raise D2ExecutionError(
                "D2_SOURCE_TOO_LARGE",
                f"D2 source is {size} bytes; max allowed is {self.max_source_bytes} bytes.",
                data={"source_size": size, "max_source_bytes": self.max_source_bytes},
            )

    def _validate_render_options(self, *, output_format: str, layout: str) -> None:
        if output_format != "svg":
            raise D2ExecutionError(
                "D2_FORMAT_UNSUPPORTED",
                "Only SVG rendering is enabled for the first platform MCP slice.",
                data={"requested_format": output_format, "supported_formats": ["svg"]},
            )
        if layout not in {"elk", "dagre"}:
            raise D2ExecutionError(
                "D2_LAYOUT_UNSUPPORTED",
                "Unsupported D2 layout engine.",
                data={"requested_layout": layout, "supported_layouts": ["elk", "dagre"]},
            )

    def _resolve_binary(self) -> str:
        resolved = shutil.which(self.binary)
        if resolved:
            return resolved
        if Path(self.binary).is_file() and os.access(self.binary, os.X_OK):
            return self.binary
        raise D2ExecutionError(
            "D2_UNAVAILABLE",
            "D2 binary is not available in this container.",
            data={"binary": self.binary},
        )

    async def _run(self, args: list[str], *, stdin: bytes | None) -> tuple[bytes, bytes]:
        try:
            process = await asyncio.create_subprocess_exec(
                *args,
                stdin=asyncio.subprocess.PIPE if stdin is not None else None,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
        except OSError as exc:
            raise D2ExecutionError(
                "D2_UNAVAILABLE",
                "D2 binary could not be executed.",
                data={"binary": args[0], "exception": type(exc).__name__},
            ) from exc

        try:
            stdout, stderr = await asyncio.wait_for(
                process.communicate(input=stdin),
                timeout=self.timeout_seconds,
            )
        except TimeoutError as exc:
            process.kill()
            await process.wait()
            raise D2ExecutionError(
                "D2_TIMEOUT",
                f"D2 command exceeded {self.timeout_seconds} seconds.",
                data={"timeout_seconds": self.timeout_seconds},
            ) from exc

        if process.returncode != 0:
            raise D2ExecutionError(
                "D2_COMMAND_FAILED",
                "D2 command failed.",
                data={"returncode": process.returncode, "stderr": stderr.decode("utf-8", errors="replace")},
            )

        return stdout, stderr
