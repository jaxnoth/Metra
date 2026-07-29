# Context routing and audit cadence

## Purpose

Keep agent response time and token use low by routing to one project, then loading only that project's compact guidance.

## Artifacts

| Path | Role |
|------|------|
| `projects.json` | Shared / public routing registry (example stubs OK) |
| `projects.local.json` | Machine-private work entries (gitignored) |
| Root `registryFile` | Optional per-root overlay (e.g. personal iCloud) |
| `profiles/sample/` | Anonymized operator pack for `import-profile` |
| `AGENTS.md` | Short human/agent fallback for `_meta` |
| `.cursor/rules/project-routing.mdc` | Always-on routing rule |
| `.cursor/rules/metra-persona.mdc` | Base Metra personality (tracked) |
| `.cursor/rules/metra-persona.local.mdc` | Operator overlay (gitignored) |
| Project `AGENTS.md` | Local entry playbook |
| Project `.cursorignore` | Hide generated/cache/binary noise |

## Multi-root isolation

Configured roots (see `meta.config.json` `roots`) stay separate:

- Work asks stay under the work root (`C:\Projects`).
- Personal asks stay under the personal root when present.
- Do not open another root unless the user names that project or asks to move material between them.
- `related` lists must stay same-root. Cross-root ideas (for example Misc scratch sheets into Trivia, or a personal bible game borrowing a work printable) are chat opt-in only.

`.\meta.ps1 routing` shows which registry entries resolved to a real folder. Optional shared stubs (TicketTracker, Solarwinds) return `whenMissing` advice when absent instead of counting as drift.

## Audit command

```powershell
.\meta.ps1 audit
.\meta.ps1 audit -Name Solarwinds,Trivia
.\meta.ps1 audit -Root personal
.\meta.ps1 audit -DriftOnly
.\meta.ps1 routing
.\meta.ps1 routing -MissingOnly
```

The audit is a **re-runnable probe**. Do not rewrite it for routine project changes. Re-run it; update curated files when it reports drift. Cloud/personal roots use light audit (no deep recursive scan).

## When to re-audit

- After adding a sibling project
- After adding or changing a project root
- After a major layout rename or new generated/cache tree
- Periodically across the portfolio (for example monthly)
- Before investigating unexplained high token use

## What to update on drift

| Finding | Action |
|---------|--------|
| Work project on disk missing from local/shared registry | Add a row to `projects.local.json` (or `projects.json` only if coworkers should see it) |
| Personal project missing from personal registry | Update that root's `registryFile` |
| Missing `AGENTS.md` / `.cursorignore` where recommended | Add compact local files |
| New large/generated path not excluded | Extend `.cursorignore` and registry `excludePaths` |
| Stale trigger terms | Update the owning registry from current README/entry docs |
| Routine edits inside existing paths | No registry work |

## Cadence principle

Usually re-run; rarely rewrite. Treat drift as a manual review signal rather than auto-regenerating guidance.

## Canvas Ops board

Open the Cursor Canvas `meta-ops-board` beside chat for visual health + routing (Ops tab = health + recommender; Triage tab = session checklist). Typical local path: `%USERPROFILE%\.cursor\projects\c-Projects-meta\canvases\meta-ops-board.canvas.tsx` (folder name may vary by machine).

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
