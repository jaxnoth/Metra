# iOS Vision Ask - client handoff

Docs-only contract for a future Metra iOS client. Server surfaces are live in Ops (`POST /api/vision/ask` preferred; contract-aware `POST /api/ask`). This file does not implement Xcode or LocalAssist.

## Surfaces (client classifies before send)

| Client intent | Online | Offline |
| --- | --- | --- |
| Relational / companion | Vision (`mode=vision`, `intent=relational`) | LocalAssist - provenance only; never claim Ops/Desk success |
| Desk / portfolio Ops | Bounded Desk Ask (`mode=bounded`, `intent=desk`) | Fail closed (`desk_requires_connectivity`) |
| Park / capture | Explicit Capture (`POST /api/capture`) | Explicit only - never inferred from social Vision phrasing |

Uncertain classification: stay relational. Do not claim Desk success. Do not auto durable Capture.

## Endpoints

Prefer:

```http
POST /api/vision/ask
Content-Type: application/json
```

Compatible alternative: `POST /api/ask` with the same contract body. Ops dispatches **before** `Get-MetraDeskAskResult`. Vision never enters AskLane.

`POST /api/ask` with `mode=bounded` + `intent=capture` is rejected - use `POST /api/capture`.

## Request (contractVersion 1)

```json
{
  "contractVersion": "1",
  "surface": "ios",
  "mode": "vision",
  "intent": "relational",
  "message": "User-supplied turn",
  "conversationId": "…",
  "turnId": "client-generated-idempotency-id",
  "capabilities": {
    "localAssistAvailable": true,
    "durableWritesAllowed": false
  },
  "context": {
    "client": "metra-ios",
    "clientVersion": "…"
  }
}
```

### Valid combinations

| surface | mode | intent | Path |
| --- | --- | --- | --- |
| ios | vision | relational | Vision engine |
| ios | bounded | desk | Desk Ask |
| ios | bounded | capture | Explicit Capture (`/api/capture`) |
| desk | bounded | desk | Desk Ask |
| desk | bounded | capture | Explicit Capture |

### Invalid (reject - never silent-normalize)

- `mode=vision` with `intent=desk` or `capture`
- Vision with `durableWritesAllowed=true`
- Vision redirected to Desk because the engine failed
- Treating HTTP 200 from Desk/Capture as Vision success

## Response provenance (always read)

```json
{
  "contractVersion": "1",
  "status": "answered",
  "source": "ops-vision",
  "mode": "vision",
  "intent": "relational",
  "response": { "text": "…" },
  "grounding": { "opsReached": true, "portfolioGrounded": false },
  "routing": {
    "handler": "vision-engine",
    "askLaneUsed": false,
    "captureSuggested": false,
    "engineInvoked": true
  },
  "writes": {
    "attempted": false,
    "committed": false,
    "durableWrite": "not_attempted"
  },
  "correlation": {
    "conversationId": "…",
    "turnId": "…",
    "serverRequestId": "…"
  }
}
```

**Sources:** `ops-vision` | `local-assist` | `ops-desk` | `capture` | `client`

Online Vision success requires: `source=ops-vision`, `askLaneUsed=false`, `captureSuggested=false`, `engineInvoked=true`, writes not attempted/committed.

Offline LocalAssist (client-built): `source=local-assist`, `opsReached=false`, `portfolioGrounded=false`, same routing/write invariants.

## Connectivity fail-closed (Desk offline)

```json
{
  "status": "unavailable",
  "source": "client",
  "mode": "bounded",
  "intent": "desk",
  "reason": "desk_requires_connectivity",
  "detail": "ops_unreachable",
  "grounding": { "opsReached": false, "portfolioGrounded": false },
  "writes": {
    "attempted": false,
    "committed": false,
    "durableWrite": "not_attempted"
  }
}
```

Unsent text may be a clearly labeled local draft only - not a durable Metra Capture write under this contract.

## Error reasons

`invalid_contract` | `unsupported_contract_version` | `vision_unavailable` | `ops_unreachable` | `desk_requires_connectivity` | `write_not_allowed` | `route_boundary_violation` | `engine_failure`

Forbidden: `status=answered` + `source=ops-vision` when AskLane, Capture templates, PowerShell companion branches, LocalAssist, or non-engine fallback answered the turn.

## Client checklist

1. Classify relational vs desk vs capture before choosing a path.
2. Relational + online -> `POST /api/vision/ask` (or contract body on `/api/ask`).
3. Relational + offline -> LocalAssist with `source=local-assist` provenance.
4. Desk + offline -> fail closed; do not fake Ops.
5. Park only via explicit Capture - never because Vision was social/ambiguous.
6. Treat provenance fields as the success signal - not HTTP status alone.
7. Never enable durable writes on Vision turns.

## Server proof

- Handler: `Invoke-MetraVisionAskHandler` (no AskLane)
- Prompt: `engines/vision-ask/system.md`
- Provenance: `routing.askLaneUsed=false` on Vision answers
- Telemetry: `metra.ask.routed` under `%LOCALAPPDATA%\Metra\ask\events.jsonl`
- Tests: `tests/Metra.VisionAsk.Contract.Tests.ps1`
- Scars: `docs/Decisions.md` (2026-08-29 iOS Vision Ask contract scars)
