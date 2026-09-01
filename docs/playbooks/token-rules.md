---
metraMemory: procedural
defaultContext: false
loadWhen:
  - token rules
  - grep scope
  - cloud chats
  - CURSOR_API_KEY
  - large json
ceiling:
  - Never portfolio-wide grep without explicit authorization
  - Ask operator for session Cursor API key before cloud chat fallback
---

> Moved from `AGENTS.md` during A2 desk split. Preserve A1 done-when / On hard stop content unless intentionally revised.

# Token rules

- Project AGENTS authoring: [docs/AGENTS-Authoring.md](../AGENTS-Authoring.md) (stub budget, playbooks, default-context discipline).
- Prefer [docs/Decisions.md](../Decisions.md) for durable Metra portfolio choices before digging agent transcripts.
- Prefer `.\metra.ps1 decisions search` / `ctx -Query` related decisions for operational why-we-chose before transcript archaeology.
- When cloud chats are needed (`chats -Cloud`, mine a Cloud Agent thread) and the Cursor API key is missing from process **and** User/Machine environment, ask the operator for a **session** key before continuing - do not silently fall back to local-only. Prefer User env `CURSOR_API_KEY` when set (resolver checks process then User then Machine). See gitignored `docs/Cross-Device.local.md`. CLI never prompts for the key; chat does.
- Do not open generated catalogs, inventory dumps, `node_modules`, or local ticket caches unless required.
- Prefer project CLI filters (`Get-OrionCatalog`, TicketTracker `brief` / `chats`, `.\metra.ps1 ctx`) over reading large JSON/YAML or full agent transcripts wholesale.
- After routing, Grep/Glob with an absolute `path` scoped to the primary project (or `C:\Projects\_metra` for Metra work; older clones may use `_meta`). Do not search the whole multi-root workspace - Cursor echoes the same hit under every mounted folder.
- Prefer `.\metra.ps1 routing` / `.\metra.ps1 ctx` over portfolio-wide file search when choosing a project.
- Keep Metra guidance short; project details stay local. Promote durable chat clues into TicketTracker `note` / `solutions/`.
- Playbook bodies under `docs/playbooks/*.md` are not default context - read on trigger only.

## Inspect / Agent token economy

- **Pack vs queue:** Bing reads `pack-diff.md` / `pack-plan.md`. Cursor Agent uses `fix-queue.json` + `latest.json` only during implement/verify — never pack bodies.
- **Budget:** `.\metra.ps1 inspect budget -Name <Project>` estimates prompt payload chars (not tokens). Bands: GREEN &lt; 30k, WARN 30k–60k, PRUNE &gt; 60k total estimated chars.
- **Plan vs implement:** Do not load plans, Decisions, or `.cursor/plans/` during coding unless the task is policy/plan work.
- **Workspace:** Multi-root workspaces mount ~50 `AGENTS.md` stubs every turn. For expensive coding, open Metra + one project — not the full portfolio.
