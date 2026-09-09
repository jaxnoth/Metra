---
metraMemory: procedural
defaultContext: false
loadWhen:
  - narrative
  - narrative engine
  - scenario pack
  - adventure pack
  - lesson simulation
  - ink
ceiling:
  - AI never owns narrative state or scoring
  - Generated prose is transient; sessions expire
  - Decision Narrative Engine ownership must stay promoted
  - Ink Story state is truth; Ask locomotive is presentation only
---

# Narrative Engine

State is truth. AI is narrator only. Packs are **Ink** (Windows `ink-engine-runtime`); capability contracts (moves, bind, leave) stay face-stable.

## Commands

```powershell
.\metra.ps1 narrative packs
.\metra.ps1 narrative compile              # all packs
.\metra.ps1 narrative compile derelict_station
.\metra.ps1 narrative start derelict_station -Seed 42
.\metra.ps1 narrative start pbi_gateway_ha_prep
.\metra.ps1 narrative status
.\metra.ps1 narrative moves
.\metra.ps1 narrative move enter_corridor
.\metra.ps1 narrative narrate
.\metra.ps1 narrative narrate -FallbackOnly
.\metra.ps1 narrative end -Summary 'completed quiet escape'
.\metra.ps1 narrative list
.\metra.ps1 narrative expire -WhatIf
.\metra.ps1 narrative forget <sessionId>
.\metra.ps1 narrative lifecycle <sessionId> archived
```

## Layout

| Path | Role |
|------|------|
| `narrative/packs/<packId>/pack.json` | Metra metadata (id, mode, title, setting, objectives) |
| `narrative/packs/<packId>/story.ink` | Authoring source |
| `narrative/packs/<packId>/story.json` | Compiled Ink JSON (committed; required to play) |
| `narrative/packs/<packId>/story.graph.json` | Compile-time graph for Inspect/tooling (not play runtime) |
| `narrative/vendor/ink/` | Tracked `ink-engine-runtime.dll`; `inklecate.exe` gitignored (auto-download on compile) |
| `%LOCALAPPDATA%\Metra\narrative\sessions\<id>\` | Disposable `state.json` (includes `inkState`), `events.jsonl`, `summary.json` |
| `%LOCALAPPDATA%\Metra\narrative\index.json` | Session index including forgotten summaries |

### Pack authoring (Ink)

1. Edit `story.ink` and `pack.json`.
2. Use **non-bracket** choices so Metra move tags bind to `Choice.tags`:
   `* Enter the dark corridor # move:enter_corridor`
3. Endings use Metra-visible runtime tags: `# terminal:success` or `# terminal:fail`.
4. Run `.\metra.ps1 narrative compile <packId>` (inklecate + Metra validation + `story.graph.json`).
5. Commit `story.json` and `story.graph.json` so play needs no build step on another machine.

Compile fails closed if: actionable choice missing `# move:`, duplicate move ids, invalid terminal tags, or `pack.json` id mismatch.

Session ids are `n` + 12 hex chars (whitelist `^n[0-9a-fA-F]{12}$`).

Fingerprint binds `pack.json` + `story.json` at session start.

## Rules

1. Only current Ink choices (with `# move:` ids) mutate the story.
2. Narration failure never blocks a valid transition.
3. Do not store Ask-generated prose as authority (Ink `lastText` is pack text).
4. Pack fingerprint is bound at session start; pack edits require a new session.
5. Atlas/Codex remain knowledge homes; packs may cite them via `source` in `pack.json`.
6. Do not put Ink under Ask `engines/` - Narrative car only.

## Faces and Ask (capability car)

CLI is the control plane. Ops Ask is the training seat: board via enter cues (`play derelict station`), stay on bind inertia, reply with choice number / move id / plain wording. Narration uses the Ask locomotive when available; fallback uses Ink `lastText` + numbered choices.

Companion Decisions: Narrative Engine ownership (`dd9105a2d71`); Capability bind (2026-09-08); Narrative packs are Ink (2026-09-08). Atlas: `plan:metra-narrative-engine-v1`. Parked: Z-machine / IF Archive addon (Future-Development).
