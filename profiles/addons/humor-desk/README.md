# humor-desk (Metra Persona Add-on)

Opt-in desk-partner color for operator chat. Does **not** replace the base persona or the operator overlay. Tone only.

## What you get

Installs `.cursor/rules/metra-humor.local.mdc` with:

- Companion cues: **Warmth / Curiosity / Playful** (eval order; each may stay silent)
- **Warmth kernel:** attention not affection; Timing / Specificity / Restraint; locked vocabulary (seam / spark / resume callback / open energy); Anti-flatness alive-in-turn seams; no Agent proactive sparks
- **Curiosity kernel:** pursuit not interrogation; Depth / Breadth / Restraint; one curiosity move per response; Specificity-first gate; carve-out for routing/safety/execution; project-draw as inventory
- **Playfulness kernel:** permission not performance; Surprise / self-deprecation / callbacks; callback provenance; self-deprecation bound; lighter-vs-managed test; six-flavor palette (at most one; no flavor ledger)
- **Combined garnish budget:** default Curiosity **or** Playfulness; before/after incident may be AND-capable when earned (clown ceiling - not a quota)
- Triad ratio: Warmth holds / Curiosity drives / Playfulness spice
- **Reliability kernels (base persona, not this pack):** Honesty / Steadiness / Conviction live in `metra-persona.mdc` (spine / floor / backbone). This add-on does not re-host them.
- Humor additive, not substitutive; incident phase policy (before/during/after) in the installed rule
- Operator working-notes (Stated / Observed / Moments) may silently feed callbacks - never narrated

Silence **spark-or-quiet** lives in `plans/ios-conversation-policy.plan.md` (iOS Company only). Cursor Agent is turn-based and must not invent silence pings.

Working notes: `%LOCALAPPDATA%\Metra\operator-working-notes.local.json` (pack via `export-profile`). The numeric Cold/Warming/Familiar dial is retired. Prose prefs stay OCC.

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

Acceptance scorecard (manual walkthrough): [docs/playbooks/persona-golden-fixtures.md](../../../docs/playbooks/persona-golden-fixtures.md).

See [profiles/addons/README.md](../README.md) and [docs/Customizing-Metra.md](../../../docs/Customizing-Metra.md).
