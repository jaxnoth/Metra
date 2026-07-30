# Sample Metra operator profile pack

Anonymized starter pack for newcomers. Same layout as `export-profile` / `import-profile`.

## Contents

| File | Role |
|------|------|
| `metra-profile.json` | Manifest (id, file list, notes) |
| `metra.config.json` | Starter roots config (work root `..` only); workspace outputs `Metra.code-workspace` |
| `projects.local.json` | Example private registry entry (`ExampleProject`) |
| `.cursor/rules/metra-persona.local.mdc` | Operator overlay (display name placeholder: Alex) |

No real usernames, hostnames, or org-private paths. `workspace.alwaysInclude` is empty.

Personal-root `registryFile` (e.g. `projects.personal.json` beside personal projects) is out of band - copy with that root separately if needed.

## Import

From the Metra checkout root (recommended `_metra`; older clones may use `_meta`):

```powershell
.\metra.ps1 setup -Profile .\profiles\sample -Force
# Edit metra.config.json roots / alwaysInclude if needed, then: .\metra.ps1 setup
# Edit .cursor\rules\metra-persona.local.mdc operator display name
```

Open or reload `Metra.code-workspace` (orchestration folder labeled **Metra**). Preview only (no writes):

```powershell
.\metra.ps1 setup -Profile .\profiles\sample -Preview
```

See [docs/Customizing-Metra.md](../../docs/Customizing-Metra.md), [docs/Brand.md](../../docs/Brand.md), and [SECURITY.md](../../SECURITY.md).
