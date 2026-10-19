#!/usr/bin/env python3
"""Validate this repository's configuration files.

Checks:
  1. agent/*.md and presets/*.md have a well-formed YAML frontmatter
     (parsed by a small built-in parser, so no pip install is needed).
  2. Every `permission` key and value is one OpenCode actually accepts.
  3. examples/opencode.jsonc is valid JSONC.
  4. Relative links in README.md / README_EN.md point at files that exist.

Standard library only. CI additionally runs scripts/ci_yaml_check.py, which uses
PyYAML to catch YAML syntax this subset parser would reject or misread.

Usage:
    python scripts/validate_config.py
Exit code 0 when everything passes, 1 otherwise.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AGENT_DIR = ROOT / "agent"
PRESET_DIR = ROOT / "presets"
EXAMPLE_CONFIG = ROOT / "examples" / "opencode.jsonc"
READMES = (ROOT / "README.md", ROOT / "README_EN.md")
EXTRA_DOCS = (ROOT / "CONTRIBUTING.md",)

ACTIONS = {"allow", "ask", "deny"}

# Keys accepted inside `permission`. Keep in sync with the OpenCode config schema.
KNOWN_TOOLS = {
    "read",
    "edit",
    "glob",
    "grep",
    "list",
    "bash",
    "task",
    "external_directory",
    "todowrite",
    "question",
    "webfetch",
    "websearch",
    "lsp",
    "skill",
    "doom_loop",
}

COLOR_RE = re.compile(r"^#[0-9a-fA-F]{6}$")
LINK_RE = re.compile(r"!?\[[^\]]*\]\(\s*(<[^>]+>|[^)\s]+)(?:\s+\"[^\"]*\")?\s*\)")

errors: list[tuple[str, int | None, str]] = []
warnings: list[tuple[str, int | None, str]] = []


def fail(path: Path, message: str, line: int | None = None) -> None:
    errors.append((str(path.relative_to(ROOT)), line, message))


def warn(path: Path, message: str, line: int | None = None) -> None:
    warnings.append((str(path.relative_to(ROOT)), line, message))


# --------------------------------------------------------------------------
# A deliberately small YAML subset parser: nested mappings, quoted/plain
# scalars, flow mappings, comments. No lists, anchors, or block scalars -
# frontmatter for these agents never needs them.
# --------------------------------------------------------------------------


class YamlError(ValueError):
    def __init__(self, message: str, line: int | None = None) -> None:
        super().__init__(message)
        self.line = line


def _strip_comment(line: str) -> str:
    quote = None
    out: list[str] = []
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            out.append(ch)
            if ch == "\\" and quote == '"':
                if i + 1 < len(line):
                    out.append(line[i + 1])
                    i += 2
                    continue
            elif ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            out.append(ch)
        elif ch == "#" and (i == 0 or line[i - 1] in " \t"):
            break
        else:
            out.append(ch)
        i += 1
    return "".join(out).rstrip()


def _split_key(text: str) -> tuple[str, bool, str]:
    quote = None
    i = 0
    while i < len(text):
        ch = text[i]
        if quote:
            if ch == "\\" and quote == '"':
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == ":":
            return text[:i].strip(), True, text[i + 1 :].strip()
        i += 1
    return text.strip(), False, ""


def _unescape_double(body: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(body):
        ch = body[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue
        i += 1
        if i >= len(body):
            raise YamlError("trailing backslash in quoted string")
        esc = body[i]
        simple = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\", "/": "/", "0": "\0"}
        if esc in simple:
            out.append(simple[esc])
            i += 1
        elif esc == "u":
            digits = body[i + 1 : i + 5]
            if not re.fullmatch(r"[0-9a-fA-F]{4}", digits):
                raise YamlError("bad \\u escape in quoted string")
            out.append(chr(int(digits, 16)))
            i += 5
        else:
            raise YamlError(f"unsupported escape: \\{esc}")
    return "".join(out)


def _split_flow(body: str) -> list[str]:
    parts: list[str] = []
    quote = None
    depth = 0
    buf: list[str] = []
    for ch in body:
        if quote:
            buf.append(ch)
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            buf.append(ch)
        elif ch in "{[":
            depth += 1
            buf.append(ch)
        elif ch in "}]":
            depth -= 1
            buf.append(ch)
        elif ch == "," and depth == 0:
            parts.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    parts.append("".join(buf))
    return [p.strip() for p in parts if p.strip()]


def _parse_scalar(text: str, lineno: int):
    t = text.strip()
    if not t:
        return None
    if t[0] == '"':
        if len(t) < 2 or not t.endswith('"'):
            raise YamlError("unterminated double-quoted string", lineno)
        return _unescape_double(t[1:-1])
    if t[0] == "'":
        if len(t) < 2 or not t.endswith("'"):
            raise YamlError("unterminated single-quoted string", lineno)
        return t[1:-1].replace("''", "'")
    if t[0] == "{":
        if not t.endswith("}"):
            raise YamlError("unterminated flow mapping", lineno)
        result = {}
        for part in _split_flow(t[1:-1]):
            key, has, rest = _split_key(part)
            if not has:
                raise YamlError(f"expected 'key: value' in flow mapping, got {part!r}", lineno)
            key = key.strip("\"'")
            if key in result:
                raise YamlError(f"duplicate key {key!r}", lineno)
            result[key] = _parse_scalar(rest, lineno)
        return result
    if t[0] == "[":
        raise YamlError("YAML lists are not supported in frontmatter", lineno)
    lowered = t.lower()
    if lowered in {"true", "false"}:
        return lowered == "true"
    if lowered in {"null", "~"}:
        return None
    return t


def _parse_block(entries, index: int, indent: int) -> tuple[dict, int]:
    result: dict = {}
    while index < len(entries):
        cur_indent, text, lineno = entries[index]
        if cur_indent < indent:
            break
        if cur_indent > indent:
            raise YamlError("unexpected indentation", lineno)
        if text.startswith("- "):
            raise YamlError("YAML lists are not supported in frontmatter", lineno)
        key, has_sep, rest = _split_key(text)
        if not has_sep:
            raise YamlError(f"expected 'key: value', got {text!r}", lineno)
        if not key:
            raise YamlError("empty key", lineno)
        if key[0] in "\"'":
            if len(key) < 2 or key[-1] != key[0]:
                raise YamlError("unterminated quoted key", lineno)
            key = key[1:-1]
        if key in result:
            raise YamlError(f"duplicate key {key!r}", lineno)
        index += 1
        if rest == "":
            if index < len(entries) and entries[index][0] > indent:
                value, index = _parse_block(entries, index, entries[index][0])
            else:
                value = None
        else:
            value = _parse_scalar(rest, lineno)
        result[key] = value
    return result, index


def parse_frontmatter(path: Path) -> tuple[dict, str]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise YamlError("file must start with a '---' line", 1)
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        raise YamlError("missing closing '---' line", 1)
    body = "\n".join(lines[end + 1 :]).strip()

    entries = []
    for offset, line in enumerate(lines[1:end], start=2):
        if not line.strip():
            continue
        cleaned = _strip_comment(line)
        if not cleaned.strip():
            continue
        lead = cleaned[: len(cleaned) - len(cleaned.lstrip())]
        if "\t" in lead:
            raise YamlError("tab indentation is not allowed, use spaces", offset)
        entries.append((len(lead), cleaned.strip(), offset))
    if not entries:
        raise YamlError("frontmatter is empty", 2)
    data, consumed = _parse_block(entries, 0, entries[0][0])
    if consumed != len(entries):
        raise YamlError("could not parse the whole frontmatter block", entries[consumed][2])
    return data, body


# --------------------------------------------------------------------------
# Semantic checks
# --------------------------------------------------------------------------


def check_permission(path: Path, perm, lineno: int | None = None) -> None:
    if not isinstance(perm, dict) or not perm:
        fail(path, "'permission' must be a non-empty mapping", lineno)
        return
    for key, value in perm.items():
        if key != "*" and key not in KNOWN_TOOLS:
            hint = ""
            close = [t for t in KNOWN_TOOLS if t.startswith(key)]
            if close:
                hint = f" (did you mean {', '.join(sorted(close))}?)"
            fail(path, f"unknown permission key {key!r}{hint}", lineno)
            continue
        if isinstance(value, str):
            if value not in ACTIONS:
                fail(path, f"permission {key!r} must be one of allow/ask/deny, got {value!r}", lineno)
        elif isinstance(value, dict):
            if not value:
                fail(path, f"permission {key!r} is an empty glob map", lineno)
            for pattern, action in value.items():
                if not isinstance(action, str) or action not in ACTIONS:
                    fail(
                        path,
                        f"permission {key!r}[{pattern!r}] must be one of allow/ask/deny, "
                        f"got {action!r}",
                        lineno,
                    )
        else:
            fail(path, f"permission {key!r} must be an action or a glob mapping", lineno)


def check_agent_file(path: Path) -> None:
    try:
        data, body = parse_frontmatter(path)
    except YamlError as exc:
        fail(path, f"frontmatter: {exc}", getattr(exc, "line", None))
        return
    except UnicodeDecodeError:
        fail(path, "file is not valid UTF-8")
        return

    for required in ("description", "mode", "permission"):
        if required not in data:
            fail(path, f"missing required frontmatter key {required!r}")
    if not isinstance(data.get("description"), str) or not str(data.get("description", "")).strip():
        fail(path, "'description' must be a non-empty string")
    mode = data.get("mode")
    if mode not in {"primary", "all", "subagent"}:
        fail(path, f"'mode' must be primary/all/subagent, got {mode!r}")
    elif mode != "primary":
        fail(path, f"'{path.name}' should use mode: primary so it shows up in the agent picker")
    color = data.get("color")
    if color is not None and (not isinstance(color, str) or not COLOR_RE.match(color)):
        fail(path, f"'color' must look like #rrggbb, got {color!r}")
    if not body:
        fail(path, "agent file has no prompt body")
    perm = data.get("permission")
    check_permission(path, perm)
    if isinstance(perm, dict) and perm.get("question") != "allow":
        fail(path, "custom agents default to question: deny - set 'question: allow' explicitly")


def check_example_config(path: Path) -> None:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        fail(path, "file is not valid UTF-8")
        return
    if text.startswith("\ufeff"):
        text = text[1:]
    try:
        data = json.loads(strip_jsonc(text))
    except json.JSONDecodeError as exc:
        fail(path, f"invalid JSONC: {exc.msg} at line {exc.lineno} column {exc.colno}")
        return
    if not isinstance(data, dict):
        fail(path, "top-level value must be an object")
        return
    if data.get("default_agent") != "auto-edit":
        warn(path, f"default_agent is {data.get('default_agent')!r}, expected 'auto-edit'")
    agents = data.get("agent")
    if not isinstance(agents, dict):
        fail(path, "'agent' must be an object")
        return
    for builtin in ("build", "plan"):
        entry = agents.get(builtin)
        if not isinstance(entry, dict) or entry.get("disable") is not True:
            warn(path, f"agent.{builtin}.disable is not true in the example")


def strip_jsonc(text: str) -> str:
    """Remove // and /* */ comments plus trailing commas, preserving strings."""
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            out.append(ch)
            i += 1
            while i < n:
                out.append(text[i])
                if text[i] == "\\" and i + 1 < n:
                    out.append(text[i + 1])
                    i += 2
                    continue
                if text[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        if ch == ",":
            j = i + 1
            while j < n and text[j] in " \t\r\n":
                j += 1
            if j < n and text[j] in "}]":
                i += 1
                continue
        out.append(ch)
        i += 1
    return "".join(out)


def check_readme_links(path: Path) -> set[str]:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        fail(path, "file is not valid UTF-8")
        return set()
    targets: set[str] = set()
    for match in LINK_RE.finditer(text):
        raw = match.group(1)
        if raw.startswith("<") and raw.endswith(">"):
            raw = raw[1:-1]
        if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", raw) or raw.startswith("#"):
            continue
        target = raw.split("#", 1)[0].split("?", 1)[0]
        if not target:
            continue
        target = target.replace("%20", " ")
        targets.add(target)
        if not (ROOT / target).exists():
            fail(path, f"broken relative link: {raw}")
    return targets


def main() -> int:
    agent_files = sorted(AGENT_DIR.glob("*.md"))
    preset_files = sorted(PRESET_DIR.glob("*.md")) if PRESET_DIR.is_dir() else []

    if not agent_files:
        fail(AGENT_DIR, "no agent definitions found")

    for path in agent_files + preset_files:
        check_agent_file(path)

    if not EXAMPLE_CONFIG.is_file():
        fail(EXAMPLE_CONFIG, "example config is missing")
    else:
        check_example_config(EXAMPLE_CONFIG)

    link_sets = {}
    for readme in READMES:
        if not readme.is_file():
            fail(readme, "README is missing")
            continue
        link_sets[readme.name] = check_readme_links(readme)

    for doc in EXTRA_DOCS:
        if doc.is_file():
            check_readme_links(doc)
    if len(link_sets) == 2:
        # The language switcher at the top points at the other README, so drop
        # those two targets before comparing.
        switcher = {"README.md", "README_EN.md"}
        zh = link_sets["README.md"] - switcher
        en = link_sets["README_EN.md"] - switcher
        if zh != en:
            only_zh = sorted(zh - en)
            only_en = sorted(en - zh)
            warn(
                ROOT / "README.md",
                f"README link sets differ (zh only: {only_zh or '-'}; en only: {only_en or '-'})",
            )

    for rel, line, msg in errors:
        prefix = f"{rel}:{line}: " if line else f"{rel}: "
        if os.environ.get("GITHUB_ACTIONS"):
            print(f"::error file={rel},line={line or 1}::{msg}")
        print(f"ERROR {prefix}{msg}")
    for rel, line, msg in warnings:
        prefix = f"{rel}:{line}: " if line else f"{rel}: "
        if os.environ.get("GITHUB_ACTIONS"):
            print(f"::warning file={rel},line={line or 1}::{msg}")
        print(f"WARN  {prefix}{msg}")

    checked = len(agent_files) + len(preset_files) + 1 + len(link_sets)
    if errors:
        print(f"\nFAILED: {len(errors)} error(s), {len(warnings)} warning(s).")
        return 1
    print(
        f"OK: {len(agent_files)} agent file(s), {len(preset_files)} preset(s), "
        f"1 example config, {len(link_sets)} README(s) checked, {len(warnings)} warning(s)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
