# humor-desk (Metra Persona Add-on)

Opt-in desk-partner humor for operator chat. Does **not** replace the base persona or the operator overlay. Tone only.

## What you get

Installs `.cursor/rules/metra-humor.local.mdc` with:

- A mix of dry understatement, evidence + light sarcasm, deadpan multi-root notes, self-aware ops humor, gentle pattern recognition, and work callbacks
- Humor additive, not substitutive (aside never replaces the answer)
- More asides on routine coding (still answer-first)
- At most one ticket intro aside when requester evidence helps focus - not every ticket
- Hard off for incidents, outages, and redistribution drafts

## Import

From the `_meta` repo root:

```powershell
.\meta.ps1 import-profile -Path .\profiles\addons\humor-desk -Preview
.\meta.ps1 import-profile -Path .\profiles\addons\humor-desk -Force
```

Disable: delete `.cursor/rules/metra-humor.local.mdc`.

## Contents

| File | Role |
|------|------|
| `meta-profile.json` | Manifest (install via `import-profile`) |
| `.cursor/rules/metra-humor.local.mdc` | Always-on Cursor rule after import |

See [profiles/addons/README.md](../README.md) and [docs/Customizing-Metra.md](../../../docs/Customizing-Metra.md).
