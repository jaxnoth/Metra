# Loom

Governed execution product: approved formal plans → queue → isolated mutation → review → operator acceptance.

**Host:** Metra (`.\metra.ps1 loom …`). **Module:** `modules/Loom/`.

## Terminology

| Term | Meaning |
|------|---------|
| **Loom** | Governed execution product/module |
| **Metra** | Host and operator surface |
| **AP-\*** | Stable work-item ID namespace (unchanged) |
| **CAND-\*** | Stable candidate ID namespace (unchanged) |

## CLI

```powershell
.\metra.ps1 loom status
.\metra.ps1 loom show -Id <AP-...>
.\metra.ps1 loom run -Id <AP-...> -DryRun
.\metra.ps1 loom run -Id <AP-...> -Confirm
.\metra.ps1 loom migrate              # dry-run summary
.\metra.ps1 loom migrate -Apply -Confirm
```

Deprecated alias (one release): `.\metra.ps1 autoprogram …` (warns, delegates to `loom`).

## Storage

Default: `%LOCALAPPDATA%\Metra\loom\`

Legacy read-only until migrated: `%LOCALAPPDATA%\Metra\autoprogram\`

## Docs

- [loom-product-boundary.plan.md](../docs/loom-product-boundary.plan.md)
- [docs/playbooks/loom.md](../docs/playbooks/loom.md)

Isolation gate: `Import-Module .\modules\Loom\Loom.psd1` without `Metra.psm1`.
