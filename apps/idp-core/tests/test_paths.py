from pathlib import Path

from app.paths import discover_repo_root


def test_repo_root_discovery_handles_container_image_layout(tmp_path: Path) -> None:
    image_root = tmp_path / "app"
    package_dir = image_root / "app"
    package_dir.mkdir(parents=True)
    source_file = package_dir / "adapters.py"
    source_file.write_text("# fixture\n", encoding="utf-8")
    catalog_dir = image_root / "catalog"
    catalog_dir.mkdir()
    (catalog_dir / "platform-apps.json").write_text('{"applications":[]}\n', encoding="utf-8")

    assert discover_repo_root(source_file) == image_root
