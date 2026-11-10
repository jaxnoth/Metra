---
metraMemory: procedural
defaultContext: false
loadWhen:
  - claude memory
  - CLAUDE.md
  - bite 4
  - portfolio cleanup
ceiling:
  - Operator-assisted only; do not invent Claude memory writes
---

# Claude Code memory refile (Bite 4)

Metra routes via `AGENTS.md` + the project registry. Claude Code may still keep project
memories (`project-*` entries). After Bite 4, keep those memories aligned with the desk
split below.

## Desk split

| File | Role |
|------|------|
| `AGENTS.md` | Metra routing / start-here / ceilings |
| `CLAUDE.md` | Claude Code working notes only (deferred - not a second AGENTS) |
| Registry (`projects.json`, `projects.local.json`, root `projects.personal.json`) | Which folder Metra opens |

## Operator checklist (paste into Claude Code when refiling)

1. Prefer durable facts in repo files (`AGENTS.md`, `PLAN.md`, `README.md`), not only chat memory.
2. If a memory says "not part of Metra" / "no metra.ps1" for a registered project, update or drop it - CarHunt, Travel, Gmail, BrowseKit, RecipeSage, Finance, Forge, PaperTrade are Metra-routable.
3. Keep secrets and dollar amounts out of shared memories; personal local configs stay gitignored.
4. One project memory id per checkout name; do not invent a parallel Metra-vs-Claude project pair.
5. After refile, a Metra `.\metra.ps1 routing -Query '<trigger>'` should still land on the same folder Claude is editing.

## Personal registry note

`projects.personal.json` beside the iCloud personal root is **kept** (not retired). Live
checkouts for several personal tools live under `C:\Projects` (work root wins on disk);
iCloud copies may appear as shadowed. Do not delete shadowed folders without an explicit
operator decision.
