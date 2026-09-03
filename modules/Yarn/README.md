# Yarn

L1.5 intake for Metra: Capture / Future-Dev / Atlas → ranked backlog → formal `.plan.md` → Bing pack → human approval → Loom handoff.

## Phase

**A0–A4 + Phase B Atlas shipped.** Slice 7 Phase C AutoProgram leftovers are closed (docs/naming). Slice 8 Notion promote remains out of scope here.

## Commands

```powershell
.\metra.ps1 yarn status
.\metra.ps1 yarn scan
.\metra.ps1 yarn backlog
.\metra.ps1 yarn daily
.\metra.ps1 yarn synthesize -BacklogId <id> -Confirm
.\metra.ps1 yarn synthesize -FromMemory <stableId> -Confirm
.\metra.ps1 yarn pack -BacklogId <id>
.\metra.ps1 yarn reconcile
.\metra.ps1 yarn pending
.\metra.ps1 yarn plan approve -BacklogId <id> -Confirm
```

## Storage

`%LOCALAPPDATA%\Metra\yarn\` (`METRA_YARN_ROOT` override): `backlog.json`, `plan-links.json`, `memory-lane.json`, `journal/`.

## Hard offs

- Never writes Loom queue/journal
- Never sets Approved without `yarn plan approve -Confirm`
- Never auto-synthesizes on `atlas sync pull`
- Agent synth requires `-UseAgent` (refused on auto path)
- Atlas Session/Ref/Brief kinds are not scanned in Phase B
