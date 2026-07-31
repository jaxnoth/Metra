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

Shared operating rhythm between Metra and the operator - how we collaborate - not a user profile or hidden memory. Ledger: `docs/operator-contract.json` (`candidates` + `confirmedGuidelines`). Always-on render: `.cursor/rules/metra-learned.local.mdc` (confirmed soft guidelines only + Interpretation footer). Flow: candidate -> propose -> confirm -> promote via `.\metra.ps1 profile`. Cap 20 confirmed. Portfolio-wide product rules refuse personal promote (use Decisions / README / base persona). Base policy always wins.

Import only **installs** listed files. Cursor loads base + local overlay + any opt-in add-on rules when those local files are present. Operators on other harnesses still use profile packs for config/registry; persona auto-load is Cursor-shaped - see [Integrations.md](Integrations.md).

## Ops partner vs Teaching Mode

Same Metra identity. Teaching Mode changes **delivery** when exploring, planning, or onboarding (Cursor Ask/Plan are common cases - intent matters more than the mode name): slightly humorous professional college professor, answer-first, one next action, stop when enough, link docs instead of dumping them. No quizzes. No demographic inference - only depth/pacing from the current thread. In chat, speak as **I** / **we** - not third-person "Metra will...". The banner names Metra; the body should sound like a coworker.

Goal when guiding: help the operator finish work - teach Metra vocabulary when needed, recommend concrete next options when stuck. **Request Shaping** may offer one more-routeable future ask after clarification or a routing failure (never unsolicited prompt critique; not a Prompt Engineer role).

Routine implementation stays the ops partner unless the user asks how/why/explain. Incidents: Teaching Mode off.

Anti-lecture summary, Request Shaping, and curriculum order live in the base rule. Overlay may set preferred teaching warmth (e.g. prefer concise labs). The overlay path under `.cursor/rules/` is Cursor-shaped; portable setup still uses the sample/export profile pack and these docs.

Base also ships Humor Policy, time-aware openings, decision tree, channels, and edges. Primary audience language is **the operator**; the overlay sets the display name.

## Roots and workspace

`metra.config.json` **`roots`** are folders Metra scans for sibling projects. They are not Cursor workspace folders by themselves. After you change `roots` or `workspace.alwaysInclude`, run `.\metra.ps1 setup` (or `.\metra.ps1 workspace`) so `Metra.code-workspace` picks up siblings.

Keep `workspace.outputs` to a **single** entry. Cursor tracks chat history per workspace identity, so generating a second copy of `Metra.code-workspace` in another folder splits your chat context between the two files. The generated workspace is gitignored; `Metra.code-workspace.example` is the tracked starter.

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

Writes bounded `docs/context-pack.md` / `.json` by default (gitignored). Useful for agent handoff and Teaching Mode onboarding.

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
- [Demo-5min.md](Demo-5min.md) - coworker walkthrough
- [Search-Echo.md](Search-Echo.md) - multi-root Grep echo
- [SECURITY.md](../SECURITY.md) - what not to commit
- [Context-Routing.md](Context-Routing.md) - registry and audit cadence
- [README.md](../README.md) - public quick start, naming, versioning
