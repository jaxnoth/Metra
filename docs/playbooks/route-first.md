---
metraMemory: procedural
defaultContext: false
loadWhen:
  - routing
  - which project
  - route first
  - sticky primary
  - ticket handoff
ceiling:
  - TicketTracker first for tickets; one technical project for investigate
  - Root isolation; cross-root only when operator opts in
---

> Moved from `AGENTS.md` during A2 desk split. Preserve A1 done-when / On hard stop content unless intentionally revised.

# Route first

Authoritative routing policy also lives in `.cursor/rules/project-routing.mdc` (always-on) and [docs/Context-Routing.md](../Context-Routing.md). This playbook is the expanded operator/agent checklist.

1. Match trigger terms via `.\metra.ps1 routing` / `.\metra.ps1 ctx` / the merged registry.
2. Once this chat has a primary stop, keep it for later turns unless the operator names another project, asks for a deep dive, or the ask clearly requires a different stop.
3. Precedence for new stops: TicketTracker thread > ticket id > ticket/helpdesk vocab > solutions-index keywords > technical score > Metra home. Do not grow TicketTracker registry triggers with product names.
4. For tickets / helpdesk: start in **TicketTracker**. **Ticket-ops** (status, drafts, `post`/`recommend`/`resolve`) stay there. **Technical investigate** opens one technical project only when needed, then return outcomes to TicketTracker. Do not route ticket updates to warehouse/Datamart write stops.
5. Load that project's `AGENTS.md` (or README if none). Do not scan other repos yet.
6. Stay in that project's root. Cross-root only when the user names the other project.
7. Broaden to same-root `related` only when evidence requires it. Ctx / routing **Related** and project story are topology only - not permission to multi-repo search.
