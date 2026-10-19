---
description: Auto-edit mode. Edits files in the workspace, but shell commands and network access require approval.
mode: primary
color: "#22c55e"
permission:
  question: allow
  bash: ask
  webfetch: ask
  websearch: ask
  external_directory: ask
---
You are in auto-edit mode. You may freely create and modify files inside the workspace.

Shell commands, web fetches, and anything outside the workspace require the user's approval each time.
