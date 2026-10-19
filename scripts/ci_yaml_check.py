#!/usr/bin/env python3
"""CI-only: parse every agent/preset frontmatter with a real YAML parser.

scripts/validate_config.py uses a small built-in parser so users can run it with
nothing but a stock Python. This script is the second opinion: it runs only in
CI (PyYAML is installed there) and catches YAML syntax the subset parser would
reject or silently misread.
"""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent


def split_frontmatter(text: str, path: Path) -> str:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise ValueError(f"{path}: file must start with '---'")
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return "\n".join(lines[1:index])
    raise ValueError(f"{path}: missing closing '---'")


def main() -> int:
    files = sorted((ROOT / "agent").glob("*.md"))
    preset_dir = ROOT / "presets"
    if preset_dir.is_dir():
        files += sorted(preset_dir.glob("*.md"))

    failures = 0
    for path in files:
        rel = path.relative_to(ROOT).as_posix()
        try:
            data = yaml.safe_load(split_frontmatter(path.read_text(encoding="utf-8"), path))
        except Exception as exc:  # noqa: BLE001 - report and continue
            print(f"::{('error' if _in_ci() else 'warning')} file={rel}::{exc}")
            print(f"FAIL {rel}: {exc}")
            failures += 1
            continue
        if not isinstance(data, dict):
            print(f"FAIL {rel}: frontmatter is not a mapping")
            failures += 1
            continue
        missing = [k for k in ("description", "mode", "permission") if k not in data]
        if missing:
            print(f"FAIL {rel}: missing keys: {', '.join(missing)}")
            failures += 1
            continue
        print(f"OK   {rel}")

    print(f"\n{len(files) - failures}/{len(files)} frontmatter block(s) parsed as YAML.")
    return 1 if failures else 0


def _in_ci() -> bool:
    import os

    return bool(os.environ.get("GITHUB_ACTIONS"))


if __name__ == "__main__":
    sys.exit(main())
