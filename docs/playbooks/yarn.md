# Yarn intake playbook (A0–A4 + Phase B Atlas)

## Route here when

`yarn`, intake backlog, Capture→plan, Future-Dev scan, Atlas memory intake, pack freshness, plan approve / Loom handoff.

## Formal plan path homes

| Stage | Location |
|-------|----------|
| Yarn `synthesize` / Bing draft | `%USERPROFILE%\.cursor\plans\` (Cursor Build/preview UX) |
| Successful Loom ingest (after `yarn plan approve` handoff) | **Copy** to `<project>\plans\` + rewrite backlog/plan-link `formalPlanPath` |
| Human docs | `<project>\docs\` only — not a Yarn synthesize writer |

Copy runs on successful Loom ingest (including reconcile retry that succeeds). `-SkipIngest` leaves the draft in `.cursor\plans`. Legacy `docs\*.plan.md` remain readable for inventory/allowlists.

## Commands

```powershell
.\metra.ps1 yarn status
.\metra.ps1 yarn scan
.\metra.ps1 yarn backlog
.\metra.ps1 yarn daily
.\metra.ps1 yarn synthesize -BacklogId <id> -Confirm
.\metra.ps1 yarn synthesize -FromMemory <stableId> -Confirm
.\metra.ps1 yarn pack -BacklogId <id>
.\metra.ps1 yarn reconcile [-DryRun]
.\metra.ps1 yarn pending
.\metra.ps1 yarn plan approve -BacklogId <id> -Confirm
.\metra.ps1 yarn plan approve -Path <formal.plan.md> -Confirm
.\metra.ps1 plan-board status
.\metra.ps1 plan-board sync -DryRun
.\metra.ps1 plan-board sync
.\metra.ps1 plan-board inventory
.\metra.ps1 plan-board inventory apply -Confirm
```

## Plan Board projection

Notion Plan Board is an **ops projection** only. Yarn backlog status and Loom verified `accepted` remain systems of record.

Copy `modules/Yarn/config/plan-board.example.json` to the Yarn root settings file (placeholders only in the example):

`%LOCALAPPDATA%\Metra\yarn\plan-board.settings.json`

That path is `Join-Path (Get-MetraYarnRoot) 'plan-board.settings.json'` (override with `METRA_YARN_ROOT` if set). Token: `METRA_NOTION_API_KEY`, else Atlas Notion `apiKey`. Missing Plan Board never blocks intake or approve.

`yarn scan` skips per-item Plan Board notifies. Full catch-up is `plan-board sync`, which rebuilds from **all** Yarn backlog items (with or without `formalPlanPath`), plan-links, Loom queue plan paths, and existing Plan Board cards.

| Event | Board update? |
|-------|---------------|
| Yarn status persisted: `idea` \| `ready` \| `pending-bing` \| `stale-pack` \| `approved` \| `parked` \| `rejected` | Yes (fail-open, once after persist; not during bulk `scan`) |
| Successful Loom handoff | Yes |
| Verified Loom `accepted` (after local commit verify) | Yes (Shipped) |
| `accepted-pending-commit` / other Loom hops | No |
| Failed Yarn mutation or failed handoff | No |

Resolver uses **explicit precedence** (not highest Stage). Manual Notion Board/Stage edits are non-authoritative and may be overwritten.

### Stages and views (v2)

| Stage | Board | On By Stage? | Meaning |
|------:|-------|:------------:|---------|
| 1 | Inbox | no | Unresolved existing card |
| 2 | Backlog | no | Idea/process without formal plan |
| 3 | Idea | yes | Formal plan path; not yet Active |
| 4 | Active | yes | `pending-bing` / `stale-pack` |
| 5 | Loom | yes | Handoff / active queue / `approved` |
| 6 | Shipped | yes | Verified Loom `accepted` only |
| 7 | Parked | yes | Yarn `parked` or affirmed inventory Park |
| 8 | Drop | no | Yarn `rejected` or affirmed inventory Drop |

One Notion database. Operator views (Metra does not create them via API): **By Stage** is the default/main tab (lean: Idea, Active, Loom, Shipped, Parked). Side tabs: Inbox, Backlog, Drop. Optional Kanban uses the same lean filter. Group/board columns by **Stage** (1–8), not Board (Board A–Z puts Active before Backlog). Remove any tab named **Default view**. Notion one-time: add Board option `Backlog`; Stage up to 8.

Upsert writes **Project** (select: Metra / TicketTracker / Atlas / Other) from Yarn `projectKey`, else title/CursorPlan hints, else Metra for formal plans. **Subproject** (Ask, LoomYarn, Inspect, Installer, OpsDesk, Routing, iOS/Face, Persona, Ticket, AtlasMemory, Personal, Other) mirrors inventory `clusterHint` and is filled especially for Metra cards. **Description** is a short blurb from the plan YAML `overview` (trimmed, ~280 chars). **PlanPath** is the full resolved path to the `.plan.md` (formal path, else `%USERPROFILE%\.cursor\plans\`, else `_meta\plans\`, else `_meta\docs\`). Truncated Pass 1 CursorPlan stems (missing `_xxxxxxxx.plan.md`) resolve by unique stem / newest hash-twin under those folders. **CursorPlan** identity also matches equal inventory normalize stems (hash suffix stripped; date tokens kept) so a truncated stub and a full leaf are treated as one plan (preferred keeper: Active/Loom > Parked/Shipped > Idea; full leaf wins ties). Exact duplicate CursorPlan leaves on two Notion pages remain an identity conflict. **Pending** / **Done** are Cursor plan YAML todo counts (`pending` / `completed`; cancelled ignored). Sync heals Stage from Board and backfills Project/Subproject/Description/PlanPath/Pending/Done when blank or drifted. Operator: show Description and PlanPath on the By Stage view.

Existing Inbox/Backlog/Drop cards with no current Yarn/Loom signal keep that Board; sync only normalizes Stage. Identity match: CursorPlan first, else YarnId (Yarn-only card may gain CursorPlan). Split or duplicate identity is a conflict: skip both sides; never auto Drop.

### Inventory (Bing pack)

`plan-board inventory` scans Yarn backlog, `%USERPROFILE%\.cursor\plans\*.plan.md`, `_meta/plans\*.plan.md`, `_meta/docs\*.plan.md` (legacy), Loom queue paths, and existing cards. It writes `%LOCALAPPDATA%\Metra\yarn\plan-board-inventory.md` and `.json` (`schemaVersion` 2). Heuristics set `proposedDecision`; `decision` stays `review` until Bing/operator affirms. Zero Notion writes.

Pipeline: scan → per-row heuristic (status/language, then noise) → post-pass (hash twins, echo collapse, `clusterHint`) → pack. Heuristic stays local; cross-row work stays in post-pass.

**Noise (propose drop):** fixtures (`calibrate_a13_`), test cards (`Fail Test`, `Sync Test`, `PB Test`, smoke capture), Future-Dev index headings (Ladder, Sequencing rules, Open Cursor plans, …), module-scrap titles that mention a `*.ps1` file without a formal plan (including `Ask recommend (\`AskRecommend.ps1\`)`). **Shipped leftover / `shipped` plan docs propose Park** (archive). Plan headings/blurbs that say DONE, shipped, or closeout, and Cursor plan YAML (`status: Shipped|Complete`, `shippedAt`, or every todo `completed`) propose Park as `completed-unmarked`. Those stay documentation in the pack; `-Affirm drop,park` still will not create drop cards without a page. `-Affirm keep,park` creates Parked and Idea/Backlog cards from proposals. Park a finished cluster with `-AffirmCluster LoomYarn -As park`.

**Echo collapse:** same `echoKey` (normalized stem with trailing date tokens stripped) so `sprint_coworker_…_20260910` matches `sprint-coworker-…-2026-09`. Preference `loom` / `cursor-plan` / `meta-plan` > yarn-with-formal > yarn > meta-doc > notion. **Noise rows never win** an echo group. Losers append `echo-duplicate` (reason history preserved) and set `echoOf`. Hash-twin cursor plans (same stem, different `_xxxxxxxx` leaves): newest `LastWriteTime` wins; losers append `hash-twin-superseded` and set `supersededBy`.

**`clusterHint`:** Ask, iOS/Face, Routing, Inspect, Installer, OpsDesk, Ticket, LoomYarn, AtlasMemory, Persona, Personal, Other. Metadata only — inventory does not create parent Yarn items or Notion epics. Additive pack fields: `clusterHint`, `echoOf`, `supersededBy` (schemaVersion stays 2).

**Surface:** `plan-board inventory` writes `%LOCALAPPDATA%\Metra\yarn\plan-board-inventory.md` grouped by `clusterHint` (already on board / review to keep / drop / park) with a one-line blurb from the plan file when present. **Read that markdown.** Do not rate 197 JSON `decision` cells.

Batch apply (still requires `-Confirm`; `decision` in JSON may stay `review`):

```powershell
.\metra.ps1 plan-board inventory apply -Confirm -Affirm drop,park
.\metra.ps1 plan-board inventory apply -Confirm -Affirm keep,park
# Quote if the host splits commas: -Affirm 'keep,park'
.\metra.ps1 plan-board inventory apply -Confirm -AffirmCluster Ask
.\metra.ps1 plan-board inventory apply -Confirm -AffirmCluster "iOS/Face" -As park
.\metra.ps1 plan-board inventory apply -Confirm -AffirmNoise
```

`-Affirm drop,park` applies proposed drop (existing page only) and does not create. `-Affirm keep,park` creates/updates Idea/Backlog and Parked cards from proposals (skips echo-board-keep and echo-duplicate). `-AffirmCluster` applies that cluster (default uses `proposedDecision`; `-As keep|drop|park` overrides).

`apply -Confirm` with no `-Affirm*` still requires JSON `decision` keep/drop/park. Unknown `schemaVersion` or missing `-Confirm` attempts nothing. Drop of an existing card requires `notionPageId`. Inventory cannot approve Yarn or enqueue Loom.

Sync and apply summaries use a **stable public contract**: `scanned`, `proposed`, `applied`, `unchanged`, `skippedReview`, `skippedStale`, `identityConflicts`, `failed`, `notionUnavailable`. Rename only with a versioned migration.

## Authority

- `scan` upserts/ranks only (Capture + Future-Dev + Atlas Plan/Roadmap/Parked)
- `daily` is read-only unless `-Reconcile`
- `reconcile` may template-synthesize Capture items, pack ready-enough plans, and retry Loom handoff (pending|failed). Atlas has no Capture-style auto-synth exception.
- `yarn synthesize -FromMemory <stableId> -Confirm` is the explicit Atlas draft path (`atlas sync pull` never synthesizes)
- `yarn plan approve -Confirm` is the sole human approval path (requires pending-bing + fresh pack)
- Yarn never writes Loom queue/journal files; Loom `Invoke-MetraLoomIngestApprovedPlan` owns ingest
- Plan review / Pending Bing live here — not in Loom daily §3
- Atlas providers return data only (local mirror); Yarn never promotes OCC/Decisions from Atlas
- Plan Board never Approves or enqueues; sync never writes Yarn/Loom status from Notion

## Phase B (Atlas)

- Post-sync cache = Atlas local mirror (`data/sync/objects` + stub), not a Yarn content cache
- Backlog fields: `atlasStableId`, `memoryLane=atlas`, `atlasKind` (Plan|Roadmap|Parked)
- Offline: empty Atlas set; Capture/Future-Dev continue; status/daily show `memoryLane=paused`

## Related

Loom owns queue execution after handoff (A4: one active lane per `projectKey`, atomic claim, `accepted-pending-commit` + local commit verify). Verified accept also notifies Plan Board (Shipped). See [loom.md](loom.md). Slice 7 Phase C AutoProgram leftovers are closed (naming/docs only; alias/migrate stay in the Loom playbook).
