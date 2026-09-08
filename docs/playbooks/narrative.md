---
metraMemory: procedural
defaultContext: false
loadWhen:
  - narrative
  - narrative engine
  - scenario pack
  - adventure pack
  - lesson simulation
ceiling:
  - AI never owns narrative state or scoring
  - Generated prose is transient; sessions expire
  - Decision Narrative Engine ownership must stay promoted
---

# Narrative Engine

State is truth. AI is narrator only.

## Commands

```powershell
.\metra.ps1 narrative packs
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
| `narrative/packs/<packId>/scenario.yaml` | Durable definitions |
| `%LOCALAPPDATA%\Metra\narrative\sessions\<id>\` | Disposable `state.json`, `events.jsonl`, `summary.json` |
| `%LOCALAPPDATA%\Metra\narrative\index.json` | Session index including forgotten summaries |

### Pack authoring (v0 format)

`scenario.yaml` must be **JSON-syntax only** (YAML 1.2 JSON subset). The file starts with `{` and is parsed with `ConvertFrom-Json`. Block-style YAML (`key:` / `- item` indentation) is **not** accepted in v0 and will fail load.

Keep the `.yaml` extension for the planned path, but edit packs as JSON documents. A future slice may add a real YAML loader; until then do not convert these files to conventional YAML.

Session ids are `n` + 12 hex chars (whitelist `^n[0-9a-fA-F]{12}$`).

## Rules

1. Only declared moves mutate state.
2. Narration failure never blocks a valid transition.
3. Do not store generated prose.
4. Pack fingerprint is bound at session start; pack edits require a new session.
5. Atlas/Codex remain knowledge homes; packs may cite them via `source`.

Companion Decision: Narrative Engine ownership (promoted). Atlas: `plan:metra-narrative-engine-v1`.
