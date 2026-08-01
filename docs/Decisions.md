# Metra decisions

Append-only record of **portfolio-wide** Metra behavior choices. Newest first. Professional prose only - no chat persona voice.

**When to append:** a routing, persona, brand, hook, or registry policy choice that should stick across chats and machines.

**When not to append:** routine tickets, one-off code fixes, temporary experiments.

Entry shape:

```markdown
## YYYY-MM-DD - Short title

- Decision: ...
- Why: ...
- See: path or command
```

---

## 2026-08-01 - Knowledge coverage visibility (not a score)

- Decision: Ship knowledge coverage as **visibility only** via canonical helper `Get-MetraKnowledgeCoverage`. One present registry-on-disk population feeds every with/missing/uncovered dimension. Dimensions: AGENTS on disk, non-empty `serves`, and at least one **active confirmed** Decision Registry row (not candidates, not superseded). `Uncovered` means missing all three. Surfaces: `.\metra.ps1 coverage`, Ops Stewardship Gaps strip, and snapshot `coverage` (keep existing aggregate counts; add capped gap lists). Gap name lists are alphabetical, deduped, capped at 12; counts stay full. No percent, grade, or health score. Out of scope: decisions review/decay, cap-100, auto-filling serves/AGENTS.
- Why: Stewardship already showed aggregate coverage counts without listing AGENTS gaps or uncovered projects, and there was no CLI without the canvas. Operators need the gap names to tend knowledge without inventing a second scoring system.
- See: `scripts/private/Snapshot.ps1` (`Get-MetraKnowledgeCoverage`, `Write-MetraKnowledgeCoverage`), `.\metra.ps1 coverage`, `integrations/cursor/metra-ops-board.canvas.tsx.template`, `docs/Context-Routing.md`

## 2026-08-01 - Project story + related in ctx

- Decision: Surface registry **`related`** (reuse the existing field; do not add `relatedProjects`) and a bounded **project story** in `.\metra.ps1 ctx`. Story is a composition of existing metadata (`purpose`, `triggers`, `serves`, `related`, optional `whenPresent`) - no new registry story field and no generated prose. Canonical helper `Get-MetraRelatedProjects` preserves registry order, dedupes, drops unknowns, keeps same-root only, caps at 6, returns `{ Name, Present }`. Context pack and `routing -Name` / `-Query` primary consume that helper only. Related remains **topology, not permission** to multi-repo search.
- Why: Agents need portfolio topology at the stop pick without inventing memory soup or auto-opening neighbors. Registry stays authoritative; story regenerates deterministically.
- See: `scripts/private/Routing.ps1` (`Get-MetraRelatedProjects`), `scripts/private/Context.ps1`, `docs/Context-Routing.md`, `.\metra.ps1 ctx -Query "..."`

## 2026-08-01 - Public GitHub vs non-coder audience (deferred)

- Decision: Treat the **GitHub README / repo page as an operator and coder onboarding surface**, not the primary explainer for non-coders. Do not dilute the PowerShell-first README into plain-language marketing that fails both audiences. A **separate website** (or equivalent plain-language landing) is the planned home for non-coder understanding; that work is deferred, not in the current public-repo ship.
- Why: Non-coder review of the live GitHub page - a teacher with some technical skills found the language not meaningful across the whole page and overwhelming. Feedback concluded a separate website is probably essential for that audience. Concrete vocabulary gaps that needed live explanation: what **PowerShell** is, and what it means to **create a base folder** (checkout / `_metra` / project root). Those terms must not be assumed on the non-coder surface. When creating a home folder, the natural choice was **Documents** (not a developer `C:\Projects`-style root) - treat that as a valid personal-root default in non-coder guidance. **Git was not installed** - `git clone` is a hard stop for that audience; the non-coder path must offer get-Metra without installing Git. The ZIP workaround then hit a second wall: files extracted from a downloaded ZIP carry the Windows mark-of-the-web, so `RemoteSigned` refuses to run unsigned `metra.ps1` even after the documented `Set-ExecutionPolicy` step. Any no-Git path must cover unblocking (ZIP Properties -> Unblock before extract, or `Unblock-File`); the README `Set-ExecutionPolicy` line alone is only sufficient for a real `git clone`.
- See: `README.md`, [Brand.md](Brand.md) (public mark / GitHub), plan `github_public_audience_revision` (Cursor plans), operator index `docs/Future-Development.local.md` (Bucket A)
- Future / not in this release:
  1. Separate plain-language website (or landing) for non-coders - problem, value, and wayfinding without CLI/registry vocabulary; do not lead with PowerShell or "create a base folder" as assumed knowledge; if a home folder is needed, prefer **Documents** (or equivalent user-known place) over developer project roots; **get Metra without Git** (ZIP as interim; an **actual installer** is required for the durable non-coder path - installer should place files, avoid mark-of-the-web friction, and not require the user to understand PowerShell execution policy)
  2. Keep GitHub README operator/coder-dense; optionally add a short "Who this page is for" pointer to the non-coder site when it exists; add an operator README note that ZIP download is supported for machines without Git **and requires unblocking** (mark-of-the-web vs `RemoteSigned`) until the installer replaces that path
  3. Re-test the non-coder surface with a similar reviewer profile before calling it done
  - Out of scope for that revision: rewriting Metra itself into a non-technical product; family/classroom ticketing (TicketTracker); persona add-ons as a substitute for plain docs; requiring Git for first-run non-coder setup; treating manual ZIP + Unblock as the final non-coder deploy story

## 2026-07-31 - Metra Ops as one interchange (retrieval surface)

- Decision: Keep **one** Metra Ops canvas with three tabs organized around operator questions: **Route** (default - classify request and hand off Where/What/Why/For whom/Next), **Portfolio** (what needs attention), **Stewardship** (what knowledge needs tending, including a compact Portfolio Operating Model card). The board **retrieves from existing homes rather than becoming a new home** - routing registry, Decision Registry, OCC, audit/verify stay canonical; the canvas is read-only for durable portfolio state. Route scoring in the board is a labeled preview of PowerShell routing; authoritative Why Here remains `routing -Query` / `ctx -Query`. Quick snapshots must mark git/verify as not checked rather than healthy zeroes.
- Why: The first Ops board reported on Metra as a health dashboard. The operating model now needs a UI that *is* Metra - route before execute, illuminate homes, tend knowledge - without inventing a competing editor or second scoring system.
- See: `integrations/cursor/metra-ops-board.canvas.tsx.template`, `scripts/private/Snapshot.ps1`, `docs/Context-Routing.md`, `docs/Brand.md`

## 2026-07-31 - Route-mark identity (paths and hubs)

- Decision: Keep the public Metra mark as a teal three-node route with an open labeled center interchange ([`docs/assets/metra-mark.svg`](assets/metra-mark.svg)). Terminal nodes stay the same Signal Teal family as the line - no blue/amber/multicolor endpoints. Brand story stays short: Metra connects endpoints; the open center is classification before work moves on. Future operator-facing chrome prefers paths, nodes, routes, connections, hubs - not brains, robots, assistants, or mascots. Documented in [Brand.md](Brand.md) Motif.
- Why: The geometry already matches portfolio operations (route → classify → continue). Extra endpoint colors and AI cliches dilute a mark that is unusually aligned with the product without needing a post-hoc story.
- See: `docs/assets/metra-mark.svg`, `docs/Brand.md`, README header image

## 2026-07-31 - For whom? (project serves)

- Decision: Ship **For whom?** as optional project-registry `serves` (`string[]`), same shape as `triggers` / `capabilities`. Audience of the work (roles, teams, consumer systems), never people memory - portfolio memory, not CRM. Surfaces: `routing -Name` / `routing -Query` print a **For whom?** question block when non-empty (before Why Here); `ctx` includes `serves` in JSON and markdown (`- serves:` per project; `## For whom?` for query primary). Full `routing` table stays quiet. Seed shared stubs TicketTracker and Solarwinds. Why Here stays Decision Registry; serves stays project registry (do not stuff audiences into the Decision Registry). v1 is plain strings only - no `{ name, kind }` objects.
- Guardrail: Metra may describe audiences served by work. Metra does not maintain memory of individuals, requesters, owners, approvers, performance history, or interpersonal relationships. Ticket requester facts stay in TicketTracker evidence when needed.
- Why: Completes the homes map without inventing people-profiling Who. Stable role/team audiences teach the portfolio at route time.
- See: `projects.json` (`serves`), `Write-MetraForWhom`, `.\metra.ps1 routing -Name Solarwinds`, `docs/Context-Routing.md`
- Future: structured `{ name, kind }` only if string[] proves too weak; Decision Registry `for` remains out of scope until needed

## 2026-07-31 - Portfolio Operations Principles

- Decision: Adopt an explicit **portfolio operations** operating model for Metra. Lead rule: **every portfolio fact should have a home.** Homes map (operator cheat sheet; does not replace the marketed product triangle of routing + context + communication):

  | Question | Home |
  |---|---|
  | Where? | Routing registry / `.\metra.ps1 routing` |
  | What? | Context / `ctx`, project `AGENTS.md` |
  | Why? (operational scars) | Decision Registry + Why Here |
  | Why? (product policy) | `docs/Decisions.md` |
  | How? (collaboration rhythm) | OCC / `profile` + communication model / professional sink |
  | Health? | Ops board / `audit` / `verify` / status |
  | For whom? | Project registry `serves` / `routing` / `ctx` (not people profiling) |

  Operating principles: (1) every portfolio fact has a home; (2) route before execute; (3) context is retrieved, not dumped; (4) decisions are preserved with rationale (ledger why + confidence + evidence; never invent operational why); (5) communication follows the same operating model as the tooling. Health is first-class for ops but is not a fourth marketing triangle leg. Metra overlaps portfolio management, knowledge management, and configuration-management ideas; it is an operating model for developers and agents, not a single Wikipedia discipline. Boundaries: product policy -> Decisions.md; operational scars -> Decision Registry; collaboration rhythm -> OCC; project-local guidance -> that project's `AGENTS.md`.
- Why: Portfolio chaos is usually information with no obvious home. Naming the model keeps future features (relationships, Ops board wisdom) from inventing parallel homes or dumping wiki-scale knowledge into prompts.
- See: `README.md` (Portfolio operations homes), Why Here / For whom / Decision Registry / OCC / product-triangle entries in this file
- Future: see Why Here entry (relatedProjects, Ops board wisdom, and related items) - do not duplicate that list here

## 2026-07-31 - Why Here? routing explanations

- Decision: Ship **Why Here?** as ledger-backed routing explanations attached when a primary stop is named or query-picked. Private helpers `Get-MetraWhyHere` / `Write-MetraWhyHere` / `Write-MetraWhyNot`; `Search-MetraDecisionRegistry -Project` scopes hits. Surfaces: `.\metra.ps1 routing -Name` (Why Here per present named project), `.\metra.ps1 routing -Query` (primary + Why Here; close runner-up + Why not), `ctx -Query` (markdown `## Why here?` / optional `## Why not?`; JSON `whyHereFor`, `relatedDecisions`, optional `whyNotFor` / `runnerUpDecisions`). Full `routing` table without Name/Query stays an index with no Why Here dump. Confidence shown only when not `high`. Ambiguity when score gap ≤ 1 or runner-up ≥ 50% of primary (primary ≥ 2). Persona may cite ledger Why Here / Why not; never invent operational why. No always-on decisions rule.
- Why: Portfolio knowledge should appear as Why? at the moment of the stop pick, not as a separate hunt or model-generated lore.
- See: `.\metra.ps1 routing -Name TicketTracker`, `.\metra.ps1 routing -Query 'gateway msal'`, `scripts/private/DecisionRegistry.ps1`, `scripts/private/Routing.ps1`
- Future / not in this release:
  1. ~~Why Here?~~ **Done** (this entry)
  2. ~~Ops board Recent Decisions / Portfolio Wisdom~~ **Done** - Stewardship tab on Metra Ops interchange (bounded strip; board remains a retrieval surface)
  3. ~~Knowledge coverage visibility (not a score)~~ **Done** - see Knowledge coverage visibility entry
  4. ~~Project story + relatedProjects in ctx~~ **Done** - see Project story + related in ctx entry
  5. decisions review (knowledge decay)
  6. Cap headroom toward 100 if retrieval stays useful
  7. ~~**For whom?**~~ **Done** - see For whom? (project serves) entry
  - Deprioritized: more persona add-ons; more Ops board health metrics
  - Operator parking-lot index (gitignored): `docs/Future-Development.local.md`; Cursor plan `metra_future_development_buckets`

## 2026-07-31 - Decision Registry (Operational Why Memory)

- Decision: Ship an operator-private **Decision Registry** for operational why-we-chose memory, separate from `docs/Decisions.md` (product policy) and the Operator Communication Contract (collaboration rhythm). Ledger is gitignored `docs/decision-registry.json` (`candidates` + `confirmed`). Flow: note/harvest -> promote; never auto-promote. Required on promote: non-empty `why`, `confidence` (`high`|`medium`|`low`), and at least one `evidence` item. Also store `source` and `origin` (`operator`|`backfill`|`harvest`). Cap 50 active confirmed. Retrieved only via `.\metra.ps1 decisions search|get` and bounded `ctx -Query` top 3 `relatedDecisions` - no always-on `.mdc`. CLI also includes `harvest` (candidates only from project `AGENTS.md`) and `seed` (curated local backfill). Travels with `export-profile` / `import-profile`. Boundary test: would every Metra clone benefit? If yes, use Decisions.md instead.
- Why: Institutional operational scars had no home that was neither routing, personality, nor product docs. Explicit promote plus retrieval-only load keeps trust and avoids memory soup in every prompt.
- See: `.\metra.ps1 decisions`, `docs/decision-registry.example.json`, `scripts/private/DecisionRegistry.ps1`
- Future: see Why Here entry (item 1 done); remaining relationship-surfacing items listed there.

## 2026-07-31 - One generated workspace file

- Decision: `workspace.outputs` ships a single entry: `Metra.code-workspace` inside the Metra checkout (`metraFolderPath: "."`, `projectPathPrefix: "../"`). Do not generate a second copy beside the projects root. The generated file is gitignored; the tracked starter is `Metra.code-workspace.example`. Fresh clones run `.\metra.ps1 setup`, which writes the real workspace locally.
- Why: Two generated copies split Cursor chat history, because Cursor tracks agent transcripts per workspace identity. The second copy also collided with a tracked starter of the same name, so a routine `git` restore silently reverted a generated workspace back to the Metra-only sample and dropped the operator's sibling folders. One generated, gitignored output keeps chat context stable and keeps real project names out of the repo.
- See: `metra.config.example.json`, `profiles/sample/metra.config.json`, `.gitignore`, `Update-MetraWorkspace`

## 2026-07-31 - Operator Communication Contract

- Decision: Ship an **Operator Communication Contract** for the shared operating rhythm between Metra and the operator (how we collaborate - soft working guidelines), not a user profile or hidden memory. Ledger is gitignored `docs/operator-contract.json` (`candidates` + `confirmedGuidelines`). Always-on load is gitignored `.cursor/rules/metra-learned.local.mdc` rendered as a confirmed soft-guideline list plus a fixed Interpretation footer - no auto-generated prose brief. Flow: candidate -> propose -> confirm -> promote; never auto-promote. Hard cap 20 confirmed guidelines. Portfolio-wide corrections (routing, professional sink, root isolation, evidence hierarchy, public product framing, base persona policy) must refuse personal promote and point at Decisions / README / base persona instead. CLI: `.\metra.ps1 profile` (private helpers; no new public module export). Travels with `export-profile` / `import-profile`. Base policy always wins on conflict.
- Why: Communication discipline that never evolves feels fake across sessions and model swaps. Explicit promotion and a deterministic guideline list keep trust inspectable without hidden memory or interpretation drift from synthesized briefs.
- See: `.\metra.ps1 profile`, `docs/operator-contract.example.json`, `.cursor/rules/metra-learned.local.example.mdc`, `docs/Customizing-Metra.md`

## 2026-07-31 - Product triangle: routing + context + communication

- Decision: Market and document Metra as **routing + context + communication discipline** - one operating model, not "CLI plus a persona feature." Prefer the terms **communication model** / **communication discipline** over repeating "communications surface/layer/voice/adapter." Surface the **professional sink** early (chat may have voice; tickets, commits, ADRs, and handoffs do not). Include a clear "Why not just use a coding agent?" differentiation. Refine earlier peer-surface wording: ops still means PowerShell routing/context tooling; the persona is the communication half of the same workflow, framed as capability rather than character.
- Why: External README review - the differentiator is treating communication as part of the operating model. Risk is visitors reading Metra as "just another PowerShell toolkit," not "too much persona."
- See: `README.md`, earlier Decision "Ops and communications are peer product surfaces"

## 2026-07-30 - Operator-private cloud continuity

- Decision: Cross-device Cursor Cloud Agent continuity is **operator-private**, not a shared Metra product surface. Do not teach it in README, Demo, or Integrations. Optional code may stay in-tree but must stay inert without a personal API key; how-to belongs in gitignored `docs/*.local.md`. Shared product still owns the brainstorm-vs-implement persona rule and local `chats`.
- Why: Personal Cursor account wiring and API keys do not travel cleanly with coworker or public clones.
- See: `.gitignore` (`docs/*.local.md`)

## 2026-07-30 - Ops and communications are peer product surfaces

- Decision: Treat Metra as two peer product surfaces: **ops** (`metra.ps1`, module, registries, `ctx`) and **communications** (Metra chat persona, Teaching Mode, professional artifact sink). Do not describe the persona as optional garnish, "not the product," or merely riding on the CLI. Routing and root isolation still win over personality for folder choice. Cursor remains the nicest auto-load adapter; CLI-only operators still get full ops value without persona chrome.
- Why: The persona is how Metra communicates during agent sessions - route-first voice, Teaching Mode delivery, and a clear split between chat tone and durable professional writes. Demoting it undercuts that half of the product while over-correcting against "AI project with scripts bolted on."
- See: `README.md`, `.cursor/rules/metra-persona.mdc`, `docs/Customizing-Metra.md`

## 2026-07-30 - Product framing: PowerShell first

- Decision: Position Metra as a PowerShell product with an AI integration layer, not an AI project with PowerShell tooling. Primary ops surfaces are `metra.ps1`, the importable module (`scripts/Metra.psd1`), registries, and `ctx` packs. Cursor persona auto-load, Teaching Mode, and transcript search are first-class product surfaces for communications (refined in "Ops and communications are peer product surfaces") - not Cursor-only theater.
- Why: A curated CLI and module surface serves CLI operators, PowerShell users, portfolio operators, and AI users. Framing Metra as Cursor-only shrinks the audience and undercuts the module / setup / help work.
- See: `README.md`, `scripts/Metra.psd1`, `docs/Integrations.md`

## 2026-07-30 - Curated exports and Get-Help docs sink

- Decision: Treat the 17 supported `*-Metra*` commands in `scripts/Metra.psm1` (`$script:MetraPublicFunctions`) as the public API. Prefer extending an existing public command or a private helper over adding an 18th export. Comment-based help on those commands is the source of truth for parameters, examples, and outputs (`Get-Help <command> -Full`). README and workflow docs stay example-oriented; do not hand-maintain a parallel API markdown reference. Compatibility exports and `*-Meta*` aliases remain one-release only and are not taught as the product surface.
- Why: Each new export is a stability commitment. Curated surfaces stay discoverable; duplicated docs drift. External review confirmed this boundary after the public/private split.
- See: `scripts/Metra.psm1`, `scripts/Metra.psd1`, `scripts/public/`, `README.md` (PowerShell-native commands)

## 2026-07-30 - Public/private PowerShell module split

- Decision: Keep one Metra module but split implementation by domain under `scripts/private/` and supported commands under `scripts/public/`. `Metra.psm1` is a thin loader with an explicit 17-command public list. Full comment-based help lives on supported public commands. Existing implementation exports and former `*-Meta*` aliases remain one-release compatibility surfaces only.
- Why: The single module reached 3,300 lines and mixed supported commands with implementation helpers. Domain files improve maintenance, while an explicit manifest and `Get-Help` boundary make the CLI usable without creating multiple submodules or duplicated reference docs.
- See: `scripts/Metra.psm1`, `scripts/Metra.psd1`, `scripts/public/`, `scripts/private/`

## 2026-07-30 - PowerShell-native command surface

- Decision: Keep `metra.ps1` as the shell-friendly dispatcher and also ship an importable `scripts/Metra.psd1` module with approved verb-noun commands such as `Get-MetraProject`, `Get-MetraRouting`, and `Export-MetraContext`. Complete dynamic `-Name` and `-Root` values from the configured portfolio.
- Why: Command-line-oriented operators expect PowerShell command discovery, parameter binding, help, and Tab completion. Thin wrappers preserve one implementation underneath both interfaces.
- See: `scripts/Metra.psd1`, `scripts/Metra.psm1`, `README.md` (PowerShell-native commands)

## 2026-07-30 - setup command and work-only example config

- Decision: Ship `.\metra.ps1 setup` as one-shot onboarding (seed `metra.config.json` from example when missing, optional `-Profile`, roots gloss, workspace regenerate, routing, ctx). Example and sample configs use a work root only; personal/cloud roots are documented snippets (iCloud, OneDrive, generic) in Customizing-Metra - never vendor-detect. Existing local config is never overwritten by the example; `-Force` applies only to profile import.
- Why: Fresh clones hit execution policy, missing config, unexplained routing/ctx, and roots-vs-workspace confusion as separate steps. An iCloud personal root in the example was noisy on machines without iCloud.
- See: `Invoke-MetraSetup`, `README.md` Quick start, `docs/Customizing-Metra.md`

## 2026-07-30 - CLI / module / config rename to Metra

- Decision: Canonical names are `metra.ps1`, `scripts/Metra.psm1`, `*-Metra*` functions, `metra.config.json`, `metra-profile.json`, and workspace keys `metraFolderName` / `metraFolderPath`. Docs and rules teach only those names. Silent one-release compatibility: `meta.ps1` shim, config/profile filename fallbacks, `metaFolder*` dual-read, and exported `*-Meta*` aliases. Live checkout folder may stay `_meta` (Cursor state). Remove shims in a later pass after muscle memory settles.
- Why: Product, persona, canvas, and recommended folder already said Metra; keeping `meta.*` trained two brands.
- See: `metra.ps1`, `meta.ps1`, `scripts/Metra.psm1`, `docs/Brand.md`

## 2026-07-30 - Recommended checkout folder `_metra`

- Decision: Recommended local checkout name is **`_metra`**. Still accepted: `_meta`, `Metra`, `metra` (and legacy `meta`). `Test-MetraSelfFolderName` recognizes all of them. Do not require renaming an existing `_meta` live checkout.
- Why: Leading underscore keeps orchestration at the top of the sibling list; `_metra` matches the product name better than `_meta` without losing that sort behavior.
- See: `README.md` (Naming), `Test-MetraSelfFolderName`, `docs/Brand.md`

## 2026-07-30 - Ship teaching-gentle Persona Add-on

- Decision: Ship `profiles/addons/teaching-gentle/` as the second Persona Add-on. Installs `metra-teaching-gentle.local.mdc`. Activates gentler pacing only when the operator explicitly requests kid/family/beginner/educational or teaching-gentle mode - never infer audience. While active, suppress humor-desk sarcasm. `Get-MetraProfileFileMap` includes the new local rule path.
- Why: Family / educational Cursor sessions need a shareable tone dial without baking audience assumptions into base Metra.
- See: `profiles/addons/teaching-gentle/`, `profiles/addons/README.md`

## 2026-07-30 - Persona Add-ons: tone only (Bing guardrail)

- Decision: Public name is **Persona Add-ons** (`profiles/addons/`). They may alter chat tone only. They may not alter routing, project selection, root isolation, evidence hierarchy, professional artifact rules, or incident handling defaults. Changes that need those behaviors belong in a base-rule discussion. Rename deferred dial `children-friendly` to `teaching-gentle` (style, not audience); apply only when the operator explicitly requests kid/family/beginner/educational mode - never infer. Humor-desk: humor is additive, not substitutive. Defer `list-addons` / `disable-addon` CLI; import = install, delete local rule = remove. Keep README ops-first; document add-ons under customization, not as the product hero.
- Why: Clean split (base = policy, overlay = identity, add-ons = optional preferences) matches the routing-registry pattern and prevents persona soup and ops-first dilution.
- See: `profiles/addons/README.md`, `docs/Customizing-Metra.md`, earlier Decision "Optional persona add-on packs (humor-desk first)"

## 2026-07-30 - Optional persona add-on packs (humor-desk first)

- Decision: Ship optional persona dials as `profiles/addons/<id>/` packs that import into gitignored `.cursor/rules/*.local.mdc` files. Public base `metra-persona.mdc` stays lean. First pack: `humor-desk` (desk-partner humor palette). `Get-MetraProfileFileMap` includes `.cursor/rules/metra-humor.local.mdc` so import/export can carry it. Further packs only when someone would actually import them.
- Why: Operators want louder chat tone without forcing it on every clone or bloating always-on base. Same install path as sample profile; easy to remove by deleting the local rule.
- See: `profiles/addons/README.md`, `profiles/addons/humor-desk/`, `docs/Customizing-Metra.md`

## 2026-07-30 - Keep Metra.psm1 single-file for public v1

- **Superseded** by [Public/private PowerShell module split](#2026-07-30---publicprivate-powershell-module-split). Kept for history.
- Decision: Keep `scripts/Metra.psm1` as one module for public v1. Split internally by operational concern (Core, Projects, Registry, then Context/Audit/Profile/Workspace) only when feature velocity or contributor readability requires it. Public function names stay stable; do not split by line count alone.
- Why: The file is large but coherent as one CLI surface. Premature multi-file layout turns maintenance into a scavenger hunt - the problem Metra exists to avoid.
- See: `scripts/Metra.psm1`, `Export-ModuleMember`, `SECURITY.md` (`run` trust boundary)

## 2026-07-30 - Public README: 90-second + Why Metra

- Decision: Keep a short "90-second understanding" and a brief "Why Metra?" near the top of `README.md`. Full Origin stays in `docs/Customizing-Metra.md`. Do not grow Teaching Mode into prompt coaching, skill levels, quizzes, or reflection loops.
- Why: First-time GitHub visitors need the portfolio/routing story before dense CLI tables. Teaching Mode must stay delivery changes for getting work done - not a second educational product.
- See: `README.md`, `docs/Customizing-Metra.md` (Origin), `.cursor/rules/metra-persona.mdc`

## 2026-07-30 - Quiet verify smoke

- Decision: `.\metra.ps1 verify` uses quiet `ctx` (`-Path -`) and quiet `import-profile -Preview` so fixture smoke does not rewrite `docs/context-pack.*` or spam host output. Focused Pester under `tests/` covers routing rows, import refuse/Preview, quiet ctx, and verify Ok.
- Why: Smoke should be pass/fail without mutating generated packs or drowning the result table.
- See: `Invoke-MetraVerify`, `tests/Invoke-MetraTests.ps1`, `docs/Routing-Scenarios.md`

## 2026-07-30 - Routing fixture smoke via verify

- Decision: Prefer `.\metra.ps1 verify` for Routing-Scenarios fixture checks. Keep the raw PowerShell list in that doc as the human-readable source of truth for what verify covers. Exit `0` with WARN-only; exit `1` on any FAIL.
- Why: Agents need structured PASS/WARN/FAIL instead of eyeball-only smoke.
- See: `docs/Routing-Scenarios.md`, `Invoke-MetraVerify`, `.\metra.ps1 verify`

## 2026-07-30 - Origin note off the always-on hot path

- Decision: Keep a short Metra origin / operating-philosophy note in `docs/Customizing-Metra.md` (Origin). Do not paste the full essay into `.cursor/rules/metra-persona.mdc`.
- Why: Always-on already encodes routing, evidence, incident tone, humor, and Teaching Mode as compact behaviors. The origin text explains those habits for onboarding and continuity without paying token cost every turn or inviting lore growth.
- See: `docs/Customizing-Metra.md` (Origin), `.cursor/rules/metra-persona.mdc`

## 2026-07-29 - sessionStart Ops refresh without workspace rewrite

- Decision: On agent chat `sessionStart`, refresh the Ops board with `snapshot -Quick` only when the snapshot is stale (age > 4h or registry/config newer). Never auto-run `workspace` from that hook.
- Why: Full snapshot is slow; rewriting `Metra.code-workspace` can reload Cursor mid-session. Stale-gated Quick keeps board truth without desk churn.
- See: `.cursor/hooks/session-snapshot.ps1`, `docs/Integrations.md`, `.\metra.ps1 snapshot -Quick`

## 2026-07-29 - Dual-mode brand without a Cursor skin

- Decision: Metra Ops follows host theme tokens (`useHostTheme()`). Brand kit (Signal Teal / Mist / Amber) is intent documentation; optional local `colorCustomizations` may push teal into host accent. No full Cursor theme extension.
- Why: Thin product boundary; coworkers keep their own IDE theme; light and dark both first-class.
- See: `docs/Brand.md`

## 2026-07-29 - Plain English over slash commands

- Decision: Prefer natural-language asks. Do not ship slash commands (`/triage`, `/route`, `/snapshot`) as the primary workflow for this operator.
- Why: Shortcuts help humans who remember them; always-on rules and `AGENTS.md` already encode the procedures for the agent.
- See: `docs/Integrations.md`

## 2026-07-29 - Chat first person; professional sink for artifacts

- Decision: Chat body uses I/we (banner still names Metra). Tickets, commits, ADRs, and redistribution drafts stay ordinary professional prose with no Metra voice.
- Why: Coworker tone in chat without polluting iSupport or git history.
- See: `.cursor/rules/metra-persona.mdc`, `AGENTS.md`

## 2026-07-29 - Product naming

- Decision: Product name is **Metra**. Recommended checkout folder was `_meta` at the time (later updated to `_metra`; see 2026-07-30 Decision). Also accepted: `Metra`, `metra`. CLI was still `meta.ps1` at the time (renamed later; see 2026-07-30 CLI rename Decision). Do not rename the live folder for branding.
- Why: Branding without breaking paths, remotes, or Cursor state slugs.
- See: `docs/Brand.md`, `README.md`

## 2026-07-31 - Ops home answers next and resolve

- Decision: Make the Route home answer two operator questions first: what needs attention next, and where to resolve the current issue. Show a capped, prioritized queue with one next command per item beside the request classifier. Keep project inventory and operating-model evidence in Portfolio and Stewardship. Do not treat workspace pinned folders as routing favorites.
- Why: The board is an operator work surface and Metra faceplate, not a telemetry wall. Wayfinding is the product identity: surface real work, classify the issue, and hand off to the existing home without inventing a second durable store.
- See: `integrations/cursor/metra-ops-board.canvas.tsx.template`, `docs/Brand.md`, `docs/Integrations.md`

## 2026-07-31 - Ask Metra preferred over terminal paste

- Decision: On Resolve this, lead with issue-specific summary/detail/done-when. Prefer Ask Metra (`newComposerChat`) so the agent continues the work in chat. Offer Copy for terminal as the optional self-serve path. Do not put command/copy controls on Needs attention rows - Resolve opens the briefing instead.
- Why: Operators were unsure whether the board expected paste-into-terminal or agent handoff. Metra's face is wayfinding into chat or CLI homes, not a command wallpaper.
- See: `integrations/cursor/metra-ops-board.canvas.tsx.template`, `docs/Brand.md`

## 2026-07-31 - Route home stays useful when the queue is clear

- Decision: When Needs attention is empty and no query is typed, the Route home shows Standing routes (default entry plus pinned present projects) that open the normal handoff, and the empty queue explains why it is empty with a full-snapshot re-scan action.
- Why: A clean portfolio left the home blank, which read as a broken board. Standing routes restore direct access to working homes without reviving pinned hubs as a routing signal.
- See: `integrations/cursor/metra-ops-board.canvas.tsx.template`, `docs/Brand.md`

## 2026-07-31 - Demo is face-first (Ops board before chat prompts)

- Decision: Coworker demo leads with Metra Ops Route (Needs attention / Resolve this / Standing routes), then the routing CLI table, then Trivia chat + professional-sink draft. Rename `Demo-5min.md` to `Demo.md` (recommended ~8 min; keep a strict 5-minute cut). Do not demo Canva/MCP, Decision Registry, OCC, personal roots, or live ticket posts in the default talk.
- Why: The Ops board is the product face for wayfinding; a chat-first script under-taught the desk and over-taught an AI primer.
- See: `docs/Demo.md`, `docs/Brand.md`, `docs/Integrations.md`

## 2026-07-31 - MCP tool bindings are documented pointers, never tracked credentials

- Decision: External agent tool connections (first case: the Canva remote MCP server) are per-machine harness bindings. Metra tracks a URL-only `integrations/cursor/mcp.example.json` plus a table in Integrations; live `.cursor/mcp.json` is gitignored, and entries carrying `headers` / tokens / API keys stay local. Bindings are optional - when a server is absent, say so rather than inventing a workflow. Profile-pack syncing of `mcp.json` is deferred until a secrets guard exists.
- Why: The connection that matters is a pointer plus per-user OAuth, so sharing it costs nothing and grants nothing. Shipping live config would either leak keys or hand forks an authorization prompt for a subscription they do not have.
- See: `docs/Integrations.md`, `integrations/cursor/mcp.example.json`, `SECURITY.md`

## 2026-07-31 - workspace.exclude keeps folders routable but unmounted

- Decision: `metra.config.json` `workspace.exclude` drops named projects from the generated `Metra.code-workspace` while leaving them in the routing registry. Document the key in Customizing-Metra; ship an empty array in `metra.config.example.json`.
- Why: Frozen review checkouts (for example Metra-Bing-Review) need to stay discoverable without loading a stale `AGENTS.md` as an always-applied Cursor rule in the live workspace.
- See: `scripts/public/Workspace.ps1`, `docs/Customizing-Metra.md`, `metra.config.example.json`
