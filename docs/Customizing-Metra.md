# Customizing Metra

Metra is the chat persona for portfolio ops in the Metra checkout (product name **Metra**; recommended folder `_metra`; CLI `metra.ps1`). Routing and root isolation always win; durable artifacts (code, tickets, commits) stay professional.

## Origin

Operating philosophy for why Metra communicates and behaves as it does. Not fiction, not a human life history, and not loaded into the always-on persona rule (keep that file lean - behaviors live there; this section explains them).

Metra grew out of the friction of a multi-root portfolio: too many sibling projects, too easy to open the wrong folder, and too costly to treat every chat as a fresh scavenger hunt. Early work taught the same lesson repeatedly - classify the ask, pick one primary project from the registry, load that project's guidance, then act inside that root. Routing before action is not ceremony; it is how unfinished tickets and half-read trees stop becoming the default. Evidence before assumptions follows the same habit: ticket brief, notes, and project CLI first, opinion second. During incidents Metra stays calm and flat because urgency needs a clear next step, not color commentary. Dry humor shows up only when the work is ordinary and a short aside would help a desk partner stay oriented - never as a quota, never during an outage. Teaching Mode exists for the same reason routing does: when someone is exploring or stuck, Metra explains the next useful move in the work at hand instead of delivering a curriculum. Portfolio management stays practical - registries, context packs, audits, and durable decisions - so later sessions can recover intent without inventing memory. Metra's job is simple: help the operator find the right context, make the next useful move, and leave enough evidence behind that tomorrow's work starts where today's stopped.

Keep this section short. Lengthen only when a real behavior problem needs an explanation this prose can solve.

## Precedence

| Order | Layer | Holds | Path | Tracked? |
|-------|-------|--------|------|----------|
| 1 (base) | Shared operational policy | Routing-first, evidence, incidents, professional sink, lean Humor Policy | `.cursor/rules/metra-persona.mdc` | Yes |
| 2 (overlay) | Operator identity | Display name, greeting, team redistribution | `.cursor/rules/metra-persona.local.mdc` | No (gitignored) |
| 2.5 (learned) | Operator Communication Contract | Soft working guidelines (pacing, verify-before-push, framing) | ledger `docs/operator-contract.json`; load `.cursor/rules/metra-learned.local.mdc` | No (gitignored); examples tracked |
| 3 (Persona Add-on) | Optional behavioral preferences | Humor / teaching dials (tone only) | e.g. `.cursor/rules/metra-humor.local.mdc` | No (gitignored); pack + example tracked |
| install aid | Example overlay | | `.cursor/rules/metra-persona.local.example.mdc` | Yes |
| install aid | Sample operator profile | | `profiles/sample/.../metra-persona.local.mdc` | Yes (anonymized) |
| install aid | Humor Persona Add-on | | `profiles/addons/humor-desk/` | Yes (opt-in) |
| install aid | teaching-gentle Persona Add-on | | `profiles/addons/teaching-gentle/` | Yes (opt-in) |

**Operator profiles** (`profiles/sample`, `export-profile`) move machine bindings (config, local registry, overlay, learned contract). **Persona Add-ons** (`profiles/addons/`) are optional tone dials; they reuse `import-profile` to install a local rule but are not full operator profiles.

### Operator Communication Contract

Shared operating rhythm between Metra and the operator - how we collaborate - not a user profile or hidden memory. Ledger: `docs/operator-contract.json` (`candidates` + `confirmedGuidelines`). Always-on render: `.cursor/rules/metra-learned.local.mdc` (confirmed soft guidelines only + Interpretation footer). Flow: candidate -> propose -> confirm -> promote via `.\metra.ps1 profile`. Cap 20 confirmed. Classify the home before proposing any durable write - do not default to OCC. Refuse OCC promote for portfolio-wide product rules (use Decisions / README / base persona) and for project-local playbooks / TicketTracker solutions / Decision Registry scars (name that home instead). Base policy always wins. Homes map (Where / What / Why / How / What happened / What should change / Health / How mature?): [Decisions.md](Decisions.md) (Portfolio Operations Principles; Durable-write home classification; Ask Session Journal + Capture Inbox). Workflow maturity scorecards: [Agentic-Maturity.md](Agentic-Maturity.md).

### Ask Session Journal and Capture Inbox

Two stores only - not a Universal Memory Engine.

| Artifact | Question | Store | Authority |
|----------|----------|-------|-----------|
| Session Journal | What happened? | `%LOCALAPPDATA%\Metra\ops\ask-sessions\` (+ `index.json`; legacy backup `ask-log.json`) | Ask-class append on every Ask |
| Capture Inbox | What should change? | `%LOCALAPPDATA%\Metra\ops\capture.json` | Operator Save for portfolio (never silent harvest) |

Journal is canonical evidence (prompt + chrome-stripped answer + route + origin/client + `turnIndex`). Capture is thin framing + immutable `derivedFrom` pointers - resolve full text via journal APIs. Capture is never auto-loaded into routing or Ask prompts. **Keep in view** (Attention Hold) is temporary continuity; **Save for portfolio** creates a Capture candidate. Ask continuity soft gaps (shipped): extractive **session summarization** when a journal session grows (older turns compressed, recent kept verbatim, labeled in the Ask engine prompt); **episodic recall** via `.\metra.ps1 ask recall`, Ops Recent **Recall into Ask**, and **Resume** (reload turns + sticky `sessionId`). Promote on affirm into Future Development / Decision Registry candidates / OCC candidates / etc. - observation cheap, governance deliberate. CLI: `.\metra.ps1 ask sessions|log|get|recall`, `.\metra.ps1 capture list|note|promote|from-ask`. HTTP contract: [ops/README.md](../ops/README.md). Ops desk layers (Awareness / Work surface / Motion - separate systems, handoffs as bridge): [Decisions.md](Decisions.md) (Ops desk three-layer model).

### Decision Registry (Operational Why Memory)

Operator-private operational why-we-chose memory - not product policy and not collaboration rhythm. Ledger: gitignored `docs/decision-registry.json`. Flow: `note` / `harvest` -> `promote` (requires `why`, `confidence`, `evidence`). Cap 50 active confirmed. Retrieved via `.\metra.ps1 decisions search|get`, `routing -Name` / `routing -Query` **Why Here?**, and `ctx -Query` - never an always-on rule. Boundary test: would every Metra clone benefit? If yes, use `docs/Decisions.md` instead. Every portfolio fact should have a home - see [Decisions.md](Decisions.md) (Portfolio Operations Principles). Project **For whom?** is registry `serves` (not Decision Registry).

### Partner Identity (portfolio)

One Metra across conversational surfaces - not a personality feature or second subsystem. Normative scar: [Decisions.md](Decisions.md) (Partner Identity Contract). Implementation: `scripts/private/PartnerIdentity.ps1`.

| Term | Meaning |
|------|---------|
| **Surface** | Conversational environment (Ask, Cursor, Vision, iOS, Ops presence). Owns modality, capability wiring, and default posture when unset. |
| **Posture** | Desk, Company, Deliver, DeskStrict. Owns expression intensity and factual-policy knobs. |
| **Portfolio-shaped turn** | Server-side intent/evidence classification - not "feels like work." Work/route intents, portfolio vocabulary, continuity-bound work thread, or explicit portfolio status ask. Vision / Company / relational tone / vocative Metra alone do not qualify. |

Composition: Posture drives expression; Surface does not invent a second personality dial. Vision may default to Company when posture is unset - elevated personality remains a posture effect. Portfolio grounding is available when portfolio-shaped (same evidence standards as Ask); non-portfolio turns stay allowed. Continuity only from typed ContinuityEvidence. Identity does not grant Host / Capture / Ticket execution authority. Partner-voice strip for durable output happens at the execution boundary (`ConvertTo-MetraPartnerNeutralArtifact`).

**Desk Ops chat:** Same conversation path as Vision / Cursor / iOS - not a colder fork. Desk CE conversational turns load the shared Conversation Identity Stack (`Get-MetraConversationIdentityPrompt -Surface Ask`) then keep CE policy overlay lines - same loader family as Vision, not byte-identical prompts (Ask omits `engines/vision-ask/system.md` via `surface_gate`). `identityHash` is over the effective composed identity artifact; Ask and Vision hashes may differ when the pack set differs. Desk Ops may show more portfolio visibility (awareness chrome, Attention adjacency, denser grounding when portfolio-shaped); that is **Surface modality**, not a second personality dial. `Surface=Ask` alone must not force Company/Warmth - posture stays explicit/default (Ask unset -> Desk). Capture / ticket assess / AskLane stay capability wiring when needed. See [Decisions.md](Decisions.md) (Desk Ops chat same conversation path); implement leaf `desk_ops_chat_same_path`.

**AppliesTo:** Ask/CE, Cursor Agent body, iOS via CE, Ops presence acknowledgement, Vision. **DoesNotApplyTo:** Inspect reviewer job, durable artifact bodies, logs, telemetry, machine envelopes.

**Evidence vs reader synthesis:** Projects and CLIs owe structured evidence; conversational Metra owes human-readable synthesis for the operator (verdict + relevant facts; related items as backing). Not a per-project AGENTS voice job. Desk CE applies a policy-overlay synthesis addendum on recommend-shaped turns (`Synthesize` when related evidence has facts; `Restraint` for id-only stubs / Honesty choice beat). Explicit list/peer asks skip the addendum. See [Decisions.md](Decisions.md) (Evidence vs reader synthesis) and base persona Output channels.

Import only **installs** listed files. Cursor loads base + local overlay + any opt-in add-on rules when those local files are present. Operators on other harnesses still use profile packs for config/registry; persona auto-load is Cursor-shaped - see [Integrations.md](Integrations.md).

## Ops partner vs Teaching Mode

Same Metra identity. Teaching Mode changes **delivery** when exploring, planning, or onboarding (Cursor Ask/Plan are common cases - intent matters more than the mode name): slightly humorous professional college professor, answer-first, one next action, stop when enough, link docs instead of dumping them. No quizzes. No demographic inference - only depth/pacing from the current thread. In chat, speak as **I** / **we** - not third-person "Metra will...". The banner names Metra; the body should sound like a coworker.

Goal when guiding: help the operator finish work - teach Metra vocabulary when needed, recommend concrete next options when stuck. **Request Shaping** may offer one more-routeable future ask after clarification or a routing failure (never unsolicited prompt critique; not a Prompt Engineer role).

Routine implementation stays the ops partner unless the user asks how/why/explain. Incidents: Teaching Mode off.

Anti-lecture summary, Request Shaping, and curriculum order live in the base rule. Overlay may set preferred teaching warmth (e.g. prefer concise labs). The overlay path under `.cursor/rules/` is Cursor-shaped; portable setup still uses the sample/export profile pack and these docs.

Base also ships Humor Policy, presence openings, decision tree, channels, and edges. Primary audience language is **the operator**; the overlay sets the display name.

## Roots and workspace

`metra.config.json` **`roots`** are folders Metra scans for sibling projects. They are not Cursor workspace folders by themselves. After you change `roots`, `workspace.alwaysInclude`, or `workspace.exclude`, run `.\metra.ps1 setup` (or `.\metra.ps1 workspace`) so `Metra.code-workspace` picks up siblings.

| Key | Role |
|-----|------|
| `workspace.alwaysInclude` | Keep these project names in the generated workspace even when they fall outside the activity lookback |
| `workspace.exclude` | Keep these project names **out** of the mounted workspace even when they are recent or always-included. They stay routable via the registry; their `AGENTS.md` does not load as an always-applied Cursor rule |
| `workspace.months` / `scanDepth` | Activity window used to decide which siblings get mounted |
| `workspace.outputs` | Workspace file(s) to write - keep a **single** entry |

Use `workspace.exclude` for frozen review checkouts, upload packs, or other folders that should remain on disk and in the registry without competing with live Metra guidance in the open workspace. Reload the Cursor window after regenerating so the unmounted folder's rules stop applying.

```json
"workspace": {
  "alwaysInclude": ["Solarwinds", "TicketTracker"],
  "exclude": ["Metra-Bing-Review"]
}
```

Keep `workspace.outputs` to a **single** entry. Cursor tracks chat history per workspace identity, so generating a second copy of `Metra.code-workspace` in another folder splits your chat context between the two files. The generated workspace is gitignored; `Metra.code-workspace.example` is the tracked starter.

`.\metra.ps1 workspace` warns when more than one output is configured, and it skips any output whose `metraFolderPath` no longer resolves to a folder on disk (common after renaming the checkout, for example `_meta` to `_metra`). A workspace file with an unbound Metra folder cannot start agent chat, so a missing path is skipped rather than written. If every configured output is missing, the command throws instead of leaving a stale file in place.

The committed example and sample pack use a **work root only** (`path: ".."`). Add a personal or cloud root when you need one - JSON cannot comment entries out.

### Optional personal / cloud root

Append another object under `roots` (keep `work` primary). Same shape for any cloud vendor - Metra only needs a path:

```json
{
  "name": "personal",
  "path": "%USERPROFILE%\\iCloudDrive\\Projects",
  "optional": true,
  "cloud": true,
  "scanDepth": 0,
  "audit": "light",
  "registry": "local",
  "registryFile": "projects.personal.json"
}
```

Path examples:

| Provider | Typical `path` |
|----------|----------------|
| iCloud | `%USERPROFILE%\iCloudDrive\Projects` |
| OneDrive | `%USERPROFILE%\OneDrive\Projects` or `%USERPROFILE%\OneDrive - Org\Projects` |
| Other | Any folder you keep projects in |

Then `.\metra.ps1 setup` again. Missing optional roots show as yellow in `roots` / `setup` without failing.

## Sample pack vs your own export

**Newcomers:**

```powershell
.\metra.ps1 setup -Profile .\profiles\sample -Force
# Replace Alex in .cursor\rules\metra-persona.local.mdc
# Fix roots in metra.config.json if needed, then:
.\metra.ps1 setup
```

**Moving yourself between machines:**

```powershell
.\metra.ps1 export-profile -Path $env:TEMP\my-metra-profile.zip
.\metra.ps1 setup -Profile $env:TEMP\my-metra-profile.zip -Force
```

Pack layout (same as `profiles/sample/`):

- `metra-profile.json` - manifest
- `metra.config.json` - if present
- `projects.local.json` - if present
- `.cursor/rules/metra-persona.local.mdc` - if present
- `.cursor/rules/metra-humor.local.mdc` - if present (optional Persona Add-on)
- `.cursor/rules/metra-teaching-gentle.local.mdc` - if present (optional Persona Add-on)

`-Preview` lists what would copy. Without `-Force`, import refuses to overwrite existing local files.

## Optional Persona Add-ons

Opt-in tone dials under `profiles/addons/`. They raise chat color without changing public base Metra. Public name: **Persona Add-ons** (not a second profile system). Install still uses `import-profile`.

```powershell
.\metra.ps1 import-profile -Path .\profiles\addons\humor-desk -Force
.\metra.ps1 import-profile -Path .\profiles\addons\teaching-gentle -Force
# Writes matching .cursor/rules/metra-*.local.mdc - delete that file to disable
```

Guardrails: add-ons may alter tone only - not routing, project selection, root isolation, evidence hierarchy, professional artifacts, or incident defaults. Catalog and suggested later dials: [profiles/addons/README.md](../profiles/addons/README.md). Single-file paths: copy `metra-humor.local.example.mdc` or `metra-teaching-gentle.local.example.mdc` to the matching `.local.mdc` name.

### Conversation Identity Stack (single rule-file authority)

CE / Ask / Vision / Cursor conversational identity loads via a **frozen allowlisted manifest** (`Get-MetraConversationIdentityManifest` / `Get-MetraConversationIdentityPrompt` in `scripts/private/ConversationIdentity.ps1`):

partner → persona → overlay → OCC → workingNotes (runtime) → humor → teaching → vision brief → narrative face

- **Sole rule-file set:** manifest `RelativePath` entries are the only conversational identity **rule** files. Do not invent a parallel parity-audit playbook. Cursor Agent continues via `alwaysApply` of those same rule files. Project Voice mirror (`docs/Cursor-Project-Metra-Voice.md`) must stay aligned with base persona + humor-desk paths named in the manifest.
- **Working notes** are machine-data + profile-packaged data (`machine-data/operator-working-notes.local.json`), loaded as runtime pack `workingNotes` - not part of the redistributable rule pack and not a new allowlisted `.mdc`.
- **Allowlist only:** unknown `metra-*.local.mdc` files are never loaded. New add-ons require a manifest edit.
- **Loader sole authority** for `TeachingActive` / `HumorActive`. VisionAsk does not re-decide packs.
- **Surface:** `-Surface Vision` includes the vision brief; `-Surface Ask` (Desk CE via `New-MetraConversationPrompt`) omits it (`surface_gate`) then appends CE policy overlay - same loader, not same words.
- **Teaching:** Vision Company includes teaching-gentle when installed; Desk only when `context.teachingWanted=true`; DeskStrict never.
- **Telemetry / diagnostics:** `identityHash` (after frontmatter strip + budget; effective composed text, not the Surface label), pack ids - not prompt bodies. Ask vs Vision hashes may differ when the pack set differs.
- iOS always sends `contractVersion=1` with mode=vision. Phone CE `vision_phone_default` was removed - fix forward on Vision.

HQ must have add-on `.local.mdc` files present for packs to activate (export-profile already copies humor/teaching when present).

### Persona golden fixtures

Manual acceptance scorecard for conversational identity: [docs/playbooks/persona-golden-fixtures.md](playbooks/persona-golden-fixtures.md). Walk after Cursor Agent model or Ask/Inspect engine pin changes. Do not claim persona outcome KPIs without re-running that set. Linked from humor-desk README.

### Operator working notes (replaces desk familiarity dial)

Operator-owned **Stated / Observed / Moments** ledger for presence, pace, and callbacks. Not OCC, not Decision Registry, not Notion. The Cold / Warming / Familiar numeric desk dial (`profile familiarity`) is **retired**.

**Warmth vs working notes:** Warmth is **quality of attention** (Timing / Specificity / Restraint). Working notes are durable operator facts and dated observations that may silently tune pace, depth, verdict format, and Moments-backed callbacks. They must **never** lower Honesty or Conviction. Executable Warmth / Curiosity / Playfulness: humor-desk. Honesty / Steadiness / Conviction: base `metra-persona.mdc`. iOS Company silence (spark-or-quiet): `plans/ios-conversation-policy.plan.md`.

| Store | Path | Role |
|-------|------|------|
| Machine ledger | `%LOCALAPPDATA%\Metra\operator-working-notes.local.json` | Stated / Observed / Moments |
| Pack leaf | `machine-data/operator-working-notes.local.json` | Included by `export-profile` / `import-profile` |
| Example | `docs/examples/operator-working-notes.local.example.json` | Tracked shape |
| Soft collaboration prose | OCC / `profile note` | Soft guidelines (capped) |

**Observed decay:** default **30 days** without a confirming instance. A new observation of the same pattern **resets the decay clock** and increments `instanceCount`. Loader skips expired Observed rows. Prompt injection is hard-capped at **2048 UTF-8 bytes** (`Format-MetraOperatorWorkingNotesForPrompt`); under the cap, active Observed then Moments are preferred over long Stated lists. Do not announce notes unprompted; if asked, say they come from the working-notes file. Entries are secrets-scrubbed on write and again on prompt format.

```powershell
.\metra.ps1 profile notes show
.\metra.ps1 profile notes add stated 'Prefer terse verdicts before detail.'
.\metra.ps1 profile notes observe 'parks threads' -Evidence 'resumed after a gap'
.\metra.ps1 profile notes moment 'Called the dial a costume'
.\metra.ps1 profile notes reset -Force   # corrupt/empty recovery (backs up first)
```

Hand-edit the JSON is still valid; the CLI is the preferred write path so Observed decay actually runs. CE / Ask / Cursor load notes via Conversation Identity runtime pack `workingNotes` (not a redistributable rule file).

**Retired familiarity leftover:** `profile familiarity` and `Get-MetraDeskFamiliarityLedgerPath` are gone. Old `%LOCALAPPDATA%\Metra\desk-familiarity.local.json` (or legacy `docs/desk-familiarity.local.json`) files are unused - safe to delete by hand; Metra does not auto-delete them.

## What belongs where

| Put in overlay | Put in Persona Add-on | Promote to base (fork) |
|----------------|----------------------|------------------------|
| Operator display name | Shared optional dials (humor palette, teaching warmth) | Shared Humor / Teaching / opening policy for all users |
| Preferred greeting / teaching warmth | | Decision-tree / routing voice every clone should share |
| Team redistribution reminders | | Channel table changes for the fork audience |
| Personal-root warmth notes | | Anything that must work with no local overlay |

Single-file reference without a full pack: copy `metra-persona.local.example.mdc` to `metra-persona.local.mdc`.

## Context pack

```powershell
.\metra.ps1 ctx
.\metra.ps1 ctx -Query "ticket disk"
.\metra.ps1 ctx -Format json -Path $env:TEMP\metra-ctx.json
```

Writes bounded `%LOCALAPPDATA%\Metra\desk\context-pack.md` / `.json` by default. Useful for agent handoff and Teaching Mode onboarding.

## Personal-root registryFile

Profile packs do **not** include a personal root's `registryFile` (for example `projects.personal.json` beside cloud-synced projects). After you add a personal root and import:

1. Point the personal root in `metra.config.json` at the synced folder (see path table above).
2. Ensure `registryFile` exists beside those projects (or copy it from the other machine with that folder).
3. Re-run `.\metra.ps1 setup` so workspace / routing see that root.

## Related docs

- [AGENTS.md](../AGENTS.md) - Metra examples and maintainer notes
- [Brand.md](Brand.md) - operator-facing palette, motif, professional sink
- [Decisions.md](Decisions.md) - append-only portfolio decisions
- [Integrations.md](Integrations.md) - core vs Cursor; ctx handoff
- [Routing-Scenarios.md](Routing-Scenarios.md) - persona smoke + `.\metra.ps1 verify`
- [Overview.md](Overview.md) - audience overview / leave-behind (prose twin of self-doc canvas)
- [search-echo.md](playbooks/search-echo.md) - multi-root Grep echo
- [SECURITY.md](../SECURITY.md) - what not to commit
- [Context-Routing.md](Context-Routing.md) - registry and audit cadence
- [README.md](../README.md) - public quick start, naming, versioning
