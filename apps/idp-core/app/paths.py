from pathlib import Path


_REPO_MARKERS: tuple[tuple[str, ...], ...] = (
    ("catalog", "platform-apps.json"),
    ("scripts", "platform-status.sh"),
    ("terraform", "kubernetes"),
)


def discover_repo_root(start: Path | None = None) -> Path:
    path = (start or Path(__file__)).resolve()
    candidates = path.parents if path.is_file() else (path, *path.parents)

    for candidate in candidates:
        if any((candidate / Path(*marker)).exists() for marker in _REPO_MARKERS):
            return candidate

    return path.parent if path.is_file() else path
