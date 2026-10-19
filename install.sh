#!/usr/bin/env bash
#
# Install OpenCode Permission Modes (read-only / auto-edit / full-auto).
#
# Copies agent/*.md into the OpenCode config directory. Existing files with the
# same name are backed up to *.bak first.
#
# If the config directory has no opencode.json / opencode.jsonc, an example config
# is created. If a config already exists, the script only prints the snippet to add
# manually - it never overwrites your file.
#
# Usage:
#   chmod +x install.sh && ./install.sh
#   OPENCODE_CONFIG_DIR=/path/to/config ./install.sh

set -euo pipefail

CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_AGENT="$SCRIPT_DIR/agent"
DST_AGENT="$CONFIG_DIR/agent"

if [ ! -d "$SRC_AGENT" ]; then
  echo "Cannot find the agent directory: $SRC_AGENT (run this script from the repo root)" >&2
  exit 1
fi

echo ""
echo "OpenCode Permission Modes"
echo "Config directory: $CONFIG_DIR"
echo ""

mkdir -p "$DST_AGENT"

stamp="$(date +%Y%m%d-%H%M%S)"
count=0
for f in "$SRC_AGENT"/*.md; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"
  dst="$DST_AGENT/$name"
  if [ -f "$dst" ]; then
    cp "$dst" "$dst.$stamp.bak"
    echo "  backup $name  ->  $name.$stamp.bak"
  fi
  cp "$f" "$dst"
  echo "  installed $name"
  count=$((count + 1))
done

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
echo "Done. Installed $count mode(s)."
echo "Restart OpenCode, then switch modes with Ctrl + . in the agent picker."
echo ""
