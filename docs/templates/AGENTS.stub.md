# AGENTS.md

This file is the desk index for this project. Keep it short. Put procedures in `docs/playbooks/*.md`.

Authoring standard: [docs/AGENTS-Authoring.md](../AGENTS-Authoring.md) (Metra home) or project-local pointer when split.

## Route here when

- The task is about:
  - `<project purpose>`
  - `<main workflow>`
  - `<known trigger phrase>`

## Start here

1. Confirm the task belongs here.
2. Read this stub before opening project files.
3. If a playbook matches the task, read that playbook before acting.
4. If no playbook matches, stay in advice / local context mode and ask the operator before consequential changes.

## Ceilings

- Do not perform Live or destructive actions without explicit operator confirmation.
- Do not treat examples as current facts unless verified.
- Do not invent missing system access.
- Do not write to external systems unless the operator explicitly asks.

## On-demand playbooks

| Trigger | Read |
| --- | --- |
| `<trigger phrase>` | `docs/playbooks/<playbook>.md` |

## Token rules

- This stub should stay under 100 physical lines.
- Playbook bodies do not belong in this file.
- Prefer links over copied command catalogs.
- Move long done-when, hard-stop, and triage procedures to cabinet files.

## Related

- `README.md`
- `docs/playbooks/` (when present)
