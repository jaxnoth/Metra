---
metraMemory: procedural-architectural
patternSchemaVersion: 1
defaultContext: false
patternId: guild-agent-interaction
owner: metra
cabinet: guild
status: active
implemented: true
loadWhen:
  - inspect engine
  - implementer engine
  - loopPaused
  - Ask uptime
ceiling:
  - Models propose and implement; deterministic policy decides what may run
  - Only the operator accepts
  - Loom calls Metra through adapters only (no private script imports)
  - Tier 1 engine faults pause dequeue; auto-recover transients without permission theater
relatedDecisions:
  - "2026-08-31 AutoProgram dependency direction"
  - "2026-08-25 Inspect engine configuration split"
  - "2026-08-12 Metra Inspect engine independence"
  - "2026-09-02 Loom Slice 6 unattended loop"
relatedPlaybooks:
  - docs/playbooks/loom.md
  - docs/playbooks/inspect-loop.md
supersedes: null
---

# Guild Agent Interaction Pattern

## Intent

Governs how coding and review agents interact with Metra/Loom: adapters, engine tiers, stop vs auto-recover, and authority boundaries.

## Actors

| Actor | Role |
|-------|------|
| Cursor Agent / implementer | Bounded isolated run; may not accept or expand scope |
| Metra Inspect / Ask engine | Review cognition; separate pin preferred from coding model |
| Loom hub | Policy, transitions, pause state, journals |
| Metra adapters | Only allowed Loom-to-Metra call path |
| Operator | Billing/key/pin choices; acceptance; resume after Tier 1 pause |

## Inputs / outputs

**In:** Context package (queue item, plan slice, paths, prior failures); engine health.

**Out:** Implementation/review evidence; optional `loopPaused` with reason; never silent skip of inspect/verify.

## Rules and ceilings

1. **Core safety:** Models propose, implement, and review. Deterministic policy decides what may run. Only the operator accepts.
2. Loom domain code reaches Metra only through documented adapters (routing, inspect, verify, Ops health). Forbidden: importing `scripts/private/*` into Loom.
3. Inspect may use dedicated `inspect.*` pin; independence preferred (coding vs review family). Same-family runs are first-pass review, not sole ship proof.
4. Transient engine faults: auto-recover (Ops/sidecar restart, bounded retry) without asking permission to restart.
5. Licensing / quota / credentials / exhausted recovery: **stop** - item or global pause (`loopPaused`); do not dequeue next; do not mark `completed` by skipping review.
6. Agent must not feed Bing pack bodies back into the fix loop (fix-queue / latest only).
7. Slice 6: Tier 1 inspect/engine faults set enriched pause; subsequent `loom loop` fails closed until cleared.

## State or contract references

- Loom `Adapters/Metra.Adapters.ps1`; inspect/verify request-result schemas
- `loopPaused` / `pauseReason` on Loom `state.json`
- `.cursor/rules/metra-inspect-loop.mdc`

## Flow

```text
implementer or inspect call
  -> transient? auto-recover and retry
  -> Tier 1 operator input needed? pause / block
  -> evidence back to hub
  -> hub alone mutates queue (never the model)
```

## Human ritual

[inspect-loop.md](../playbooks/inspect-loop.md); [loom.md](../playbooks/loom.md) Slice 6 pause notes; `.\metra.ps1 ask engine show`.

## Anti-patterns

- Asking the operator for permission to restart Ops when the harness already owns recovery
- Continuing the overnight loop while inspect is unrecoverably down
- Loom importing Metra private implementation files
- Treating inspect-clean alone as ship-ready when coder and inspector share an engine family

## Evidence

- Contract / code: Loom adapters; `Loop.ps1` pause; Inspect engine selection
- Tests: `tests/Loom/Loom.Boundary.Tests.ps1`, `Loom.Loop.Tests.ps1`, `Loom.InspectAdapter.Tests.ps1`
- Playbook: `docs/playbooks/inspect-loop.md`, `docs/playbooks/loom.md`
- Decision scar: Adapter direction (2026-08-31); Inspect engine split (2026-08-25); Inspect engine independence (2026-08-12); Slice 6 pause (2026-09-02); Inspect context economy (2026-09-01)
- Shipped slice: Loom Slices 3-6 + Metra inspect loop
