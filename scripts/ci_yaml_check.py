#!/usr/bin/env python3
"""CI-only: parse the frontmatter and GitHub config files with real YAML.

scripts/validate_config.py uses a small built-in parser so users can run it with
nothing but a stock Python. This script is the second opinion: it runs only in
CI (PyYAML is installed there) and catches YAML syntax the subset parser would
reject or silently misread. It also parses every file under .github/, so a
broken issue form or workflow is caught before merge.
"""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
FORM_TYPES = {"markdown", "input", "textarea", "dropdown", "checkboxes"}


def split_frontmatter(text: str, path: Path) -> str:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise ValueError(f"{path}: file must start with '---'")
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return "\n".join(lines[1:index])
    raise ValueError(f"{path}: missing closing '---'")


def check_frontmatter() -> tuple[int, int]:
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
    return len(files) - failures, len(files)


def check_github_yaml() -> tuple[int, int]:
    gh_dir = ROOT / ".github"
    files = sorted(gh_dir.rglob("*.yml")) if gh_dir.is_dir() else []
    failures = 0

    for path in files:
        rel = path.relative_to(ROOT).as_posix()
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            print(f"FAIL {rel}: {exc}")
            failures += 1
            continue

        if not isinstance(data, dict):
            print(f"FAIL {rel}: top-level YAML is not a mapping")
            failures += 1
            continue

        is_issue_form = path.parent.name == "ISSUE_TEMPLATE" and path.name != "config.yml"
        if is_issue_form:
            problems = []
            if not isinstance(data.get("name"), str) or not data.get("name"):
                problems.append("missing or empty 'name'")
            if not isinstance(data.get("description"), str) or not data.get("description"):
                problems.append("missing or empty 'description'")
            if "labels" in data and (
                not isinstance(data["labels"], list)
                or not all(isinstance(x, str) for x in data["labels"])
            ):
                problems.append("'labels' must be a list of strings")

            seen_ids = set()
            body = data.get("body")
            if not isinstance(body, list) or not body:
                problems.append("'body' must be a non-empty list")
            else:
                for index, item in enumerate(body):
                    if not isinstance(item, dict):
                        problems.append(f"body[{index}] is not a mapping")
                        continue
                    item_type = item.get("type")
                    if item_type not in FORM_TYPES:
                        problems.append(f"body[{index}].type is invalid: {item_type!r}")
                        continue
                    if item_type == "markdown":
                        continue
                    item_id = item.get("id")
                    if not isinstance(item_id, str) or not item_id:
                        problems.append(f"body[{index}] is missing 'id'")
                    elif item_id in seen_ids:
                        problems.append(f"body[{index}] duplicates id {item_id!r}")
                    else:
                        seen_ids.add(item_id)

                    attributes = item.get("attributes")
                    if not isinstance(attributes, dict) or not isinstance(attributes.get("label"), str):
                        problems.append(f"body[{index}] is missing attributes.label")
                        attributes = {}

                    validations = item.get("validations")
                    if validations is not None and (
                        not isinstance(validations, dict)
                        or not isinstance(validations.get("required", False), bool)
                    ):
                        problems.append(f"body[{index}].validations must be a mapping with boolean 'required'")

                    if item_type == "dropdown":
                        options = attributes.get("options")
                        if not isinstance(options, list) or not options:
                            problems.append(f"body[{index}] dropdown needs a non-empty 'options' list")
                        elif not all(isinstance(x, str) for x in options):
                            problems.append(f"body[{index}] dropdown options must be strings")

                    if item_type == "checkboxes":
                        options = attributes.get("options")
                        if not isinstance(options, list) or not options:
                            problems.append(f"body[{index}] checkboxes need a non-empty 'options' list")
                        else:
                            for j, option in enumerate(options):
                                if not isinstance(option, dict) or not isinstance(option.get("label"), str):
                                    problems.append(f"body[{index}].options[{j}] needs a 'label'")
            if problems:
                for problem in problems:
                    print(f"FAIL {rel}: {problem}")
                failures += 1
                continue
        elif path.name == "config.yml" and path.parent.name == "ISSUE_TEMPLATE":
            problems = []
            if not isinstance(data.get("blank_issues_enabled"), bool):
                problems.append("'blank_issues_enabled' must be true or false")
            links = data.get("contact_links")
            if not isinstance(links, list):
                problems.append("'contact_links' must be a list")
            else:
                for index, link in enumerate(links):
                    for key in ("name", "url", "about"):
                        if not isinstance(link, dict) or not isinstance(link.get(key), str):
                            problems.append(f"contact_links[{index}] needs a string '{key}'")
            if problems:
                for problem in problems:
                    print(f"FAIL {rel}: {problem}")
                failures += 1
                continue

        print(f"OK   {rel}")

    return len(files) - failures, len(files)


def main() -> int:
    fm_ok, fm_total = check_frontmatter()
    gh_ok, gh_total = check_github_yaml()
    print(f"\nfrontmatter: {fm_ok}/{fm_total} parsed, .github: {gh_ok}/{gh_total} parsed.")
    return 0 if fm_ok == fm_total and gh_ok == gh_total else 1


if __name__ == "__main__":
    sys.exit(main())
