# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Because the project is pure configuration, a version bump means "these files were
tested against this OpenCode build" rather than a runtime dependency change.

## [Unreleased]

## [1.0.0] - 2026-10-19

First public release. Verified on **OpenCode Desktop 1.19.3 (Windows)**.

### Added

- Three primary agents, implemented only with the native `permission` config:
  - `read-only` — reads and searches, never edits, never runs commands.
  - `auto-edit` — edits files freely, asks before commands and network access.
  - `full-auto` — everything allowed, no prompts.
- `install.ps1` (Windows) and `install.sh` (macOS/Linux): copy the agent files,
  back up anything they would overwrite, and never touch an existing
  `opencode.json` / `opencode.jsonc`.
- `uninstall.ps1` / `uninstall.sh`: restore the backups recorded at install time,
  or remove the files if they were installed into a clean config directory.
- `examples/opencode.jsonc`: optional `default_agent` plus disabling the built-in
  `build` / `plan` agents.
- `docs/how-it-works.md`: evaluation order, permission schema, and why this is a
  set of agents rather than a plugin.
- `docs/faq.md`: the usual papercuts (keybindings, IME conflicts, `"*": deny`
  ordering, restart requirements).
- `presets/hardened-full-auto.md`: optional `full-auto` variant that denies
  force-push, `rm -rf`, `git reset --hard` and `git clean -f`.
- CI on Ubuntu, macOS and Windows that validates the permission schema, parses
  the frontmatter with a real YAML parser, checks README links, and runs an
  install / reinstall / uninstall round-trip.

[Unreleased]: https://github.com/jeeleonard9-art/opencode-permission-modes/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/jeeleonard9-art/opencode-permission-modes/releases/tag/v1.0.0
