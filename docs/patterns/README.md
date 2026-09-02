# Metra Patterns

Architectural method docs for how **Metra · Yarn · Loom · Atlas** are designed to work. Peer-programmer teaching surface. Not operator command checklists (those stay in [playbooks](../playbooks/)).

**Status:** P0 cabinet + P1 active seeds + **P2/P3 runtime** (`scripts/private/Patterns.ps1`: Loom package attach, Yarn synthesize match + gap checklist). Slice 8 promote still deferred.

## Purpose

Patterns explain designed behavior (ceilings, actors, flows). Playbooks tell an operator what to type. Decisions explain why. Formal plans authorize a bounded delivery. Code and contracts enforce runtime truth.

## Authority

- The **tracked Pattern file** under this tree is always authoritative.
- Atlas/Notion may hold a discoverability copy after Slice 8 promote; publication does not transfer authority.
- Pattern prose never overrides code or contracts.

## Taxonomy

| Kind | Members |
|------|---------|
| Products | Metra · Yarn · Loom · Atlas |
| Concepts | Evidence · Fabric |
| Cabinets | Guild (`guild/` folder - filing only, not a product) |
| Artifacts | Plans · Patterns · Playbooks · Decisions |

## Load behavior

- Not always-on. Stub indexes triggers only ([AGENTS.md](../../AGENTS.md)).
- Runtime: plan `patterns: [patternId]` cites (Loom request package) and deterministic Yarn match (citations / loadWhen / owner / cabinet). Guild is not special-cased (invariant 15).
- Humans and agents still **Read** Pattern files on trigger the same way as playbooks.

## Directory taxonomy

```text
docs/patterns/
  README.md          # this file
  SCHEMA.md          # front matter and ID rules
  index.yaml         # patternId -> relative path (unique IDs)
  yarn/              # owner: yarn
  loom/              # owner: loom
  guild/             # cabinet: guild (cross-cutting)
  _assets/<patternId>/   # optional Flow companions
```

Do not create `portfolio/` or `governance/` under this tree.

## Pattern lifecycle (summary)

Unwritten behavior -> pattern-gap candidate -> Approved Pattern-authorship plan -> tracked Pattern file -> accepted merge -> eligible for promotion -> Atlas discoverability copy.

## Stub semantics

- `status: stub` and `implemented: false` mean the method is not claimed as shipped behavior.
- Do not invent active Pattern prose for unshipped behavior.

## Validation rules

See [SCHEMA.md](SCHEMA.md). Duplicate `patternId` values are forbidden. Paths must stay under this directory. `cabinet` is organizational only.

## Index

Canonical ID map: [index.yaml](index.yaml). Add an entry when a Pattern file is created (P1+).

## See also

- Decision scar: [Decisions.md](../Decisions.md) (2026-09-02 Patterns taxonomy)
- Authoring: [AGENTS-Authoring.md](../AGENTS-Authoring.md)
- Architecture plan: `metra_patterns_architecture_0354f980.plan.md` (Cursor plans)
