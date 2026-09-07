---
name: coworker-desk
description: >-
  Coworker onboarding for Metra portfolio desk: clean-machine install checks,
  metra.ps1 routing, Overview/selfdoc, missing companion honesty, and
  ticket-ops vs one investigate hop. Use when a coworker starts Metra or when
  companions may be missing. Default Off; no iSupport writes; does not replace
  metra.ps1 routing.
disable-model-invocation: true
---

# Coworker desk

Thin onboarding skill. **Skill is not Metra.** Routing, registry, persona, and
inspect stay in the Metra checkout (`.\metra.ps1`).

## Authority

| Owns | Does not own |
|------|--------------|
| Pointing at Metra CLI and Overview | Registry / persona / inspect policy |
| Missing-companion honesty | Live Orion / Colleague / KB / SQL claims without the companion |
| Reminding ticket-ops vs hop | TicketTracker write commands |

## First commands (with Metra checkout)

```powershell
cd <Metra checkout>
.\metra.ps1 routing
.\metra.ps1 routing -MissingOnly
.\metra.ps1 selfdoc
```

Open Overview prose twin: `docs\Overview.md`. Prefer self-doc canvas when available.

## Ticket-shaped asks

1. Route first - expect **TicketTracker** for ticket ids / helpdesk vocabulary.
2. In TicketTracker: `brief` then `assess` then `assess ... -Recommend -Preview`
   (use the **tickets** plugin/skill; zero durable writes on Preview).
3. Durable `post` / `recommend` / `resolve` only when the operator explicitly asks.

## Portfolio companions

Correct analysis often needs **one** investigate hop (Codex, Solarwinds,
Colleague, IWUDATA-SQL, …). Ticket-ops stay in TicketTracker; return there for
durable writes.

| Situation | Behavior |
|-----------|----------|
| Companion present | Open that one project; follow its AGENTS.md / CLI |
| Companion missing | `.\metra.ps1 routing -MissingOnly`; follow `whenMissing`; do not invent Live evidence |

Install optional companion plugins (codex, tickets, later m365 / solarwinds / …)
from the team marketplace as needed. Do not treat this desk skill as a
bundle of all companions.

## Hard offs

- Replacing `.\metra.ps1 routing` or acting as product entry (no routing bridge)
- Auto iSupport writes
- Fake Live Orion / KB / SQL / Colleague results when clone or Live is absent
- Merging TicketTracker + M365 + Codex policy into this skill

## Smoke

1. Fresh shell; `cd` Metra checkout; `.\metra.ps1 routing` succeeds.
2. `.\metra.ps1 routing -MissingOnly` lists absent entries with advice (or none).
3. For a ticket id, land on TicketTracker without inventing companion evidence.
