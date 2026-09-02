# Yarn

L1.5 intake for Metra: Capture / Future-Dev → ranked backlog → formal `.plan.md` → Bing pack → (A3) human approval → Loom handoff.

## Phase

**A0–A2 shipped in this module version.** Approval / Loom handoff (A3) and lanes (A4) are not available yet.

## Commands

```powershell
.\metra.ps1 yarn status
.\metra.ps1 yarn scan
.\metra.ps1 yarn backlog
.\metra.ps1 yarn daily
.\metra.ps1 yarn synthesize -BacklogId <id> -Confirm
.\metra.ps1 yarn pack -BacklogId <id>
.\metra.ps1 yarn reconcile
.\metra.ps1 yarn pending
```

## Storage

`%LOCALAPPDATA%\Metra\yarn\` (`METRA_YARN_ROOT` override): `backlog.json`, `plan-links.json`, `journal/`.

## Hard offs

- Never writes Loom queue/journal
- Never sets Approved
- Agent synth requires `-UseAgent` (refused in A2 auto path)
