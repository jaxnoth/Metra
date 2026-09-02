# Pattern schema (v1)

Convention for Pattern markdown under `docs/patterns/`. Not a runtime loader yet.

## Front matter

```yaml
---
metraMemory: procedural-architectural
patternSchemaVersion: 1
defaultContext: false
patternId: loom-review          # durable ID; unique across index.yaml
owner: loom                     # metra | yarn | loom | atlas
cabinet: null                   # guild | omit/null (filing only)
status: stub                    # stub | active | deprecated
implemented: false
loadWhen:
  - review
  - inspect
ceiling:
  - Example ceiling
relatedDecisions: []
relatedPlaybooks: []
supersedes: null
---
```

| Field | Required | Notes |
|-------|----------|-------|
| `patternSchemaVersion` | yes | `1` |
| `patternId` | yes | Kebab-case; stable when file moves |
| `owner` | yes | Runtime product that owns the method |
| `cabinet` | no | Organizational filing only (invariant: no runtime branches on cabinet) |
| `status` | yes | `stub` until behavior ships |
| `implemented` | yes | `true` only when Evidence shows shipped behavior |
| `loadWhen` | no | Exact phrases / aliases for future deterministic match |
| `defaultContext` | yes | Always `false` |

Rejected legacy fields: `product`, `domain` (use `owner` and `cabinet`).

## Body sections

Intent · Actors · Inputs/outputs · Rules/ceilings · State/contract refs · Flow · Human ritual · Anti-patterns · Evidence (required when `status: active`).

## ID uniqueness

1. Every Pattern file declares exactly one `patternId`.
2. [`index.yaml`](index.yaml) maps each `patternId` to one repo-relative path under `docs/patterns/`.
3. Duplicate IDs (including case variants) fail verification and must block acceptance when runtime validation exists.
4. Plans cite IDs only: `patterns: [loom-review]` - never absolute paths.
5. Atlas StableId form when promoted: `pattern:<patternId>`.

## Path containment (future loader)

Normalize repository root and candidate path before containment. Fail closed on absolute paths, `..` escapes, and symlink targets outside the repo. Missing optional cites warn; malformed front matter rejects that Pattern from context.
