#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import stat
import subprocess
import tomllib
import zipfile
from pathlib import Path

RUNTIME_INCLUDE_PATHS = (
    ".dockerignore",
    "catalog-info.yaml",
    "Dockerfile",
    "LICENSE.md",
    "app",
    "contracts",
    "pyproject.toml",
    "uv.lock",
)

DOCKERFILE_LINES_TO_DROP = ("COPY --chown=${APP_UID}:${APP_GID} examples ./examples",)

ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build the narrow runtime source zip used by downstream container builders.",
    )
    parser.add_argument(
        "--source-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Repository root to package.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help="Directory for the zip and checksum. Defaults to SOURCE_ROOT/dist.",
    )
    parser.add_argument(
        "--name",
        default=None,
        help="Zip file name. Defaults to apim-simulator-runtime-vVERSION.zip.",
    )
    parser.add_argument(
        "--version",
        default=None,
        help="Version string to use in the default zip name. Defaults to pyproject.toml.",
    )
    return parser.parse_args()


def project_version(source_root: Path) -> str:
    with (source_root / "pyproject.toml").open("rb") as handle:
        return str(tomllib.load(handle)["project"]["version"])


def tracked_runtime_files(source_root: Path) -> list[Path]:
    for include_path in RUNTIME_INCLUDE_PATHS:
        if not (source_root / include_path).exists():
            raise SystemExit(f"runtime artifact input is missing: {include_path}")

    result = subprocess.run(
        ["git", "-C", str(source_root), "ls-files", "-z", "--", *RUNTIME_INCLUDE_PATHS],
        check=True,
        stdout=subprocess.PIPE,
    )
    files = {Path(item.decode()) for item in result.stdout.split(b"\0") if item}
    for include_path in RUNTIME_INCLUDE_PATHS:
        path = Path(include_path)
        if (source_root / path).is_file():
            files.add(path)
        elif (source_root / path).is_dir():
            files.update(
                child.relative_to(source_root)
                for child in (source_root / path).rglob("*")
                if child.is_file()
            )
    return sorted(files)


def patched_file_bytes(source_root: Path, relative_path: Path) -> bytes:
    data = (source_root / relative_path).read_bytes()
    if relative_path.as_posix() != "Dockerfile":
        return data

    lines = data.decode("utf-8").splitlines()
    patched = [line for line in lines if not any(drop_line in line for drop_line in DOCKERFILE_LINES_TO_DROP)]
    return ("\n".join(patched) + "\n").encode("utf-8")


def zip_mode(source_root: Path, relative_path: Path) -> int:
    mode = stat.S_IMODE((source_root / relative_path).stat().st_mode)
    if mode & stat.S_IXUSR:
        return 0o755
    return 0o644


def write_zip(source_root: Path, output_path: Path) -> None:
    files = tracked_runtime_files(source_root)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for relative_path in files:
            info = zipfile.ZipInfo(relative_path.as_posix())
            info.date_time = ZIP_TIMESTAMP
            info.external_attr = zip_mode(source_root, relative_path) << 16
            archive.writestr(info, patched_file_bytes(source_root, relative_path))


def write_checksum(zip_path: Path) -> tuple[Path, str]:
    digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    checksum_path = zip_path.with_name(f"{zip_path.name}.sha256")
    checksum_path.write_text(f"{digest}  {zip_path.name}\n", encoding="utf-8")
    return checksum_path, digest


def main() -> None:
    args = parse_args()
    source_root = args.source_root.resolve()
    version = args.version or project_version(source_root)
    output_dir = (args.output_dir or source_root / "dist").resolve()
    artifact_name = args.name or f"apim-simulator-runtime-v{version}.zip"
    zip_path = output_dir / artifact_name

    write_zip(source_root, zip_path)
    checksum_path, digest = write_checksum(zip_path)

    print(f"Wrote {zip_path}")
    print(f"Wrote {checksum_path}")
    print(f"sha256 {digest}")


if __name__ == "__main__":
    main()
