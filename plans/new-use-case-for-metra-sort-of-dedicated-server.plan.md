---
name: New use case for Metra. Sort of. Dedicated server that eventually analyzes all i
overview: "CANCELLED / done. Empty Yarn stub (2026-09-04) from Capture 89b2cfec. Concept pursued elsewhere as jumpbox HQ + TicketWatch (mine-first Attention) - not this draft. Do not Bing-finalize this stub."
status: done
bingReviewed: false
captureId: 89b2cfecff644dd9b1c48e34c370de27
synthesizedAt: "2026-09-04T01:42:46.5926811Z"
synthesizerVersion: yarn-template-v1
patterns:
  - guild-agent-interaction
todos:
  - id: draft-1
    content: "Cancelled - stub never refined. Real work lives in TicketWatch mine-first + jumpbox/satellite HQ scars (see body)."
    status: cancelled
isProject: false
---

# Dedicated server / analyze tickets - CANCELLED stub

**Status:** Done / cancelled stub (closed 2026-09-16). Surveyor should not treat this as Pending Bing Review work.

## Verdict

You were right that the **concept** moved on. This file did not: it is another Yarn template with truncated Capture text and no architecture.

Do **not** refine or Bing-finalize this stub. Continue (or park) work in the real homes below.

## Capture intent (as synthesized)

Dedicated always-on Metra host that eventually analyzes incoming iSupport tickets for initial analysis.

## Where that concept actually went

| Thread | Home | Notes |
|--------|------|-------|
| Always-on Metra host | Jumpbox HQ; Tailscale Serve; satellite connect; desk modes | `docs/Cross-Device.local.md`; Decisions (satellite / campus hosts); playbooks `satellite-remote-install`, `tailscale-campus` |
| Ticket initial analysis | **TicketWatch** (F3.x) | Sensor = TicketTracker; Attention = Metra; Authority = operator. Mine-first Attention - **not** silent analyze-all help desk |
| Shipped bites | `docs/Shipped.local.md` TicketWatch mine-first | M1-M3, Affirm A; plans `ticket_watch_mine-first_89e19166`, `ticket_watch_desk_97f6eee6`, … |
| Coworker install of TT/Codex | Stations / Station Updates | Decisions 2026-09-07; `station-updates` playbook |
| Always-on investigate subsystem | Scout | Considered then **superseded / parked** in Decisions - Attention territory |

## Product dial-back (important)

The Capture title said analyze **all** incoming tickets. Shipped TicketWatch is deliberately **mine-first** Attention with operator Affirm - not an automation help desk that writes iSupport on its own. Broaden scope only via explicit TicketWatch follow-ons (M4 Team pack, Host poll, etc. in Future-Dev) - not by resurrecting this stub.

## Explicit non-work

- Filling Architecture / Delivery TBD here
- Treating this plan as the jumpbox or TicketWatch implementation plan
- Auto Live / Affirm B from watch without a separate product decision
