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
