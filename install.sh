#!/usr/bin/env bash
#
# Install OpenCode Permission Modes (read-only / auto-edit / full-auto).
#
# Copies agent/*.md into the OpenCode config directory. Files that differ from
# the ones shipped here are backed up to *.bak first; identical files are left
# alone.
#
# If the config directory has no opencode.json / opencode.jsonc, an example config
# is created. An existing config is never overwritten.
#
# A small manifest (.opencode-permission-modes.manifest) records what was
# installed and which backup belongs to which file, so uninstall.sh can put your
# original files back.
#
# Usage:
#   chmod +x install.sh && ./install.sh
#   OPENCODE_CONFIG_DIR=/path/to/config ./install.sh

set -euo pipefail

CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_AGENT="$SCRIPT_DIR/agent"
DST_AGENT="$CONFIG_DIR/agent"
MANIFEST="$CONFIG_DIR/.opencode-permission-modes.manifest"

if [ ! -d "$SRC_AGENT" ]; then
  echo "Cannot find the agent directory: $SRC_AGENT (run this script from the repo root)" >&2
  exit 1
fi

echo ""
echo "OpenCode Permission Modes"
echo "Config directory: $CONFIG_DIR"
echo ""

mkdir -p "$DST_AGENT"

# Backup recorded by a previous install, if any.
prior_backup() {
  [ -f "$MANIFEST" ] || return 0
  awk -F'\t' -v name="$1" '$0 ~ /^#/ { next } $1 == name { print $2; exit }' "$MANIFEST"
}

stamp="$(date +%Y%m%d-%H%M%S)"
count=0
unchanged=0
entries="$(mktemp "${TMPDIR:-/tmp}/ocpm-entries.XXXXXX")"
trap 'rm -f "$entries"' EXIT

for f in "$SRC_AGENT"/*.md; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"
  dst="$DST_AGENT/$name"
  backup=""

  if [ -f "$dst" ]; then
    if cmp -s "$dst" "$f"; then
      backup="$(prior_backup "$name")"
      printf '%s\t%s\n' "$name" "$backup" >> "$entries"
      echo "  unchanged $name"
      unchanged=$((unchanged + 1))
      continue
    fi
    backup="$name.$stamp.bak"
    cp "$dst" "$DST_AGENT/$backup"
    echo "  backup $name  ->  $backup"
  fi

  cp "$f" "$dst"
  printf '%s\t%s\n' "$name" "$backup" >> "$entries"
  echo "  installed $name"
  count=$((count + 1))
done

{
  echo "# opencode-permission-modes install manifest (v1)"
  echo "# <agent file> tab <backup file or empty>"
  echo "# Used by uninstall.sh to restore your originals. Safe to delete."
  cat "$entries"
} > "$MANIFEST"

if [ ! -f "$CONFIG_DIR/opencode.json" ] && [ ! -f "$CONFIG_DIR/opencode.jsonc" ]; then
  cp "$SCRIPT_DIR/examples/opencode.jsonc" "$CONFIG_DIR/opencode.jsonc"
  echo ""
  echo "Created opencode.jsonc (defaults to auto-edit, hides build/plan)"
else
  echo ""
  echo "Existing config detected, left untouched. To default to auto-edit and hide build/plan, add:"
  echo '    "default_agent": "auto-edit",'
  echo '    "agent": { "build": { "disable": true }, "plan": { "disable": true } }'
fi

echo ""
echo "Done. Installed $count mode(s), $unchanged unchanged."
echo "Restart OpenCode, then switch modes with Ctrl + . in the agent picker."
echo "To undo this later: ./uninstall.sh"
echo ""
