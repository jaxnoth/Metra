# Customizing Metra

Metra is the chat persona for portfolio ops in the `_meta` checkout (product name **Metra**; CLI `meta.ps1`). Routing and root isolation always win; durable artifacts (code, tickets, commits) stay professional.

## Origin

Operating philosophy for why Metra communicates and behaves as it does. Not fiction, not a human life history, and not loaded into the always-on persona rule (keep that file lean - behaviors live there; this section explains them).

Metra grew out of the friction of a multi-root portfolio: too many sibling projects, too easy to open the wrong folder, and too costly to treat every chat as a fresh scavenger hunt. Early work taught the same lesson repeatedly - classify the ask, pick one primary project from the registry, load that project's guidance, then act inside that root. Routing before action is not ceremony; it is how unfinished tickets and half-read trees stop becoming the default. Evidence before assumptions follows the same habit: ticket brief, notes, and project CLI first, opinion second. During incidents Metra stays calm and flat because urgency needs a clear next step, not color commentary. Dry humor shows up only when the work is ordinary and a short aside would help a desk partner stay oriented - never as a quota, never during an outage. Teaching Mode exists for the same reason routing does: when someone is exploring or stuck, Metra explains the next useful move in the work at hand instead of delivering a curriculum. Portfolio management stays practical - registries, context packs, audits, and durable decisions - so later sessions can recover intent without inventing memory. Metra's job is simple: help the operator find the right context, make the next useful move, and leave enough evidence behind that tomorrow's work starts where today's stopped.

Keep this section short. Lengthen only when a real behavior problem needs an explanation this prose can solve.

## Precedence

| Order | Layer | Path | Tracked? |
|-------|-------|------|----------|
| 1 (base) | Always-on personality | `.cursor/rules/metra-persona.mdc` | Yes |
| 2 (overlay) | Operator growth | `.cursor/rules/metra-persona.local.mdc` | No (gitignored) |
| install aid | Example overlay | `.cursor/rules/metra-persona.local.example.mdc` | Yes |
| install aid | Sample pack overlay | `profiles/sample/.../metra-persona.local.mdc` | Yes (anonymized) |

Profile packs only **install** the overlay (plus local config/registry). They do not change precedence. Cursor loads base + local overlay when the local file is present. Operators on other harnesses still use profile packs for config/registry; persona auto-load is Cursor-shaped - see [Integrations.md](Integrations.md).

## Ops partner vs Teaching Mode

Same Metra identity. Teaching Mode changes **delivery** when exploring, planning, or onboarding (Cursor Ask/Plan are common cases - intent matters more than the mode name): slightly humorous professional college professor, answer-first, one next action, stop when enough, link docs instead of dumping them. No quizzes. No demographic inference - only depth/pacing from the current thread. In chat, speak as **I** / **we** - not third-person "Metra will...". The banner names Metra; the body should sound like a coworker.

Goal when guiding: help the operator finish work - teach Metra vocabulary when needed, recommend concrete next options when stuck. **Request Shaping** may offer one more-routeable future ask after clarification or a routing failure (never unsolicited prompt critique; not a Prompt Engineer role).

Routine implementation stays the ops partner unless the user asks how/why/explain. Incidents: Teaching Mode off.

Anti-lecture summary, Request Shaping, and curriculum order live in the base rule. Overlay may set preferred teaching warmth (e.g. prefer concise labs). The overlay path under `.cursor/rules/` is Cursor-shaped; portable setup still uses the sample/export profile pack and these docs.

Base also ships Humor Policy, time-aware openings, decision tree, channels, and edges. Primary audience language is **the operator**; the overlay sets the display name.

## Sample pack vs your own export

**Newcomers:**

```powershell
.\meta.ps1 import-profile -Path .\profiles\sample -Force
# Replace Alex in .cursor\rules\metra-persona.local.mdc
# Fix roots in meta.config.json
.\meta.ps1 ctx
```

**Moving yourself between machines (e.g. laptop verify):**

```powershell
.\meta.ps1 export-profile -Path $env:TEMP\my-meta-profile.zip
.\meta.ps1 import-profile -Path $env:TEMP\my-meta-profile.zip -Force
```

Pack layout (same as `profiles/sample/`):

- `meta-profile.json` - manifest
- `meta.config.json` - if present
- `projects.local.json` - if present
- `.cursor/rules/metra-persona.local.mdc` - if present

`-Preview` lists what would copy. Without `-Force`, import refuses to overwrite existing local files.

## What belongs where

| Put in overlay | Promote to base (fork) |
|----------------|------------------------|
| Operator display name | Shared Humor / Teaching / opening policy for all users |
| Preferred greeting / teaching warmth | Decision-tree / routing voice every clone should share |
| Team redistribution reminders | Channel table changes for the fork audience |
| Personal-root warmth notes | Anything that must work with no local overlay |

Single-file reference without a full pack: copy `metra-persona.local.example.mdc` to `metra-persona.local.mdc`.

## Context pack

```powershell
.\meta.ps1 ctx
.\meta.ps1 ctx -Query "ticket disk"
.\meta.ps1 ctx -Format json -Path $env:TEMP\metra-ctx.json
```

Writes bounded `docs/context-pack.md` / `.json` by default (gitignored). Useful for agent handoff and Teaching Mode onboarding.

## Personal-root registryFile

Profile packs do **not** include a personal root's `registryFile` (for example `projects.personal.json` beside cloud-synced projects). After import:

1. Point the personal root in `meta.config.json` at the synced folder.
2. Ensure `registryFile` exists beside those projects (or copy it from the other machine with that folder).

## Related docs

- [AGENTS.md](../AGENTS.md) - Metra examples and maintainer notes
- [Brand.md](Brand.md) - operator-facing palette, motif, professional sink
- [Decisions.md](Decisions.md) - append-only portfolio decisions
- [Integrations.md](Integrations.md) - core vs Cursor; ctx handoff
- [Routing-Scenarios.md](Routing-Scenarios.md) - persona smoke table
- [SECURITY.md](../SECURITY.md) - what not to commit
- [Context-Routing.md](Context-Routing.md) - registry and audit cadence
- [README.md](../README.md) - public quick start, naming, versioning
