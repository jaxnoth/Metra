# Context routing and audit cadence

## Purpose

Keep agent response time and token use low by routing to one project, then loading only that project's compact guidance.

## Artifacts

| Path | Role |
|------|------|
| `projects.json` | Machine-readable registry (purpose, triggers, paths) |
| `AGENTS.md` | Short human/agent fallback for `_meta` |
| `.cursor/rules/project-routing.mdc` | Always-on routing rule |
| Project `AGENTS.md` | Local entry playbook |
| Project `.cursorignore` | Hide generated/cache/binary noise |

## Audit command

```powershell
.\meta.ps1 audit
.\meta.ps1 audit -Name Solarwinds
.\meta.ps1 audit -DriftOnly
```

The audit is a **re-runnable probe**. Do not rewrite it for routine project changes. Re-run it; update curated files when it reports drift.

## When to re-audit

- After adding a sibling project
- After a major layout rename or new generated/cache tree
- Periodically across the portfolio (for example monthly)
- Before investigating unexplained high token use

## What to update on drift

| Finding | Action |
|---------|--------|
| Project on disk missing from registry | Add a row to `projects.json` |
| Missing `AGENTS.md` / `.cursorignore` where recommended | Add compact local files |
| New large/generated path not excluded | Extend `.cursorignore` and registry `excludePaths` |
| Stale trigger terms | Update `projects.json` triggers from current README/entry docs |
| Routine edits inside existing paths | No registry work |

## Cadence principle

Usually re-run; rarely rewrite. Treat drift as a manual review signal rather than auto-regenerating guidance.

## Canvas Ops board

Open the Cursor Canvas [meta-ops-board](C:/Users/admin.sswan/.cursor/projects/c-Projects-meta/canvases/meta-ops-board.canvas.tsx) beside chat for visual health + routing (Ops tab = health + recommender; Triage tab = session checklist).

Refresh data after audits or layout changes:

```powershell
.\meta.ps1 snapshot
```

This writes [`canvas-snapshot.json`](canvas-snapshot.json) and updates the embedded `SNAPSHOT` block between `// <meta-ops-snapshot>` markers in the canvas. The canvas cannot read disk at runtime - always re-run `snapshot` (or ask the agent to) when the board looks stale.

Snapshot health includes:
- Agent routing coverage (`AGENTS.md`, `.cursorignore`, drift findings)
- Git counts per project: dirty files, ahead/behind vs upstream (local only; no fetch), branch name, and a short summary (`clean` / `dirty N` / `ahead N` / `behind N`)

Validate with [Routing-Scenarios.md](Routing-Scenarios.md).

## Chat context bridge (ticket work)

Cursor stores agent transcripts under `%USERPROFILE%\.cursor\projects\c-Projects-<Name>\agent-transcripts\`. Those files are **local Cursor artifacts**, not git, and are not auto-injected into new meta chats.

During ticket triage, search them for clues (bounded summaries only):

```powershell
# From TicketTracker (uses RoutingTerms + ticket id)
.\TicketTracker.ps1 chats <id>
.\TicketTracker.ps1 chats <id> -Name Solarwinds -IncludeMeta

# From _meta
.\meta.ps1 chats -Name Solarwinds -Query "disk alert"
.\meta.ps1 chats -Name TicketTracker,Solarwinds -Ticket 12345 -IncludeMeta
```

Canonical durable memory remains:
- TicketTracker `note` (prefer `-Tags chat` and cite `[short title](chat-uuid)`)
- `solutions/` write-ups for recurring patterns
- `AI Recommendation:` on the ticket description when analysis supports it

Do not dump full JSONL transcripts into agent context unless the user opens a specific chat.
