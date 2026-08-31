---
metraMemory: procedural
defaultContext: false
loadWhen:
  - OCC
  - operator contract
  - decision registry
  - ask recall
  - capture
  - portfolio facts home
  - agentic maturity
ceiling:
  - Never auto-promote OCC; classify home before promote
  - Refuse OCC for product policy, project playbooks, solutions, Decision scars
---

> Moved from `AGENTS.md` during A2 desk split. Preserve A1 done-when / On hard stop content unless intentionally revised.

# Portfolio memory governance

Durable homes and promotion rules. Portfolio Operations Principles: [docs/Decisions.md](../Decisions.md).

## Operator Communication Contract

Optional **Operator Communication Contract** (learned soft guidelines): `.\metra.ps1 profile` -> `docs/operator-contract.json` + `.cursor/rules/metra-learned.local.mdc` (gitignored; see examples).

After repeated working-preference corrections (or explicit remember), classify the home first, then propose OCC only for soft portfolio collaboration rhythm. On yes run `.\metra.ps1 profile promote`. Never auto-promote. Refuse OCC for portfolio-wide product rules (Decisions / README / base persona), project-local playbooks (`AGENTS.md`), TicketTracker `solutions/`, and Decision Registry scars. Say the home when proposing a durable write. Learned guidelines are soft; routing and professional sink still win.

## Ask Session Journal + Capture Inbox

Journal (`docs/ops-ask-log.local.json`) is canonical Ask evidence (recent continuity window). Capture (`docs/ops-capture.local.json`) is thin intake with immutable `derivedFrom` lineage - not a second OCC, not always-on agent memory, and never auto-loaded into routing or Ask prompts. Prefer `.\metra.ps1 ask sessions|log|get|recall` and `.\metra.ps1 capture list|note|promote` (or say context unavailable) over inventing cross-chat recall. Ops Recent **Resume** / **Recall into Ask** and Ask session summarization (extractive) are deliberate labeled continuity - not silent Capture injection. Classify the eventual durable home before OCC/Decision promote. Keep in view (Attention) != Save for portfolio (Capture). Observation is cheap; governance (promote into Decisions / OCC / AGENTS / tracked files) stays deliberate via Host/CLI.

## Decision Registry

Optional **Decision Registry** (Operational Why Memory): `.\metra.ps1 decisions` -> `docs/decision-registry.json` (gitignored; retrieved via search/ctx, not always-on).

For operational why-we-chose scars, use `.\metra.ps1 decisions search` / `ctx -Query` Why Here hits before transcript archaeology. Promote requires why + confidence + evidence. Harvest creates candidates only. When stating a route, prefer ledger-backed Why Here (decision + why); never invent operational why.

## Atlas (portfolio knowledge bus)

**Path map (where we are / next / later):** [docs/portfolio-memory-path.md](../portfolio-memory-path.md) - reopen that file when memory work feels scattered. This playbook stays promotion rules only.

Sibling project `C:\Projects\Atlas` (`.\Atlas.ps1` / `.\metra.ps1 atlas`). **Metra routes. Atlas stores. Notion persists.**

| Content | Authority | Atlas / Notion |
|---------|-----------|----------------|
| Soft collaboration rhythm | OCC | never sync |
| Operational why | Decision Registry | Reference pointer only |
| Portfolio product policy | Decisions.md | Reference pointer only |
| Cross-product plans/docs/briefs/parked | **Notion Plans via Atlas** | two-way bus (`put` local; `sync push`/`publish` remote) |
| Institutional KB | Codex | not Atlas |
| Capture / Ask journal | local | Sessions only after explicit promote |

`ctx -Query` may append up to three Atlas citations when Atlas is healthy - never always-on, never Ask/OCC injection. Deletion sync unsupported in v1. Vectors deferred.

Routing vs Codex: KB/Nice vocabulary -> Codex; plans/briefs/expanded memory/Notion sync -> Atlas.

## For whom? and maturity

- **For whom?:** cite registry `serves` when present (audiences of the work). Do not invent individuals, requesters, owners, approvers, or interpersonal memory - ticket people facts stay in TicketTracker evidence.
- **Portfolio facts** need a home (routing / ctx / Decision Registry / Decisions.md / OCC / project AGENTS.md / Ops health / serves / workflow maturity). Do not invent a parallel home.
- **Workflow agentic completeness:** score Current vs Target with [docs/Agentic-Maturity.md](../Agentic-Maturity.md) (L1-L6 gates + scorecard). Prefer gap lists over portfolio percentages. Higher is not always better; durable writes stay gated.

## Output channels

- Idea / brainstorm requests stay conversational. Do not edit files, commit, or open a pull request until the operator explicitly asks to implement.
- Durable writes (code, docs, ticket `post`/`recommend`, commits, ADRs, registry): professional only; [Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing) is artifact-quality only, not chat style.
- Slack/Teams/email drafts for the operator: Metra voice OK if still sendable. Redistribution: flatter, less personal humor.
- Personality may evolve when change improves the portfolio. Operator identity belongs in the local overlay; working-preference evolution belongs in the Communication Contract; portfolio-wide policy belongs in Decisions / base rule. Vet base edits so routing and professional sink never regress.
