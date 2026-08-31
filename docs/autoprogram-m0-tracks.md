# AutoProgram / Loom — git track separation (M0)

**Date:** 2026-08-31  
**Purpose:** Keep boundary correction and feature work reviewable. **Do not merge mixed diffs.**

Product name: **Loom** (chosen 2026-08-31). Working name through M2: **AutoProgram**.

---

## Canonical status (operator + Bing)

**Phase A committed (`7d90ebe`); Slice 3 not started; boundary M0–M1 complete.**

| Label | State |
|-------|--------|
| Slice 1–2 (Phase A) | **Committed** `7d90ebe`, 13/13 Pester |
| Slice 3 (branch runner) | **Not started** — frozen until M2 partial + operator gate |
| Slices 4–8 | Not started — frozen |
| Boundary M0 | **Complete** (this doc + focused packs) |
| Boundary M0.5 | **Complete** — commit `7d90ebe`, tag `boundary-correction-start` |
| Boundary M1 | **Complete** — ADRs, boundary plan, tracks doc, portfolio-memory-path |

---

## Tracks (never combine in one commit)

### Track A — AutoProgram Phase A (Loom working name)

**M0.5 commit scope only:**

| Path | Role |
|------|------|
| `scripts/private/Autoprogram.ps1` | Phase A implementation |
| `tests/Metra.Autoprogram.Tests.ps1` | Phase A Pester (13 tests) |
| `metra.ps1` | `autoprogram` dispatch only — **⚠ mixed hunks today** (also routing edges, ops `-Foreground`; see below) |
| `scripts/Metra.psd1` | Export wiring for autoprogram |
| `scripts/Metra.psm1` | `Invoke-MetraAutoprogramCommand` delegate |

**Commit message (M0.5):** `feat(autoprogram): Phase A baseline (Slices 1–2 state + triage)`

**Tag (M0.5):** `boundary-correction-start` → **`7d90ebe`** (landed 2026-08-31)

### Track B — Routing Phase 5 review

| Path | Notes |
|------|--------|
| `scripts/private/Routing.ps1` | +518 lines delta |
| `docs/routing-graph-phase5-review.plan.md` | Untracked plan |
| `docs/routing-graph-evolution.plan.md` | Modified |
| `tests/Metra.Tests.ps1` | Routing-related tests |

### Track C — Ask / Cursor resilience

| Path | Notes |
|------|--------|
| `scripts/private/AskEngine.ps1` | Sidecar recovery |
| `scripts/private/AskLane.ps1` | |
| `scripts/private/AskRecommend.ps1` | |
| `scripts/private/Chats.ps1` | |
| `engines/cursor/*` | SDK pin, session cache, model-selection |
| `tests/Metra.AskLane.Tests.ps1` | |

### Track D — Ops / Inspect incidental

| Path | Notes |
|------|--------|
| `scripts/private/Inspect.ps1` | |
| `scripts/private/OpsHost.ps1` | |
| `scripts/private/OpsServer.ps1` | |
| `scripts/private/Snapshot.ps1` | |
| `scripts/bootstrap/Start-MetraOps.ps1` | |

### Track E — Boundary / ADR docs (M1 commit)

| Path | Notes |
|------|--------|
| `docs/autoprogram-product-boundary.plan.md` | Approved boundary plan |
| `docs/autoprogram-m0-tracks.md` | This file |
| `docs/Decisions.md` | Loom ADRs (2026-08-31) |
| `docs/portfolio-memory-path.md` | Loom layer cross-link |

**Commit message (M1):** `docs(loom): M1 boundary ADRs, plans, and portfolio memory links`

**Rule:** Track A commit must contain **zero** hunks from Tracks B–D.

### M0.5 staging note (`metra.ps1`)

As of M0 (2026-08-31), `metra.ps1` combines **Track A** (`autoprogram` verb + handler) with **Track B** (routing `edges propose/review/affirm`, `-MinCount`, `-Status`) and **Track D** (ops `-Foreground`, `Start-MetraOpsDesk`). M0.5 must use **`git add -p metra.ps1`** (or equivalent) to stage only the `autoprogram` hunks, **or** land routing/ops commits first and rebase Track A onto a clean autoprogram-only delta.

---

## M0 artifacts

| Artifact | Path |
|----------|------|
| Roadmap plan pack | `%LOCALAPPDATA%\Metra\inspect\pack-plan.md` |
| Track A focused pack | `%LOCALAPPDATA%\Metra\inspect\autoprogram-phase-a-pack.md` |
| Pester proof | `Invoke-Pester tests/Metra.Autoprogram.Tests.ps1` → 13/13 |

---

## Freeze (until operator gate after M2 partial)

No implementation work on Slices 3–8, plan synthesize, or unattended loop until:

1. M0.5 — Phase A committed + tagged  
2. M1 — ADRs linked  
3. M2 partial — module + adapters + isolation gate green  
4. Explicit operator **go** for Slice 3  

See [autoprogram-product-boundary.plan.md](autoprogram-product-boundary.plan.md).
