# Sample Metra operator profile pack

Anonymized starter pack for newcomers. Same layout as `export-profile` / `import-profile`.

## Contents

| File | Role |
|------|------|
| `meta-profile.json` | Manifest (id, file list, notes) |
| `meta.config.json` | Starter roots config (relative work root, optional personal root); workspace outputs `Metra.code-workspace` |
| `projects.local.json` | Example private registry entry (`ExampleProject`) |
| `.cursor/rules/metra-persona.local.mdc` | Operator overlay (display name placeholder: Alex) |

No real usernames, hostnames, or org-private paths. `workspace.alwaysInclude` is empty.

Personal-root `registryFile` (e.g. `projects.personal.json` beside personal projects) is out of band - copy with that root separately if needed.

## Import

From the `_meta` repo root:

```powershell
.\meta.ps1 import-profile -Path .\profiles\sample -Force
# Edit meta.config.json roots / alwaysInclude
# Edit .cursor\rules\metra-persona.local.mdc operator display name
.\meta.ps1 workspace
.\meta.ps1 audit
.\meta.ps1 snapshot
```

Open `Metra.code-workspace` (orchestration folder labeled **Metra**). Preview only (no writes):

```powershell
.\meta.ps1 import-profile -Path .\profiles\sample -Preview
```

See [docs/Customizing-Metra.md](../../docs/Customizing-Metra.md), [docs/Brand.md](../../docs/Brand.md), and [SECURITY.md](../../SECURITY.md).
