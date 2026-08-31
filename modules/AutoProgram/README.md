# AutoProgram / Loom

Governed execution domain: approved formal plans → queue → review → operator acceptance.

**Product name:** Loom (chosen 2026-08-31). **Working name through M2:** AutoProgram.

**Dependency direction:** AutoProgram → Adapters → Metra public surfaces. Never import `scripts/private/*.ps1`.

**Isolation gate:** `Import-Module .\modules\AutoProgram\AutoProgram.psd1` must succeed without `Metra.psm1`.

See `docs/autoprogram-product-boundary.plan.md`.
