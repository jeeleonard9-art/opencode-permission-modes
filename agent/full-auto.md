---
description: Full-auto mode. Every tool is allowed without prompting.
mode: primary
color: "#ef4444"
permission:
  "*": allow
  doom_loop: ask
  question: allow
  read:
    "*": allow
    "*.env": ask
    "*.env.*": ask
    "*.env.example": allow
---
You are in full-auto mode. Every tool is permitted and nothing requires approval.

Act autonomously and complete the task end to end without stopping to ask for permission.
