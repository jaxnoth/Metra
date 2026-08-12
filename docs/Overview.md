# Metra

**Visual primary:** open the Metra self-documentation canvas beside chat in Cursor (`metra-self-documentation.canvas.tsx`). This file is the sendable prose twin for email or print.

Land in the right place. Then get to work.

Metra helps AI assistants start in the right project, with the right materials, instead of guessing. Different kinds of work live in different places - Metra remembers which is which, so the assistant starts in the correct one before work begins.

---

## The problem

AI at work usually lands in one of two bad places:

| Extreme | What it feels like | Why it fails here |
|---------|--------------------|-------------------|
| **Carte blanche** | The assistant rummages every folder, edits freely, and "helps" without asking where it belongs | Mixes projects; brochure-speak in tickets; risky near production and systems of record |
| **Chatbot only** | A smart conversation that cannot see our folders, habits, or ticket tools | Clever answers with no map - people still do all the wayfinding by hand |

```text
  Carte blanche AI                    Chatbot only
         |                                  |
         +-------- Metra (steer) -----------+
                      |
              one project + clear next step
              chat can help the operator
              tickets stay normal prose
```

---

## What Metra does

### Standing route examples

<!-- metra-selfdoc-routes-begin -->

| Project | Verified ask | Why | Purpose |
|---------|--------------|-----|---------|
| TicketTracker | ticket | trigger-phrase | Local ticket assistant for iSupport and future helpdesk systems - sync, search, notes, recommendations. |
| Solarwinds | solarwinds | trigger-phrase | Orion platform-as-code - alerts, monitors, templates, dashboards, dependencies. |
| Trivia | trivia | trigger-phrase | Fun Committee / IT get-together printables - trivia drafts, theme sheets, and word-search generators under C:\Projects\Trivia. |
| Colleague | colleague | trigger-phrase | PowerShell module for Ellucian Colleague admin - WAGC, WAFM, PRQM, EDQM, listeners, sessions. |
| IWUDATA-Automation | iwudata automation | trigger-phrase | PowerShell automation that populates IWUDATA warehouse databases. |
| Reporting | reporting | trigger-phrase | Reporting assets, SSRS/related report work, and ops scripts. |
| Jitterbit | jitterbit | trigger-phrase | Harmony Studio exports, private agents, and IWU.Jitterbit operation-log monitoring module. |
| AutoHotkey | autohotkey | trigger-phrase | AutoHotkey scripts and helpers. |

Precedence (live engine): ticket id > helpdesk vocabulary > solutions keywords > registry score; weak signals stay at Metra.
Example: ask `1035666` -> TicketTracker (ticket-id), even when no project name appears in the ask.

Generated 2026-08-12T15:13:42.1062244-04:00 by `.\metra.ps1 selfdoc` from live `Get-MetraRoutingAmbiguity` (present projects only).
<!-- metra-selfdoc-routes-end -->

Metra picks the matching place before work starts. It does not replace judgment, Cursor, iSupport, or Orion. After routing, it keeps help useful for the person doing the work, and keeps durable writing (tickets, commits, emails to others) ordinary and professional.

- **Route first.** An ask is matched to one project home (for example TicketTracker for helpdesk, Solarwinds for Orion, Trivia for Fun Committee). That project's habits apply. Wrong home is a routing miss - not "the model decided to explore."
- **More than chat.** The core is a PowerShell CLI (`.\metra.ps1`) that routes, audits, and builds context with no AI required. Metra Ops is a home screen on the same map. Ask is optional. If the AI engine is off, the command line still works.
- **You stay in charge.** Day to day, Metra answers and guides. Durable changes - regenerating a printable, posting work history to iSupport - happen when the operator asks, not because the tool decided to.
- **Two voices.** Chat with the operator can sound like a calm coworker. What lands in a ticket, commit, or mail to others goes through a professional sink - ordinary work prose, no Metra branding.

Like a dispatcher: the radio voice can be friendly, but the work order still goes to the right truck - and nobody rolls a truck until someone says so.

---

## Vision and institutional fit

Higher ed and IT shops will keep adding AI to day-to-day work. The question is not whether assistants show up - it is whether they land as carte blanche over every folder, or as a chatbot with no institutional map. Metra is a deliberate middle: steer first, keep judgment with the operator, and keep durable writing ordinary and professional.

**Why it matters here**

- Many project folders, many habits - tickets, monitoring, warehouse, printables. The first job is always the same: right desk, right rules.
- Unbounded AI mixes projects and can sound wrong in systems of record. Pure chat without wayfinding still leaves people routing by hand.
- Metra treats routing and boundaries as product, not afterthought. Personality never picks the project; the map does.

**Campus postures (pattern, not an audit)**

AI already lands in different postures on campus. In some areas, teams connect general-purpose assistants to rich systems of record (CRM / Salesforce-shaped work is one example people discuss; specifics vary and are not fully mapped here). That pattern tends toward a broad lane - ask anything, and sometimes act - unless someone deliberately builds safeguards. Metra is built for the opposite posture: route to one home, answer with habits we trust, durable writes only when a person asks. The useful comparison is the **pattern** of governance, not any one team.

**Governance without theater**

Ops Ask is answer-only: read, explain, point at the next step. It does not edit the portfolio from the browser. File changes happen in the editor when someone asks. Ticket posts go through existing tools on request - no auto-post, no Metra branding in iSupport. The CLI works with no AI at all. Thin on purpose: Metra does not replace TicketTracker, Orion, or warehouse systems - it points at them.

**Where this could grow - and where it should not**

| Path | Fit |
|------|-----|
| Broader UIT / DataOps operator desk | Natural - more project homes, stubs, companions; still point at systems, do not own them |
| AI adoption "pane" (steer + guardrails) | Strong institutional story - one place to ask, routing + professional sink, no carte blanche |
| True university SPOG (everyone, every system) | Wrong home for Metra - campus glass is a different product job (vendors / Ellucian-shaped shells are likelier owners) |

"Single pane of glass" is a useful bridge phrase ("single place to find the right desk"), not a promise that Metra becomes the campus glass. Metra may feed a future institutional shell or stay a separate operator desk. Connecting any system of record (including Salesforce) only works if someone owns a project home, registry triggers, and write boundaries - otherwise it is carte blanche with a nicer logo.

**Summary**

1. Middle path - adopt AI without keys-to-the-kingdom or empty chatbot spend.
2. Institutional fit - one project home, habits we already trust, professional sink for anything coworkers see.
3. Operator stays in charge - steer and guide by default; durable writes only when asked.
4. Grow the governed desk - not an unbounded campus SPOG under the Metra name.

---

## How it works (thin by design)

Metra stays small on purpose. Depth lives in each project's own tools and rules.

**Route first, then answer.** Every ask hits a map of everyday phrases to one project. The assistant starts in that folder's habits (`AGENTS.md`), not by scanning the whole drive.

**CLI first - Metra without AI.** The same map and portfolio tools run from the terminal with no desk and no model:

```powershell
.\metra.ps1 routing -Query "ticket disk"
.\metra.ps1 ctx -Query "ticket disk"
.\metra.ps1 audit -Name TicketTracker,Solarwinds,Trivia
.\metra.ps1 list
```

That is the thin core, not a demo fallback. Ops and Ask sit on top. People who never open an AI chat can still route work and keep the registry honest.

**Answer on the desk; build in the editor.** Metra Ops Ask does not edit the portfolio from the browser. When files need to change, open Cursor (or another editor) on that project and ask to build. That split is the boundary against carte blanche.

**Thin stack, clear owners**

```text
metra.ps1 (CLI core)
     |
Tray host  ->  Ops desk  ->  Ask engine   (all optional)
(keeps desk alive)  (home screen)  (optional AI brain)
```

The CLI works alone. The tray supervises the desk. The desk owns the AI engine. Cursor is one swappable engine behind a small loopback contract - not the product. If Ask is down, routing, context, and classify still work.

**Map stays data, not a second brain.** Shared stubs (TicketTracker, Solarwinds, Trivia, and others) live in a small registry the team can ship. Private folders stay local. Missing optional projects get honest advice instead of fake folders.

**What Metra deliberately does not do**

- Own production systems of record
- Auto-post tickets or auto-edit the portfolio from Ops
- Index every sibling repo on every ask
- Turn into a Teams bot, mascot, or always-on agent with the keys

Thin means: steer, answer, hand off.

---

## Common questions

**Do I have to use AI or Cursor?**  
No. `.\metra.ps1 routing`, `ctx`, `audit`, and `list` work with no AI and no Ops desk. Ask is optional. Using an editor is optional.

**Will this change my tickets by itself?**  
No. Ticket updates go through TicketTracker when the operator asks. Work history stays ordinary professional prose.

**Will it edit all my projects?**  
Not by default. Metra steers to one project and prefers answer-first help. File changes happen in the editor when you ask - review before you run.

**Is my data being trained on or sent somewhere?**  
Follow org policy. Cloud AI tools send prompts and often file context to a vendor unless you use an approved local setup. Do not paste passwords, PHI, or secrets. Ask IT/security for current guidance.

**Will it replace my job, TicketTracker, or Orion?**  
No. Metra guides and drafts carefully. Tickets stay in iSupport; monitoring stays Solarwinds.

**How is this different from ChatGPT in a browser?**  
Browser chat usually cannot see our folders, our routing map, or our ticket habits. Metra is built for this multi-folder layout - and it refuses the "edit everything" extreme.

**Is Metra a bot in Teams?**  
No. Text helper and desk only - no avatar, no forced jokes. Incidents stay flat and useful.

**What if I do not have TicketTracker on my PC?**  
Fine. Optional stubs give advice when a folder is missing instead of pretending it exists.

---

## Learn more

- Visual primary (in Cursor): open the **Metra self-documentation** canvas beside chat
- Public overview: [https://jaxnoth.github.io/Metra/](https://jaxnoth.github.io/Metra/)
- Product repo and operator docs: ask the Metra steward for the current clone or installer path
