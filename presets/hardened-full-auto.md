---
description: Full-auto with destructive git and shell commands blocked. Optional hardening.
mode: primary
color: "#ef4444"
permission:
  "*": allow
  doom_loop: ask
  question: allow
  bash:
    "*": allow
    "git push --force*": deny
    "git push -f*": deny
    "rm -rf*": deny
    "git reset --hard*": deny
    "git clean -f*": deny
  read:
    "*": allow
    "*.env": ask
    "*.env.*": ask
    "*.env.example": allow
---
You are in full-auto mode, with a short list of destructive commands blocked:
force-push, rm -rf, git reset --hard and git clean -f are not available to you.

Everything else is permitted and nothing requires approval. Act autonomously and
complete the task end to end. If a task genuinely needs one of the blocked
commands, stop and ask the user to run it.
