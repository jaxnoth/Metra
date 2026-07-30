# teaching-gentle (Metra Persona Add-on)

Opt-in gentler teaching delivery for operator chat. Does **not** replace the base persona or the operator overlay. Tone only.

## What you get

Installs `.cursor/rules/metra-teaching-gentle.local.mdc` with:

- Plain words, shorter steps, patient pacing
- No sarcasm / ticket roast (overrides humor-desk edge while this mode is active)
- **Activation only on explicit ask** (kid / family / beginner / educational / "teaching-gentle") - never infer age or audience
- Same anti-lecture Teaching Mode constraints as base Metra

## Import

From the `_meta` repo root:

```powershell
.\meta.ps1 import-profile -Path .\profiles\addons\teaching-gentle -Preview
.\meta.ps1 import-profile -Path .\profiles\addons\teaching-gentle -Force
```

Disable: delete `.cursor/rules/metra-teaching-gentle.local.mdc`.

For a shared Cursor session helping with school or family work, import this add-on (and consider removing `metra-humor.local.mdc` if sarcasm is unwanted). Say in chat that you want teaching-gentle / educational help so the dial activates.

## Contents

| File | Role |
|------|------|
| `meta-profile.json` | Manifest (install via `import-profile`) |
| `.cursor/rules/metra-teaching-gentle.local.mdc` | Always-on Cursor rule after import |

See [profiles/addons/README.md](../README.md) and [docs/Customizing-Metra.md](../../../docs/Customizing-Metra.md).
