# Metra agent guide

Orchestration repo (**Metra** product; recommended checkout folder `_metra`) for sibling folders under configured roots. Prefer routing over broad multi-repo search. CLI: `.\metra.ps1`.

Authoring: [docs/AGENTS-Authoring.md](docs/AGENTS-Authoring.md) (Metra). A2 desk split (2026-08-14).

## Constitution (always-on elsewhere)

Do not duplicate these in playbooks or durable writes - link and obey:

| Source | Role |
| --- | --- |
| [`.cursor/rules/metra-persona.mdc`](.cursor/rules/metra-persona.mdc) | Persona, Teaching Mode, Humor Policy, OCC promote rules |
| [`.cursor/rules/project-routing.mdc`](.cursor/rules/project-routing.mdc) | Route-first, root isolation, TicketTracker precedence |
| [docs/Context-Routing.md](docs/Context-Routing.md) | Desk model, registry, ctx |
| [docs/Decisions.md](docs/Decisions.md) | Portfolio Operations Principles, durable scar home |
| [`.cursor/rules/metra-inspect-loop.mdc`](.cursor/rules/metra-inspect-loop.mdc) | Inspect coding loop gate |

Optional overlays: `metra-persona.local.mdc`, `metra-learned.local.mdc`, `metra-humor.local.mdc`. See [docs/Customizing-Metra.md](docs/Customizing-Metra.md).

## Route here when

Triggers: Metra home, routing, ctx, registry, inspect, profile, decisions, workspace setup, portfolio orchestration, multi-root workspace ops. Also: atlas / portfolio memory / expanded memory / plan archive -> sibling Atlas (see portfolio-memory-governance).

## Start here

1. Read this stub. Persona/voice lives in always-on `metra-persona.mdc` (examples on trigger: [docs/playbooks/persona-voice-examples.md](docs/playbooks/persona-voice-examples.md)).
2. Route with `.\metra.ps1 routing` / `.\metra.ps1 ctx` before broad search. Expanded checklist: [docs/playbooks/route-first.md](docs/playbooks/route-first.md).
3. Match a playbook trigger below and **Read** that file before deep work.
4. Non-Cursor agents: this stub + target project `AGENTS.md` + `.\metra.ps1 ctx`. See [docs/Integrations.md](docs/Integrations.md).

## Ceilings

- Keep established primary stop unless the operator names another project or the ask clearly requires a different stop.
- Ticket/helpdesk: TicketTracker first; ticket-ops stay there; one technical project for investigate only.
- Stay in the routed project root; cross-root only when the operator opts in.
- Portfolio facts need a declared home ([docs/Decisions.md](docs/Decisions.md)) - no parallel homes; no OCC for product policy.
- Idea/brainstorm: conversational until the operator asks to implement (no edit, commit, or PR).
- Meaningful code changes: inspect loop ([docs/playbooks/inspect-loop.md](docs/playbooks/inspect-loop.md)).
- Durable artifacts: professional prose only; chat may use Metra voice.

## On-demand playbooks

| Trigger | Read |
| --- | --- |
| route precedence, sticky primary, ticket handoff | [docs/playbooks/route-first.md](docs/playbooks/route-first.md) |
| persona chat examples, maintainer notes | [docs/playbooks/persona-voice-examples.md](docs/playbooks/persona-voice-examples.md) |
| OCC, decisions, ask/capture, memory homes | [docs/playbooks/portfolio-memory-governance.md](docs/playbooks/portfolio-memory-governance.md) |
| projects.json, profiles, import-profile | [docs/playbooks/registry-profiles.md](docs/playbooks/registry-profiles.md) |
| metra.ps1 commands | [docs/playbooks/cli-reference.md](docs/playbooks/cli-reference.md) |
| inspect loop, pack, Bing lane, A2 pack | [docs/playbooks/inspect-loop.md](docs/playbooks/inspect-loop.md) |
| grep scope, cloud chats, token discipline | [docs/playbooks/token-rules.md](docs/playbooks/token-rules.md) |
| audit, selfdoc, verify, registry maintenance | [docs/playbooks/maintenance-audit.md](docs/playbooks/maintenance-audit.md) |
| Tailscale, DNSFilter, campus hosts, Serve enable | [docs/playbooks/tailscale-campus.md](docs/playbooks/tailscale-campus.md) |
| satellite connect, Mac onboarding, profile sync merge | [docs/playbooks/satellite-remote-install.md](docs/playbooks/satellite-remote-install.md) |
| yarn intake, backlog, synthesize, pack freshness | [docs/playbooks/yarn.md](docs/playbooks/yarn.md) |
| loom queue, triage, run, review, daily, loop | [docs/playbooks/loom.md](docs/playbooks/loom.md) |

## On-demand patterns

Architectural methods (how Metra / Yarn / Loom / Atlas are designed). Bodies under [docs/patterns/](docs/patterns/README.md). Not always-on. Loom attaches cited Patterns to the implementer package; Yarn emits `patterns:` + gap checklist on synthesize. Loom owns accept-gated `pattern score|promote` (Atlas put).

| Trigger | Read |
| --- | --- |
| Pattern taxonomy, cabinet, schema, patternId | [docs/patterns/README.md](docs/patterns/README.md), [docs/patterns/SCHEMA.md](docs/patterns/SCHEMA.md) |
| loom queue ingest, Approved plan enqueue | [docs/patterns/loom/queue-ingestion.md](docs/patterns/loom/queue-ingestion.md) |
| loom project lane, loop concurrency | [docs/patterns/loom/project-lane.md](docs/patterns/loom/project-lane.md) |
| loom review, completed vs inspect/verify | [docs/patterns/loom/review.md](docs/patterns/loom/review.md) |
| completed vs accepted, daily approve | [docs/patterns/guild/completed-vs-accepted.md](docs/patterns/guild/completed-vs-accepted.md) |
| agent/inspect engines, adapters, pause | [docs/patterns/guild/agent-interaction.md](docs/patterns/guild/agent-interaction.md) |
| pattern score/promote, Atlas put, Slice 8 | [docs/patterns/guild/knowledge-promotion.md](docs/patterns/guild/knowledge-promotion.md) |

## Token rules

- Scoped Grep/Glob under the routed project absolute path - not whole multi-root workspace first.
- Prefer CLI filters over large JSON or full agent transcript dumps.
- Full list: [docs/playbooks/token-rules.md](docs/playbooks/token-rules.md).
- Example overlay rules under `.cursor/rules/*.example.mdc` are optional imports - not linked here.

## Related

Topology only: sibling projects via registry `related`. Open only when evidence requires it.
