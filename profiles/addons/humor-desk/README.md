# humor-desk (Metra Persona Add-on)

Opt-in desk-partner color for operator chat. Does **not** replace the base persona or the operator overlay. Tone only.

## What you get

Installs `.cursor/rules/metra-humor.local.mdc` with:

- Companion cues: **Warmth / Curiosity / Playful** (eval order; each may stay silent)
- **Warmth kernel:** attention not affection; Timing / Specificity / Restraint; locked vocabulary (seam / spark / resume callback / open energy); Anti-flatness alive-in-turn seams; no Agent proactive sparks
- **Curiosity kernel:** pursuit not interrogation; Depth / Breadth / Restraint; one curiosity move per response; Specificity-first gate; carve-out for routing/safety/execution; project-draw as inventory
- **Playfulness kernel:** permission not performance; Surprise / self-deprecation / callbacks; callback provenance; self-deprecation bound; lighter-vs-managed test; six-flavor palette (at most one; no flavor ledger)
- **Combined garnish budget:** beyond the answer, Curiosity **or** Playfulness - not both (invited-absurdity exception)
- Triad ratio: Warmth holds / Curiosity drives / Playfulness spice; honesty and steadiness deferred
- Grow/mirror register; dual desk familiarity (session fast, durable slow ledger) as **intensity** only
- Humor additive, not substitutive; hard off for incidents, tickets (mostly), redistribution drafts

Silence **spark-or-quiet** lives in `plans/ios-conversation-policy.plan.md` (iOS Company only). Cursor Agent is turn-based and must not invent silence pings.

Durable numeric familiarity: `.\metra.ps1 profile familiarity show` / `analyze-nudge` (local `%LOCALAPPDATA%\Metra\desk-familiarity.local.json`). Prose prefs stay OCC.

## Import

From the Metra checkout root (recommended `_metra`; older clones may use `_meta`):

```powershell
.\metra.ps1 import-profile -Path .\profiles\addons\humor-desk -Preview
.\metra.ps1 import-profile -Path .\profiles\addons\humor-desk -Force
```

Disable: delete `.cursor/rules/metra-humor.local.mdc`.

## Contents

| File | Role |
|------|------|
| `metra-profile.json` | Manifest (install via `import-profile`) |
| `.cursor/rules/metra-humor.local.mdc` | Always-on Cursor rule after import |

See [profiles/addons/README.md](../README.md) and [docs/Customizing-Metra.md](../../../docs/Customizing-Metra.md).
