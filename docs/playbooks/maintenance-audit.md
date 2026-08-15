---
metraMemory: procedural
defaultContext: false
loadWhen:
  - audit
  - selfdoc
  - verify
  - add project
  - registry drift
  - Brand.md
ceiling:
  - Audit never auto-edits files or auto-splits stubs
---

> Moved from `AGENTS.md` during A2 desk split. Preserve A1 done-when / On hard stop content unless intentionally revised.

# Maintenance and audit

Re-run `.\metra.ps1 audit` after adding a project or changing layout. Update the appropriate registry (`projects.json` only for shared entries), project `AGENTS.md`, and `.cursorignore` only when audit reports drift. After registry **route / trigger / purpose** changes, run `.\metra.ps1 selfdoc` so the self-documentation canvas and `docs/Overview.md` regenerate standing examples (or `snapshot -RefreshSelfDocumentation`). See [docs/Context-Routing.md](../Context-Routing.md). After routing or persona policy changes that should stick, append [docs/Decisions.md](../Decisions.md). Smoke fixtures: `.\metra.ps1 verify`.

Operator-facing brand (palette, Ops board, workspace naming) lives in [docs/Brand.md](../Brand.md). Tickets and commits stay in the professional sink - no Metra chrome.

A2 desk split review pack:

```powershell
.\metra.ps1 inspect pack-only agents -Name <Project>
```

Writes `%LOCALAPPDATA%\Metra\inspect\pack-agents.md` and copies to clipboard for Bing comparison lane.
