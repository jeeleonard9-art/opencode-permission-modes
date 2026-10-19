#!/usr/bin/env bash
#
# Remove the OpenCode Permission Modes installed by install.sh.
#
# Reads .opencode-permission-modes.manifest and, for each of the three modes:
#   - restores the backup recorded at install time (if there is one), or
#   - removes the file if it was installed into a clean config directory.
#
# opencode.json / opencode.jsonc are never modified, but the script warns when
# default_agent still points at a mode that no longer exists.
#
# Usage:
#   ./uninstall.sh          # asks for confirmation
#   ./uninstall.sh --yes    # no prompt
#   OPENCODE_CONFIG_DIR=/path/to/config ./uninstall.sh

set -euo pipefail

CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
AGENT_DIR="$CONFIG_DIR/agent"
MANIFEST="$CONFIG_DIR/.opencode-permission-modes.manifest"
MODES="read-only.md auto-edit.md full-auto.md"

ASSUME_YES=0
case "${1:-}" in
  -y|--yes) ASSUME_YES=1 ;;
  "") ;;
  *) echo "Usage: $0 [--yes]" >&2; exit 2 ;;
esac

if [ ! -d "$AGENT_DIR" ]; then
  echo "Nothing to do: $AGENT_DIR does not exist."
  exit 0
fi

has_manifest_entry() {
  [ -f "$MANIFEST" ] || return 1
  awk -F'\t' -v name="$1" '$0 ~ /^#/ { next } $1 == name { found = 1 } END { exit !found }' "$MANIFEST"
}

prior_backup() {
  [ -f "$MANIFEST" ] || return 0
  awk -F'\t' -v name="$1" '$0 ~ /^#/ { next } $1 == name { print $2; exit }' "$MANIFEST"
}

newest_backup() {
  newest=""
  for candidate in "$AGENT_DIR/$1".*.bak "$AGENT_DIR/$1.bak"; do
    [ -f "$candidate" ] || continue
    if [ -z "$newest" ] || [ "$candidate" -nt "$newest" ]; then
      newest="$candidate"
    fi
  done
  if [ -n "$newest" ]; then basename "$newest"; fi
  return 0
}

# Collect the plan first, so the confirmation prompt lists exactly what happens.
plan="$(mktemp "${TMPDIR:-/tmp}/ocpm-plan.XXXXXX")"
trap 'rm -f "$plan"' EXIT

for mode in $MODES; do
  dst="$AGENT_DIR/$mode"
  exists=0
  [ -f "$dst" ] && exists=1

  backup=""
  if has_manifest_entry "$mode"; then
    backup="$(prior_backup "$mode")"
  elif [ "$exists" -eq 1 ]; then
    # Installed by an older version: fall back to the newest backup.
    backup="$(newest_backup "$mode")"
  fi
  if [ -n "$backup" ] && [ ! -f "$AGENT_DIR/$backup" ]; then backup=""; fi

  if [ -n "$backup" ]; then
    printf 'restore\t%s\t%s\n' "$mode" "$backup" >> "$plan"
  elif [ "$exists" -eq 1 ]; then
    printf 'remove\t%s\t-\n' "$mode" >> "$plan"
  fi
done

if [ ! -s "$plan" ]; then
  echo "Nothing to undo in $AGENT_DIR."
  rm -f "$MANIFEST"
  exit 0
fi

echo ""
echo "OpenCode Permission Modes - uninstall"
echo "Config directory: $CONFIG_DIR"
echo ""
echo "Planned changes:"
while IFS=$'\t' read -r action file backup; do
  if [ "$action" = "restore" ]; then
    echo "  restore $file  <-  $backup"
  else
    echo "  remove  $file"
  fi
done < "$plan"

echo ""
echo "opencode.json / opencode.jsonc will not be touched."
echo ""

if [ "$ASSUME_YES" -ne 1 ]; then
  printf "Proceed? [y/N] "
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Aborted. Nothing was changed."; exit 1 ;;
  esac
fi

while IFS=$'\t' read -r action file backup; do
  if [ "$action" = "restore" ]; then
    cp "$AGENT_DIR/$backup" "$AGENT_DIR/$file"
    rm -f "$AGENT_DIR/$backup"
    echo "  restored $file"
  else
    rm -f "$AGENT_DIR/$file"
    echo "  removed  $file"
  fi
done < "$plan"

rm -f "$MANIFEST"

# The config file is the user's: only warn, never edit.
for cfg in "$CONFIG_DIR/opencode.json" "$CONFIG_DIR/opencode.jsonc"; do
  [ -f "$cfg" ] || continue
  name="$(basename "$cfg")"
  default="$(sed -n 's/.*"default_agent"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cfg" | head -n 1)"
  case " $MODES " in
    *" $default.md "*)
      echo ""
      echo "Warning: $name still has \"default_agent\": \"$default\"."
      echo "That mode no longer exists; OpenCode will fall back to its built-in default."
      echo "Edit or remove default_agent in that file."
      ;;
  esac
  if grep -Eq '"build"[[:space:]]*:[[:space:]]*\{[[:space:]]*"disable"[[:space:]]*:[[:space:]]*true' "$cfg"; then
    echo ""
    echo "Note: $name disables the built-in build agent."
    echo "With the three modes gone, you may want to remove that too."
  fi
done

echo ""
echo "Done. Restart OpenCode to drop the modes from the picker."
echo ""
