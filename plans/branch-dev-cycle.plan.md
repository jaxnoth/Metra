---
name: Branch-based ship cycle (bite)
product: Metra
overview: "Loom-owned ship cycle with thin metra bite desk façade; Yarn Approve/Pulse for unattended queue only; machine-gated protected merge."
status: implemented
phase: branch-dev-cycle
todos:
  - id: plan-scar
    content: "Repo plan scar + index entry"
    status: completed
  - id: registry-fields
    content: "protectedBranches / ownerAffirmPaths on Metra"
    status: completed
  - id: loom-ship-core
    content: "Loom ShipCycle helpers; Invoke-LoomShip authority"
    status: completed
  - id: ship-state-tuple
    content: "Persist reviewed immutable tuple + review identity"
    status: completed
  - id: bite-facade
    content: "metra bite façade over Loom ShipCycle"
    status: completed
  - id: loom-wire-runner
    content: "Wire runner/review/daily -Merge through ShipCycle"
    status: completed
  - id: yarn-handoff
    content: "Pulse prepare-bing hop uses Base pack when ship state present"
    status: completed
  - id: hooks-branch-aware
    content: "Work vs protected hooks; ship lock not bare env"
    status: completed
  - id: pack-sha-bind
    content: "prepare-bing -Base; pack binds merge-base + HEAD"
    status: completed
  - id: docs-decisions
    content: "Playbooks + Decisions scar"
    status: completed
  - id: tests-bite-gate
    content: "Gate + adversarial ship-marker tests"
    status: completed
  - id: dogfood-hold-e3c
    content: "Dogfood Metra bite; hold CDM E3c"
    status: completed
relatedPlans:
  - path: plans/branch-dev-cycle.proposal.md
    role: provenance
  - path: plans/loom-product-boundary.plan.md
    role: prior-boundary
---

# Branch-based ship cycle (one path: Loom-owned, bite façade)

## Verdict

Yarn prepares and schedules unattended work. Loom owns one ship-cycle implementation. Desk agents call `metra bite *` and bypass the Yarn scheduler, not governance. Protected branches land only through `Invoke-LoomShip` after validating a persisted reviewed tuple. CDM E3c stays held until `bite start` works on Metra.

## Design

See Cursor plan `branch-dev-cycle_15c85a2b` and proposal `plans/branch-dev-cycle.proposal.md` (superseded as authority; kept for provenance).

Authority:

- Surveyor/Yarn Approve required for Loom queue ingest only (not desk bite).
- Bing machine `verdict: approve` + `Invoke-LoomShip` tuple validation authorize protected mutation.
- `METRA_LOOM_SHIP` is a post-validation hook/recursion marker only; paired with a short-lived ship lock.

## Done when

Desk and Loom queue share one ShipCycle; bare env marker cannot mutate protected; Metra dogfoods via bite; CDM E3c not started.
