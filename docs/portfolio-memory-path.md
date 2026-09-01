# Portfolio memory path (operator map)

**One place to reopen when memory work feels scattered.**  
This is the roadmap map. Authority and promotion rules stay in their homes (below). Update this file when the path changes - do not invent a second map.

**Last oriented:** 2026-08-31 (Loom boundary M1; Metra 0.1.15 desk Ask sidecar ops)  
**Stable idea:** Metra routes. Atlas stores. Notion persists. **Loom** executes governed delivery. Vectors accelerate retrieval later - they never become truth.

---

## Where you are (one glance)

```text
NOW (shipped)
  Registry + ctx + Decision Registry + Ask journal/Capture
  -> Desk Ask engine ops (sidecar health, agent dispose, opaque recovery) - Metra 0.1.15
  -> Atlas bus (StableIds) -> Notion Portfolio Memory
  -> iOS Vision Ask contract (relational surface; no AskLane)

NEXT (when continuity hurts)
  Commit-triggered Atlas Sessions (durable "what changed")
  Explicit Capture/Session promote habits
  iOS Bounded Desk Ask (separate from Vision)

LATER (when search gets noisy)
  Vector seam over StableIds (optional accelerator)
  Local Chroma/LanceDB or Notion AI search first
```

---

## Layer cheat sheet (do not collapse these)

| Layer | Job | Home |
| --- | --- | --- |
| Routing registry + `ctx` | Which project / bounded handoff | Metra |
| Decision Registry | Operational why-we-chose | Metra (`.\metra.ps1 decisions`) |
| Decisions.md | Product policy scars | Metra `docs/Decisions.md` |
| OCC | Soft collaboration rhythm only | Metra profile / learned overlay |
| Ask journal + Capture | Continuity / thin intake | Local Metra (promote deliberately); desk sidecar ops scar Decisions 2026-08-30 |
| **Atlas** | Portfolio knowledge bus | `C:\Projects\Atlas` |
| Notion Portfolio Memory | Cloud persist for Atlas | [Metra Portfolio Memory](https://www.notion.so/Metra-Portfolio-Memory-3c937328878a8104a1f0e1adad3658cb) |
| Codex | Institutional KB | Codex (not Atlas) |
| **Loom** (AutoProgram through M2) | Governed plan execution (queue, journal, review, operator acceptance) | Metra-hosted module; `%LOCALAPPDATA%\Metra\autoprogram\`; [autoprogram-product-boundary.plan.md](autoprogram-product-boundary.plan.md) |
| TicketTracker | Tickets | TicketTracker (not memory bus) |
| iOS Vision Ask | Relational companion surface | Ops `/api/vision/ask` - not Desk AskLane |
| **Vectors (future)** | Semantic find over StableIds | Not built - see Phase C |

Promotion rules: [playbooks/portfolio-memory-governance.md](playbooks/portfolio-memory-governance.md).

---

## Phase A - Structured path (DONE)

**Goal:** Expand memory without a vector database.

| Milestone | Status | Proof |
| --- | --- | --- |
| Atlas sibling project (Stub + Notion) | Done | `C:\Projects\Atlas`, `.\Atlas.ps1` / `.\metra.ps1 atlas` |
| StableIds + provenance on every object | Done | Atlas object contract |
| Notion Plans / Sessions / References | Done | Portfolio Memory root + DBs |
| `put` local; `sync push` / `publish` remote | Done | Atlas Sync docs |
| Decision: vectors deferred, not authority | Done | Decisions.md 2026-08-27 Atlas |
| Design note for future vectors | Parked design | Notion [Vector Store Seam](https://www.notion.so/Metra-Vector-Store-Seam-Expanded-Memory-Path-3c937328878a810eb215c996c359244a) (`plan:metra-vector-store-seam`) |

**Operator commands:**

```powershell
cd C:\Projects\Atlas
.\Atlas.ps1 health
.\Atlas.ps1 search "<query>"
.\metra.ps1 atlas   # from Metra when wired
```

**Hard offs already locked:** OCC / Decision Registry / Decisions.md are not two-way synced as authority. Codex stays institutional KB. Deletion sync unsupported in v1.

---

## Phase B - Continuity without vectors (NEXT)

Do these before building embeddings. They fix "I can't find what we did" without semantic search.

| Bite | Why | Status |
| --- | --- | --- |
| Desk Ask sidecar ops (health, dispose, opaque recovery) | Journal/Capture/Ask continuity needs a trustworthy engine, not a wedged listener | **Shipped** 2026-08-30 - Metra **0.1.15**; Decisions 2026-08-30 Ask sidecar scar |
| Commit-triggered Atlas Sessions | Durable per-commit recall; searchable via Atlas | Escalated in Future-Development; not shipped |
| Explicit Capture → Session / Plan promote | Intake becomes portfolio memory on purpose | Habit + CLI exists; keep deliberate |
| iOS Vision Ask contract | Relational phone turns never hit Desk AskLane | **Shipped** 2026-08-30 - [ios-vision-ask-contract.md](ios-vision-ask-contract.md) |
| iOS Bounded Desk Ask | Portfolio Ops from phone when online | Separate from Vision; after Vision contract |
| Ani / Grok bridge retirement | Continuity moves to Atlas Sessions + iOS Metra | Transitional - see Future-Development |

**Open when stuck on phone continuity:** Vision vs Bounded is a **surface** choice, not a memory-store choice. Memory still lands via Capture/Session/Atlas promote.

---

## Phase C - Vector seam (LATER)

Only when Phase A/B retrieval feels noisy (too many keyword hits, cross-project "find similar" fails, free-form session recall needs meaning not tags).

| Rule | Meaning |
| --- | --- |
| Vectors are optional | Core routing + Atlas work if the vector layer is down |
| Vectors are not truth | Every hit returns StableId + provenance back to Atlas/Notion/Decision object |
| Prefer small start | Session summaries first; or Notion AI search; or local Chroma/LanceDB |
| Atlas search `Semantic` | Reserved today - throws until a provider ships (`Atlas/docs/Search.md`) |

**Design source (do not duplicate long-form here):**  
[Metra – Vector Store Seam & Expanded Memory Path](https://www.notion.so/Metra-Vector-Store-Seam-Expanded-Memory-Path-3c937328878a810eb215c996c359244a)

**Atlas Plans pointer:** StableId `plan:metra-vector-store-seam`

**Trigger checklist (all optional - use judgment):**

1. Notion / Atlas volume makes keyword search noisy  
2. Need cross-project long-horizon "similar decision" recall  
3. Free-form session text queried by meaning  
4. Agent/iOS auto-retrieve without explicit IDs  

If none of those hurt yet - stay on Phase B.

---

## What not to mix up

| Feeling | Wrong conclusion | Right move |
| --- | --- | --- |
| "Ask failed with empty SDK detail" | Need vectors or a new memory store | Check `/health` (consecutive errors), sidecar recycle, opaque recovery path; wedged agent ≠ memory gap |
| "I can't find that chat" | Need vectors now | Session summary → Atlas Session; or Ask journal recall |
| "Phone sounded like Capture" | Break AskLane heuristics | Vision contract path (`/api/vision/ask`) - already shipped |
| "Need one memory brain" | Universal Memory Engine | Keep typed homes; Atlas is the bus only |
| "Notion has the vector design" | Vectors must be built next | Design is parked; Phase B first |
| "Atlas search is weak" | Replace Notion with embeddings | Improve titles/tags/Sessions; Semantic later |

---

## Reopen menu (when lost)

1. **This file** - where am I on the path?  
2. [portfolio-memory-governance.md](playbooks/portfolio-memory-governance.md) - which home do I write to?  
3. [Decisions.md](Decisions.md) Atlas + Vision + Ask sidecar scars - what is locked?  
4. Notion [Portfolio Memory](https://www.notion.so/Metra-Portfolio-Memory-3c937328878a8104a1f0e1adad3658cb) - what is already in the cloud?  
5. Notion [Vector Store Seam](https://www.notion.so/Metra-Vector-Store-Seam-Expanded-Memory-Path-3c937328878a810eb215c996c359244a) - Phase C design only  
6. [ios-vision-ask-contract.md](ios-vision-ask-contract.md) - phone relational vs desk  
7. `C:\Projects\Atlas\README.md` - CLI how-to  

---

## How to update this map

When a Phase B or C bite ships or parks:

1. Flip the Status cell in this file (one line).  
2. If it is product policy, add/adjust Decisions.md.  
3. If it is operational why, Decision Registry.  
4. If it is a plan body for the bus, Atlas `put` / Notion Plans - not a second Metra roadmap.

Do not grow Future-Development.local.md as the path map - that file is a backlog ocean; this file is the trail.
