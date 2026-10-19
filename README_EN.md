# OpenCode Permission Modes

> Codex-style permission levels for [OpenCode](https://opencode.ai): **read-only / auto-edit / full-auto**. One keystroke to switch, zero runtime overhead.

[![validate](https://github.com/jeeleonard9-art/opencode-permission-modes/actions/workflows/validate.yml/badge.svg)](https://github.com/jeeleonard9-art/opencode-permission-modes/actions/workflows/validate.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![opencode](https://img.shields.io/badge/OpenCode-1.19.3-000000)](https://opencode.ai)
[![platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)]()
[![PRs](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/jeeleonard9-art/opencode-permission-modes/pulls)

English · **[中文](README.md)**

![Permission matrix](assets/three-modes.png)

## What is this

OpenCode ships with two built-in agents, `build` and `plan`. Switching between them changes *whether the agent plans first*, not *how much it is allowed to touch*. If you want an agent that can read but never edit, or one that edits freely but asks before running commands, you end up clicking "approve" all day.

This repo splits permissions into three independent primary agents, built on OpenCode's native `permission` config:

| Mode | In one sentence | Best for |
| --- | --- | --- |
| `read-only` | Reads and searches only; never edits, never runs commands | Reading code, research, code review, explanations |
| `auto-edit` | Edits files freely, but shell commands and network need approval | Day-to-day work (**recommended default**) |
| `full-auto` | Everything allowed, no prompts | Small well-defined tasks, bulk refactors, unattended runs |

Switching is just picking another agent (press `Ctrl + .` in the desktop app). Permissions apply **immediately**: no app restart, no extra model call, no extra tokens.

## Why not a plugin

There are two ways to build this. I picked the second one:

| | Plugin (hooking tool execution) | **Agents + permission (this repo)** |
| --- | --- | --- |
| Runtime cost | Every tool call goes through JS logic | A lookup in memory, **zero overhead** |
| Complexity | Handle every branch of `tool.execute.before` | Pure config, no executable code |
| Visibility | Hidden in code; the UI never shows the active mode | **Shows up in the agent switcher** |
| Upgrade risk | Depends on non-public internals | Depends only on the public config schema |

## Permission matrix

| Tool | read-only | auto-edit | full-auto |
| --- | --- | --- | --- |
| `bash` run commands | deny | ask | allow |
| `edit` modify/create files | deny | allow | allow |
| `read` files | allow¹ | allow¹ | allow¹ |
| `glob` / `grep` / `list` search | allow | allow | allow |
| `webfetch` / `websearch` network | allow | ask | allow |
| `task` spawn subagent | deny | allow | allow |
| `question` ask you back | allow | allow | allow |
| `external_directory` outside workspace | ask | ask | allow |
| `todowrite` / `skill` | allow | allow | allow |
| `doom_loop` loop guard | ask | ask | ask |

¹ All three modes ask before reading `*.env` / `*.env.*`, and allow `*.env.example` — so the agent cannot casually pull secrets into the context window.

## Install

### One-liner scripts

**Windows**

```powershell
git clone https://github.com/jeeleonard9-art/opencode-permission-modes.git
cd opencode-permission-modes
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

**macOS / Linux**

```bash
git clone https://github.com/jeeleonard9-art/opencode-permission-modes.git
cd opencode-permission-modes
chmod +x install.sh && ./install.sh
```

The script does two things: copies `agent/*.md` into your config directory (anything that differs is backed up as `.bak`; identical files are skipped), and drops in an example config **only if** you don't have one yet. It never overwrites an existing `opencode.json`. It also writes `.opencode-permission-modes.manifest` next to your config, recording what was installed and which backup belongs to which file — that is what the uninstaller uses.

### Uninstall

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

```bash
# macOS / Linux
./uninstall.sh --yes
```

It restores the three `.md` files to their pre-install state (or deletes them if there was nothing to back up), never touches `opencode.json`, and warns you if `default_agent` still points at a mode that no longer exists.

### Manual install

1. Copy the three `.md` files from `agent/` into OpenCode's config directory:

   | OS | Path |
   | --- | --- |
   | Windows | `C:\Users\<you>\.config\opencode\agent\` |
   | macOS / Linux | `~/.config/opencode/agent/` |

2. Optional — make the three modes the only entries and default to `auto-edit`. Add to `opencode.json` (or `.jsonc`):

   ```jsonc
   {
     "$schema": "https://opencode.ai/config.json",
     "default_agent": "auto-edit",
     "agent": {
       "build": { "disable": true },
       "plan": { "disable": true }
     }
   }
   ```

   See [`examples/opencode.jsonc`](examples/opencode.jsonc). This step is optional; without it, `build` and `plan` simply stay in the list.

3. Restart OpenCode (new agent files are scanned at startup).

## Usage

- **Desktop app**: the agent picker above the input box, or `Ctrl + .` / `Shift + Ctrl + .` to cycle.
- **TUI**: `Tab` (depending on `agent_cycle` in your `tui.json`).
- **Change the default mode**: edit `default_agent`.
- **Change the keybinding**: Settings → Keybinds → *Model and agent*. **A restart is required.**

> Windows note: `Ctrl + Space` is the default IME toggle for Chinese input, so it usually never reaches the app. That is why this project uses `Ctrl + .`. Remap your IME if you prefer `Ctrl + Space`.

## Customizing

**Tweak a mode**: edit the `permission` block in the corresponding `agent/*.md`.

**Add a fourth mode**: copy any `.md`, give it a new `name` and `permission`, restart — it appears in the picker.

**Keep only two**: delete the file you don't want.

**Pin a mode to a different model**: add `model: provider/model-id` to that file's frontmatter.

**Harden `full-auto`**: `bash: allow` means it can run anything. If you want "everything allowed except the destructive stuff", copy [`presets/hardened-full-auto.md`](presets/hardened-full-auto.md) into your `agent/` directory (you get an extra `hardened-full-auto` mode) or use it to replace `agent/full-auto.md`. It denies:

```yaml
    "git push --force*": deny
    "git push -f*": deny
    "rm -rf*": deny
    "git reset --hard*": deny
    "git clean -f*": deny
```

> This is **glob matching on the command string**, not a sandbox. Variants like `sudo rm -rf` or `cd /tmp && rm -rf x` do not match a prefix pattern; add your own rules if you need them. For real isolation, use a container or a VM.

## How it works

None of the three agents carries a real system prompt (just one line announcing the mode). Their only difference is the `permission` field. Before each tool call, OpenCode evaluates that config locally: `deny` removes the tool from the model's tool list entirely, `ask` triggers a confirmation, `allow` goes straight through.

The rule that wins is the **last matching rule**; if nothing matches, the default is `ask`. One easy-to-miss gotcha: for custom agents, `question` defaults to `deny`, which is why every mode here sets `question: allow` explicitly.

More detail in [`docs/how-it-works.md`](docs/how-it-works.md) and [`docs/faq.md`](docs/faq.md).

## Compatibility

- Developed and verified on **OpenCode Desktop 1.19.3 (Windows)**.
- Uses only public config fields (`agent.*.permission`, `default_agent`, `agent.*.disable`); works with both the TUI and the desktop app.
- No dependencies, no build step, no executable code.
- CI runs on Ubuntu, macOS and Windows: it validates the permission schema, parses the frontmatter, checks documentation links, and exercises an install → reinstall → uninstall round-trip.

The full matrix (version × platform × form), version-sensitive details and a self-check list live in [`docs/compatibility.md`](docs/compatibility.md).

## Known limitations

- Adding or removing agent files requires an app restart. Editing an existing mode's permissions does not — see [`docs/faq.md`](docs/faq.md).
- `read-only` denies `task`, so it cannot spawn subagents. That is deliberate: a subagent brings its own permission set and is an easy way to escape the restriction.
- This is a *policy*, not a sandbox. `full-auto` with `bash: allow` means the agent can run anything. Only use it in an environment you trust.

## Feedback and maintenance

- **Found a bug**: use the [issue forms](https://github.com/jeeleonard9-art/opencode-permission-modes/issues/new/choose). They ask for your OpenCode version, OS, form factor and reproduction steps — missing one of those usually costs a round-trip.
- **Usage questions, ideas**: go to [Discussions](https://github.com/jeeleonard9-art/opencode-permission-modes/discussions) instead of the issue tracker.
- **Want to change something**: read [CONTRIBUTING.md](CONTRIBUTING.md) first; it spells out what this repo accepts and what it rejects.
- **Cadence**: this tracks changes to OpenCode's `permission` schema; every release is recorded in [CHANGELOG.md](CHANGELOG.md), tagged, and its verification status is kept in [compatibility.md](docs/compatibility.md).

CI guards every change: `scripts/validate_config.py` (standard library only) checks the `permission` keys and values, that `examples/opencode.jsonc` parses, and that relative links in this README resolve; CI then re-parses the frontmatter with a real YAML parser and runs the install/uninstall round-trip. Run the same check locally:

```bash
python scripts/validate_config.py
```

## Changelog

See [`CHANGELOG.md`](CHANGELOG.md).

## License

[MIT](LICENSE)
