---
metraMemory: procedural-architectural
patternSchemaVersion: 1
defaultContext: false
patternId: guild-knowledge-promotion
owner: loom
cabinet: guild
status: active
implemented: true
loadWhen:
  - pattern promote
  - pattern score
  - atlas put
  - Slice 8
ceiling:
  - Promotion candidates require an accepted Loom item
  - Tracked Pattern file remains authoritative after Atlas publication
  - Gaps never auto-author Pattern bodies
  - Cabinet is organizational only (no guild special-case in promote)
relatedDecisions:
  - "2026-09-02 Patterns taxonomy and Pattern authority"
  - "2026-09-02 Loom Slice 8 Pattern promote"
relatedPlaybooks:
  - docs/playbooks/loom.md
supersedes: null
---

# Guild Knowledge Promotion Pattern

## Intent

Governs accept-gated scoring and Atlas publication of Pattern discoverability copies (Slice 8). Loom owns score/promote; Atlas publishes only.

## Actors

| Actor | Role |
|-------|------|
| `Invoke-MetraLoomPatternScore` | Lists promote candidates from accepted Evidence |
| `Invoke-MetraLoomPatternPromote` | Preview/Confirm gate; writes promotion ledger |
| Atlas put adapter | Local object; optional `-Publish` |
| Operator | Confirms promote; never transfers Pattern authority |

## Inputs / outputs

**In:** Accepted queue item; `docs/patterns/**` paths changed in baseline..completedCommit; validated Pattern front matter; content hash at accepted revision.

**Out:** Score report; Preview eligibility; Confirm → Atlas put (`pattern:<patternId>`) + `patterns/promotions.json` ledger + journal `pattern-promote`.

## Rules and ceilings

1. Item status must be `accepted` (not `completed`, not `accepted-pending-commit`).
2. Target path must stay under `docs/patterns/` after normalization (fail closed on escape/absolute).
3. Pattern must appear in the accepted commit range diff.
4. Working tree hash must match blob at accepted revision.
5. Same `patternId` + `contentHash` already promoted → reject.
6. Missing cite/file → not eligible; malformed front matter → reject that Pattern.
7. Publication does not transfer authority from the tracked file.

## State / contract refs

- Ledger: `{loomRoot}/patterns/promotions.json`
- StableId: `pattern:<patternId>`
- Atlas: put local unless `-Publish`

## Flow

```mermaid
flowchart TD
  evidence[Accepted_item_Evidence]
  score[pattern_score]
  preview[pattern_promote_Preview]
  confirm[pattern_promote_Confirm]
  atlas[Atlas_put]
  ledger[promotions_ledger]
  evidence --> score
  score --> preview
  preview --> confirm
  confirm --> atlas
  confirm --> ledger
```

## Human ritual

```powershell
.\metra.ps1 loom pattern score
.\metra.ps1 loom pattern promote -Path .\docs\patterns\guild\knowledge-promotion.md -Preview
.\metra.ps1 loom pattern promote -Path .\docs\patterns\guild\knowledge-promotion.md -Confirm
.\metra.ps1 loom pattern promote -Path .\docs\patterns\guild\knowledge-promotion.md -Confirm -Publish
```

## Anti-patterns

- Promoting from `completed` without daily accept
- Treating Atlas/Notion as authoritative Pattern store
- Auto-writing Pattern bodies from gap candidates
- Special-casing `cabinet: guild` in eligibility code

## Evidence

- CLI: `loom pattern score|promote` in `Invoke-LoomCommand`
- Module: `modules/Loom/Private/PatternPromote.ps1`
- Tests: `tests/Metra.Loom.Tests.ps1` (Slice 8 Pattern promote)
