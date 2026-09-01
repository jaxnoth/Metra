# AGENTS Authoring Standard

`AGENTS.md` is a desk index, not a procedure warehouse. This standard implements A2 / G2: lean AGENTS stubs plus on-demand playbooks under `docs/playbooks/*.md`.

## Policy anchor

- Desk model scar: [Decisions.md](Decisions.md) (2026-08-14 - Desk model for context and durable knowledge).
- Routing/context doctrine: [Context-Routing.md](Context-Routing.md) (Desk model section).
- Memory crosswalk: [Agentic-Maturity.md](Agentic-Maturity.md) (Memory stores crosswalk).
- G2 target: treat `AGENTS.md` like a Makefile - short, reviewed, human-curated; no AI-generated dumps.

## Vocabulary

### Storage

A file sitting on disk.

Examples:

- `docs/playbooks/*.md`
- `docs/Decisions.md`
- `decision-registry.json`
- `solutions/`
- `projects.json`
- git-tracked README files

### Context

What is inside the model window right now.

Examples:

- Always-on `.cursor/rules`
- Mounted `AGENTS.md` stubs
- Current chat
- Tool results in the active thread

### Memory

Anything that survives the session and comes back.

Memory must be typed, intentional, and bounded. Metra does not silently auto-inject durable storage into context.

### Default context

What Metra/Cursor load every turn without a trigger. This is the thing being managed.

**Review test:** Does this belong in default context? (Not: where should this file live?)

## Memory types

| Type | Role | Metra home | Default context? |
| --- | --- | --- | --- |
| Procedural | How to do things | Stub ceilings, playbook index, `docs/playbooks/*.md`, future A4 `SKILL.md` | Stub index and ceilings yes; playbook bodies no |
| Working | Current chat | Cursor / Ask in-thread messages | Yes, session only |
| Semantic | Facts | Decision Registry, OCC, `Decisions.md`, solutions, registry serves | Retrieved, capped, deduped |
| Episodic | What already happened | Ask Session Journal, chats, Attention, Capture promote path | Labeled recall only |

## Desk model

Storage is cheap. Context is expensive. Memory is only useful when retrieval is intentional. **Default context is a budget, not a warehouse.**

Context rot happens when storage is copied into context at session start.

A stub `AGENTS.md` is procedural context. It should route the agent, state ceilings, and point to cabinet files.

A playbook is procedural storage. It is read into context only when the task triggers it.

Semantic memory stays retrieved, capped, and deduped.

Episodic memory stays explicit through Journal, Recall, chats, or Resume. It is not a second always-on layer.

## Policy precedence

Shrink duplication; do not move duplication.

- Durable product policy lives in `docs/Decisions.md`.
- Routing/context doctrine lives in `docs/Context-Routing.md`.
- `_meta/AGENTS.md` is the orchestration index only.
- `.cursor/rules` are default-context behavior shims, not policy ledgers.
- Examples live in docs, not always-on rules.

## Stub structure

Every project `AGENTS.md` should use this order:

1. Route here when
2. Start here
3. Ceilings
4. On-demand playbooks
5. Token rules
6. Related

Starter template: [templates/AGENTS.stub.md](templates/AGENTS.stub.md).

## Stub budget

Default stub budget is **100 physical lines**, including blank lines and tables.

Configure override in `metra.config.json`:

```json
{
  "audit": {
    "agentsLineBudget": 100
  }
}
```

`.\metra.ps1 audit` reports `OK` or `WARN` per project. The warning is advisory only. Audit never edits files and never auto-splits stubs.

Playbook bodies under `docs/playbooks/*.md` do not count toward the stub budget.

## Cabinet rules

- Use `docs/playbooks/*.md` only (one doorknob; no alternate paths).
- One procedure per file.
- Keep cabinet files specific.
- Do not move generic background sludge into playbooks just to preserve it.
- Cabinet files are not mounted always-on.
- Playbook bodies load only when a task triggers a Read.

## Playbook front matter

Convention only - not a schema migration. Put at the top of cabinet files:

```yaml
---
metraMemory: procedural
defaultContext: false
loadWhen:
  - stuck session
  - investigate Colleague process
ceiling:
  - Confirm before Live action
  - Never kill datatel without explicit operator confirmation
---
```

**A4 readiness:** Front matter exists to support future retrieval and skill activation (playbook -> requestable playbook -> `SKILL.md`). It does not change behavior in A2.

**A2 non-goal:** A2 does not implement a playbook loader, retrieval engine, or `SKILL.md` runtime.

## Provenance

Every playbook moved from `AGENTS.md` during a desk split should include:

> Moved from `AGENTS.md` during A2 desk split. Preserve A1 done-when / On hard stop content unless intentionally revised.

## Write path

When adding durable knowledge, classify the home first:

- Procedural: playbook or stub pointer
- Semantic: `Decisions.md`, Decision Registry, OCC, `solutions/`
- Episodic: Journal / Capture / Recall path
- Working: current chat only

Then:

1. Dedupe against the target home.
2. Write to the correct home.
3. Update the stub index if a playbook was added.
4. Keep default context lean.

## Artifact prose (AISIGNS)

Durable writes use ordinary professional prose per [metra-persona Output channels](../.cursor/rules/metra-persona.mdc). Apply at **write time**, not only when Bing, inspect, or encoding review catches problems later.

Avoid in committed artifacts:

- Words: `pivotal`, `landscape`, `delve`, and the construction `not only X but also Y`
- Punctuation: em dashes (use `-`), Unicode arrows (use `->`), decorative symbols where ASCII suffices
- Structure: emoji as bullets or section markers

Chat voice may stay conversational; docs, playbooks, decisions, commits, and ticket bodies do not.

## Hard offs

- Never auto-generate `AGENTS.md` from model dumps.
- Never treat storage as context.
- Never mount full playbooks always-on.
- Never collapse cabinet files back into stubs during ticket pressure.
- Never auto-promote playbooks into Ask prompts or Cursor rules.
- Never hide a required safety ceiling only in a cabinet playbook.
- Never make Context Footprint Estimate a quality score, maturity score, or merge gate in A2.

## Audit hygiene

`.\metra.ps1 audit` reports per-project AGENTS line counts and a portfolio **Context Footprint Estimate** (report-only):

```
AGENTS.md: 217 lines WARN over budget 100

Context Footprint Estimate
--------------------------
AlwaysApply rules: 231 lines
  113 lines  .cursor\rules\metra-persona.mdc
   71 lines  .cursor\rules\metra-inspect-loop.mdc
   ...
Mounted AGENTS:    612 lines
Total estimated:   843 lines
```

Footprint sums `alwaysApply: true` `.cursor/rules/*.mdc` plus mounted project-root `AGENTS.md` files in audit scope. It excludes playbooks, authoring docs, README, Decision Registry, Journal/Capture, and rules with `alwaysApply: false`. Cursor may inject additional system/user content Metra cannot observe.

For external A2 review (Bing comparison lane), pack stub + playbooks only without unrelated working-tree noise:

```powershell
.\metra.ps1 inspect pack-only agents -Name Colleague
```

Writes `%LOCALAPPDATA%\Metra\inspect\pack-agents.md` and copies the pack to the clipboard.

## Harness note

Stub discipline helps immediately because mounted AGENTS files shrink the always-on prefix.

The target state is index-only load: stubs are always-on, cabinet files are read on trigger.

Cursor may still mount all workspace `AGENTS.md` files. Fewer workspace folder pins reduces mounted AGENTS count (operator choice; not auto-scripted). Future agent-requestable playbooks or A4 skill packs may improve harness behavior further.
