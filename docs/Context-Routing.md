# Context routing and audit cadence

## Purpose

Keep agent response time and token use low by routing to one project, then loading only that project's compact guidance.

## Desk model (context anti-rot)

Portfolio knowledge follows the desk model scar in [Decisions.md](Decisions.md) (2026-08-14).

| Layer | Role | Examples |
|-------|------|----------|
| Index | Route and point; always-on stays tiny | `projects.json`, `routing` / `ctx`, stub `AGENTS.md`, OCC |
| Cabinet | Detail on demand; keep files small | skills, solutions, playbooks, one Decision Registry entry |
| Writes | Classify home, dedupe, update index pointer | `capture promote`, `decisions promote`, git commit |

Agents read the index, then named cabinet files only - not the whole cabinet every chat. Cursor multi-root workspaces that inject every full `AGENTS.md` violate this scar until agent lane **A2** stub/skill splits land (see gitignored `Future-Development.local.md`).

## Artifacts

| Path | Role |
|------|------|
| `projects.json` | Shared / public routing registry (example stubs OK) |
| `projects.local.json` | Machine-private work entries (gitignored) |
| Root `registryFile` | Optional per-root overlay (e.g. personal iCloud) |

**Registry merge precedence** (same project `name`: later wins):

1. Shared `projects.json`
2. Each configured root `registryFile` (`Get-MetraRoots` order)
3. `projects.local.json`

Registry project rows use the same optional arrays for consistency: `triggers`, `capabilities`, `serves`, `gitPaths`, and `related` (all `string[]`). `gitPaths` names folders **below** the project root that hold the git repo, for projects where the root is not the repo (for example Jitterbit tracks `IWU.Jitterbit/`). When the root has no `.git` and `gitPaths` is absent, the snapshot shallow-probes immediate child folders; counts across nested repos are summed and the desk labels the subfolder. Set `gitPaths` explicitly when the probe would be ambiguous or wrong. `serves` is **For whom?** - audiences of the work (roles, teams, consumer systems), never people/requester memory. Omit or leave empty when unknown; `routing -Name` / `-Query` and `ctx` print a For whom? block only when non-empty. `related` is same-root neighbor topology (preserve registry order; dedupe; cap 6 in `ctx` / routing via `Get-MetraRelatedProjects`). **Related is topology, not permission to multi-repo search** - open a related project only when evidence requires it.
| `profiles/sample/` | Anonymized operator pack for `import-profile` |
| `AGENTS.md` | Short human/agent fallback for the Metra checkout |
| `.cursor/rules/project-routing.mdc` | Always-on routing rule |
| `.cursor/rules/metra-persona.mdc` | Base Metra personality (tracked) |
| `.cursor/rules/metra-persona.local.mdc` | Operator overlay (gitignored) |
| Project `AGENTS.md` | Local desk index (stub); procedures in `docs/playbooks/*.md` - see [AGENTS-Authoring.md](AGENTS-Authoring.md) |
| Project `.cursorignore` | Hide generated/cache/binary noise |
| `docs/Decisions.md` | Append-only portfolio-wide Metra policy (prefer before transcript dig) |
| `docs/Agentic-Maturity.md` | Workflow L1-L6 maturity / completeness scorecards (design metric; not Ops health) |

## Multi-root isolation

Configured roots (see `metra.config.json` `roots`) stay separate:

- Work asks stay under the primary work root (example: `C:\Projects`).
- Personal asks stay under the personal root when present.
- Do not open another root unless the user names that project or asks to move material between them.
- `related` lists must stay same-root. Cross-root ideas (for example Misc scratch sheets into Trivia, or a personal bible game borrowing a work printable) are chat opt-in only.

`.\metra.ps1 routing` shows which registry entries resolved to a real folder. `.\metra.ps1 ctx` writes a bounded agent context pack (present projects + reminders). With `-Query`, `ctx` also composes a **Project story** for the primary stop from existing fields (`purpose`, `triggers`, `serves`, `related`, optional `whenPresent`) plus Why Here ledger hits - no separate story field. Optional shared stubs (TicketTracker, Solarwinds) return `whenMissing` advice when absent instead of counting as drift.

## Registry triggers (when to activate)

Treat `triggers` like Agent Skills "when to activate" text: short, distinctive phrases that should fire this stop - not a second copy of `purpose`.

| Do | Avoid |
|----|-------|
| Multi-word or product/workflow phrases (`ops desk`, `stuck process`, `word search`) | Stop words and generic English (`help`, `today`, `project`, `the`) |
| Workflow vocabulary on TicketTracker (`ticket`, `isupport`, `helpdesk`) | Product/vendor laundry lists on TicketTracker (see Decisions 2026-08-04) |
| Keep `purpose` as the one-line "what this project is" | Stuffing purpose prose into triggers |
| Optional stubs: always set `whenMissing` advice | Empty `whenMissing` on `optional: true` rows |

Shared stop list for query scoring lives in `Get-MetraRoutingStopWords` (`scripts/private/Routing.ps1`). Prefer triggers that would survive that filter if used as query tokens.

After any registry trigger / purpose / route edit that should appear in the explain surface: update the owning registry file, then `.\metra.ps1 selfdoc` (or `Export-MetraSnapshot -RefreshSelfDocumentation`). Do not invent a parallel process. Report-only route metadata checks live on `.\metra.ps1 audit` and `.\metra.ps1 audit -MetadataOnly` (empty purpose/triggers, optional missing `whenMissing`, exact stop-word / single-character triggers). Advisories only - never auto-edit the registry and never counted as drift.

Human-facing desks (HTML Ops Ask / Route, Overview/selfdoc, companion stubs) consume these same fields - map quality is not agent-only. Parking-lot dependency notes: gitignored `docs/Future-Development.local.md` (Agent-facing lane).

## Audit command

```powershell
.\metra.ps1 audit
.\metra.ps1 audit -Name Solarwinds,Trivia
.\metra.ps1 audit -Root personal
.\metra.ps1 audit -DriftOnly
.\metra.ps1 audit -MetadataOnly
.\metra.ps1 routing
.\metra.ps1 routing -MissingOnly
.\metra.ps1 ctx
.\metra.ps1 ctx -Query "ticket disk"
.\metra.ps1 verify
```
The audit is a **re-runnable probe**. Do not rewrite it for routine project changes. Re-run it; update curated files when it reports drift. `-MetadataOnly` skips the recursive tree scan and prints route registry advisories only. Cloud/personal roots use light audit (no deep recursive scan). Each project with `AGENTS.md` prints a physical line count (`OK` / `WARN` against `audit.agentsLineBudget`, default 100). Normal audit also prints **Context Footprint Estimate** (alwaysApply rules + mounted AGENTS; report-only, not a merge gate). Use `verify` for Routing-Scenarios fixture smoke (PASS/WARN/FAIL).

## When to re-audit

- After adding a sibling project
- After adding or changing a project root
- After a major layout rename or new generated/cache tree
- Periodically across the portfolio (for example monthly)
- Before investigating unexplained high token use

## Self-documentation (repeatable)

After **any** registry / trigger / route change that should show up in the explain surface, refresh self-docs:

```powershell
.\metra.ps1 selfdoc
```

What it updates:

| Artifact | Role |
|----------|------|
| Cursor canvas `metra-self-documentation` | Visual primary - route diagram + standing examples verified by the live router |
| `docs/Overview.md` | Sendable prose twin (standing route table between HTML markers) |
| `%LOCALAPPDATA%\Metra\selfdoc\selfdoc-routes.json` | Sidecar for site/forge later |
| `%LOCALAPPDATA%\Metra\selfdoc\selfdoc-routing-examples.json` | Living validation suite (ticket id, home fallback, verified asks) |
| `integrations/cursor/metra-self-documentation.canvas.tsx.template` | Tracked template synced from the live canvas |

Selfdoc documents **routing behavior**, not only registry fields:

- Sample asks are confirmed with `Get-MetraRoutingAmbiguity` (so ticket id / vocab / solutions precedence stay honest).
- Only **present** projects from `Get-MetraRoutingTable` appear.
- Featured order comes from `routing.featuredProjects` and/or project `featured: true` (not a hard-coded list in `SelfDocumentation.ps1`).

`.\metra.ps1 snapshot` exports board state only; pass `-RefreshSelfDocumentation` when you want selfdoc in the same call. `.\metra.ps1 setup` regenerates the context pack and self-documentation as a pair (same known-good checkout). Do not hand-edit the generated route table or the canvas `SELFDOC_ROUTES` embed - change the registry / triggers, then re-run `selfdoc`.

## What to update on drift

| Finding | Action |
|---------|--------|
| Work project on disk missing from local/shared registry | Add a row to `projects.local.json` (or `projects.json` only if coworkers should see it) |
| Personal project missing from personal registry | Update that root's `registryFile` |
| Missing `AGENTS.md` / `.cursorignore` where recommended | Add compact local files |
| New large/generated path not excluded | Extend `.cursorignore` and registry `excludePaths` |
| Stale trigger terms | Update the owning registry from current README/entry docs, then `.\metra.ps1 selfdoc` |
| Route metadata advisories (`audit -MetadataOnly`) | Fix the named field on that registry row; never treat as drift; then `.\metra.ps1 selfdoc` if purpose/triggers changed |
| `AGENTS.md` over stub line budget (`audit`) | Advisory WARN only - split stub vs `docs/playbooks/` per [AGENTS-Authoring.md](AGENTS-Authoring.md); audit never auto-edits |
| Registry route / trigger / purpose change | `.\metra.ps1 selfdoc` (or `snapshot -RefreshSelfDocumentation`) so the self-doc canvas + Overview stay honest |
| Routine edits inside existing paths | No registry work |

## Cadence principle

Usually re-run; rarely rewrite. Treat drift as a manual review signal rather than auto-regenerating guidance.

## Metra home destination

Metra itself is a registry destination (`projects.json` name `Metra`) and the **default home** (`routing.homeDestination`). Stay on Metra until another project wins with a confident score. Ticket/helpdesk work still starts in TicketTracker.

## HTML Ops desk (primary)

```powershell
.\metra.ps1 ops
```

Browser home screen on loopback (`http://127.0.0.1:7380` by default). **General** mode is Route-first (Ask, next attention, Classify/Handoff). **Advanced desk** in Settings unlocks Projects / Recent / Health. Shared brain: `%LOCALAPPDATA%\Metra\desk\canvas-snapshot.json` via `Get-MetraDeskPayload`. Cursor is optional.

## Canvas Ops board (advanced IDE)

Open the Cursor Canvas **Metra Ops** (`metra-ops-board`) beside chat when you want the IDE faceplate. One board, three tabs organized around operator questions:

| Tab | Job |
|-----|-----|
| **Route** (default) | Classify a request and produce a bounded handoff (Where / What / Why / For whom / Next) |
| **Portfolio** | What needs attention - drift, hygiene, root-filtered project detail |
| **Stewardship** | What knowledge needs tending - Decision Registry, OCC, coverage gaps, ledger hygiene (stale / missing why / superseded; visibility only) |

The board **retrieves from existing homes** (routing registry, Decision Registry, OCC, audit/verify). It does not become a second write surface; durable actions stay in CLI/chat.

Typical local path (slug is path-derived from the checkout folder):

`%USERPROFILE%\.cursor\projects\<cursor-slug>\canvases\metra-ops-board.canvas.tsx`

For a `_metra` checkout under `C:\Projects`, the slug is usually `c-Projects-metra`. An older `_meta` checkout is usually `c-Projects-meta`.

Refresh data after audits or layout changes:

```powershell
.\metra.ps1 snapshot          # full audit + git + verify summary
.\metra.ps1 snapshot -Quick   # hook-friendly; registry + light health; git/verify marked not checked
```

The live `.canvas.tsx` is generated. `snapshot` rewrites the data between the `<metra-ops-snapshot>` markers and reinstalls the surrounding component code whenever it differs from `integrations/cursor/metra-ops-board.canvas.tsx.template`. Edit the template, not the live canvas - local edits outside the markers are replaced on the next snapshot. Close and reopen the canvas panel to pick up a refreshed board.

Local snapshot also carries bounded Decision Registry / OCC summaries, per-project `serves` and Why Here snippets, knowledge-coverage counts plus capped gap lists, and decision-registry review facts (stale / missing why / superseded - not scores). Use `.\metra.ps1 coverage` and `.\metra.ps1 decisions review` for the same visibility without the canvas. Gitignored; fail-open when ledgers are missing.

Agent chat `sessionStart` can run `-Quick` when the snapshot is stale - see [Integrations.md](Integrations.md). Do not auto-run `workspace` from that hook.

Brand kit for the faceplate: [Brand.md](Brand.md).

Validate with [Routing-Scenarios.md](Routing-Scenarios.md).

## Chat context bridge (ticket work)

Cursor stores agent transcripts under `%USERPROFILE%\.cursor\projects\c-Projects-<Name>\agent-transcripts\`. Those files are **local Cursor artifacts**, not git, and are not auto-injected into new meta chats.

**Sticky ticket threads:** If the chat opened on a ticket (id / helpdesk triggers / solutions keywords), keep **TicketTracker** as primary for later turns. Precedence: thread > ticket id > ticket vocab > solutions keywords > technical score > Metra home. Ticket-ops stay in TicketTracker - example: Thrive access denied thread stays TicketTracker for resolve/email, not a Datamart rewrite. Do not grow TicketTracker registry triggers with product names. Open a technical project only for an explicit investigate ask (or when ticket-ops cannot finish); return durable writes to TicketTracker. See [Decisions.md](Decisions.md) (routing precedence; in-thread sticky primary).

During ticket triage, search transcripts for clues (bounded summaries only):

```powershell
# From TicketTracker (uses RoutingTerms + ticket id)
.\TicketTracker.ps1 chats <id>
.\TicketTracker.ps1 chats <id> -Name Solarwinds -IncludeMeta

# From the Metra checkout
.\metra.ps1 chats -Name Solarwinds -Query "disk alert"
.\metra.ps1 chats -Name TicketTracker,Solarwinds -Ticket 12345 -IncludeMeta
```

Canonical durable memory remains:
- TicketTracker `note` (prefer `-Tags chat` and cite `[short title](chat-uuid)`)
- `solutions/` write-ups for recurring patterns
- `Metra AI Recommendation:` on the ticket description when analysis supports it
- For Metra portfolio policy (persona, brand, hooks): [Decisions.md](Decisions.md)

Do not dump full JSONL transcripts into agent context unless the user opens a specific chat.

## Related

- [Routing-Scenarios.md](Routing-Scenarios.md) - routing / persona smoke + `verify`
- [Integrations.md](Integrations.md) - Cursor adapter, sessionStart, ctx handoff
- [search-echo.md](playbooks/search-echo.md) - multi-root Grep echo
- [Decisions.md](Decisions.md) - append-only Metra policy
- [Brand.md](Brand.md) - Ops board brand kit
