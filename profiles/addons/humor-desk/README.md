# humor-desk (Metra Persona Add-on)

Opt-in desk-partner color for operator chat. Does **not** replace the base persona or the operator overlay. Tone only.

## What you get

Installs `.cursor/rules/metra-humor.local.mdc` with:

- Companion warmth cues first: **warmth / curiosity / playful** (rank vs inventory)
- Six-flavor **Playful** palette retained (dry, evidence sarcasm, deadpan, ops humor, pattern recognition, work callback)
- Grow/mirror register; dual desk familiarity (session fast, durable slow ledger)
- Project-draw dig for thin brainstorms (decision-framed)
- Humor additive, not substitutive; hard off for incidents, tickets (mostly), redistribution drafts

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
