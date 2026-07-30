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
| `docs/Decisions.md` | Append-only portfolio-wide Metra policy (prefer before transcript dig) |

## Multi-root isolation

Configured roots (see `meta.config.json` `roots`) stay separate:

- Work asks stay under the primary work root (example: `C:\Projects`).
- Personal asks stay under the personal root when present.
- Do not open another root unless the user names that project or asks to move material between them.
- `related` lists must stay same-root. Cross-root ideas (for example Misc scratch sheets into Trivia, or a personal bible game borrowing a work printable) are chat opt-in only.

`.\meta.ps1 routing` shows which registry entries resolved to a real folder. `.\meta.ps1 ctx` writes a bounded agent context pack (present projects + reminders). Optional shared stubs (TicketTracker, Solarwinds) return `whenMissing` advice when absent instead of counting as drift.

## Audit command

```powershell
.\meta.ps1 audit
.\meta.ps1 audit -Name Solarwinds,Trivia
.\meta.ps1 audit -Root personal
.\meta.ps1 audit -DriftOnly
.\meta.ps1 routing
.\meta.ps1 routing -MissingOnly
.\meta.ps1 ctx
.\meta.ps1 ctx -Query "ticket disk"
.\meta.ps1 verify
```
The audit is a **re-runnable probe**. Do not rewrite it for routine project changes. Re-run it; update curated files when it reports drift. Cloud/personal roots use light audit (no deep recursive scan). Use `verify` for Routing-Scenarios fixture smoke (PASS/WARN/FAIL).

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

## Canvas Ops board (Metra Ops)

Open the Cursor Canvas **Metra Ops** (`metra-ops-board`) beside chat for visual health + routing (Ops tab = health + recommender; Triage tab = session checklist).

Typical local path (slug is path-derived from the checkout folder):

`%USERPROFILE%\.cursor\projects\<cursor-slug>\canvases\metra-ops-board.canvas.tsx`

For a `_meta` checkout under `C:\Projects`, the slug is usually `c-Projects-meta`.

Refresh data after audits or layout changes:

```powershell
.\meta.ps1 snapshot          # full audit + git
.\meta.ps1 snapshot -Quick   # hook-friendly; registry + light health only
```

Agent chat `sessionStart` can run `-Quick` when the snapshot is stale - see [Integrations.md](Integrations.md). Do not auto-run `workspace` from that hook.

Brand kit for the faceplate: [Brand.md](Brand.md).

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
- For Metra portfolio policy (persona, brand, hooks): [Decisions.md](Decisions.md)

Do not dump full JSONL transcripts into agent context unless the user opens a specific chat.

## Related

- [Routing-Scenarios.md](Routing-Scenarios.md) - routing / persona smoke + `verify`
- [Integrations.md](Integrations.md) - Cursor adapter, sessionStart, ctx handoff
- [Search-Echo.md](Search-Echo.md) - multi-root Grep echo
- [Decisions.md](Decisions.md) - append-only Metra policy
- [Brand.md](Brand.md) - Ops board brand kit
