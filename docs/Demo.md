# Metra pitch

Coworker talk notes. Plain language. Sell the middle path - not a feature tour.

**Leave them with:** Metra sits between "let AI change everything" and "just another chatbot," and that is why it fits our many project folders.

---

## Story

AI at work usually lands in one of two bad places:

| Extreme | What it feels like | Why it fails here |
|---------|--------------------|-------------------|
| **Carte blanche** | The assistant rummages every folder, edits freely, and "helps" without asking where it belongs | Mixes projects; brochure-speak in tickets; scary near production |
| **Chatbot only** | A smart conversation that cannot see our folders, habits, or ticket tools | Clever answers with no map - you still do all the wayfinding by hand |

**Metra is the middle path.** It does not replace judgment, Cursor, iSupport, or Orion. It **steers** AI help toward one project, keeps chat useful for you, and keeps durable writing (tickets, commits, emails to others) ordinary and professional.

One sentence:

> Metra is guardrails and a front desk for AI over many project folders - not a free-for-all agent, and not a toy chatbot.

```text
  Carte blanche AI                    Chatbot only
         |                                  |
         +-------- Metra (steer) -----------+
                      |
              one project + clear next step
              chat can help you
              tickets stay normal prose
```

---

## Pitch

Say this slowly. No quiz.

**Hook**

> We have a lot of project folders - tickets, Orion, warehouse jobs, Fun Committee printables. When someone asks for help, the first job is always the same: open the **right** folder and follow **that** project's habits.
>
> People are bringing AI into that work. Left alone, it usually goes one of two ways: give it the keys, or treat it like a web chatbot with no map. Metra is built for the middle.

**Steer, do not surrender**

> Metra does not hand AI carte blanche over the portfolio. It steers. Your ask is matched to **one** project - TicketTracker for helpdesk, Solarwinds for Orion, Trivia for Fun Committee - then that project's rules apply. The assistant is pointed at the right desk, with habits we already trust.

**More than a chatbot**

> It is also not just chat. The core of Metra is a **PowerShell CLI** - `.\metra.ps1` - that routes, audits, and builds context with no AI required. Metra Ops is a home screen on top of that same map. Ask is optional sugar. If the engine is off, the command line still works.

**You stay in charge**

> Day to day, Metra answers and guides. Durable changes - regenerating a printable, posting work history to iSupport - happen when **you** ask, not because the tool decided to. Chat with you can sound like a calm coworker. What lands in a ticket stays ordinary professional writing.

Dispatcher line if faces look blank:

> Like a dispatcher: the radio voice can be friendly, but the work order still goes to the right truck - and nobody rolls a truck until you say so.

**Close**

1. Middle path - neither carte blanche AI nor empty chatbot.
2. One project - Metra steers the ask to a home and that project's habits.
3. You decide durable writes - chat can help; tickets stay professional and on request.

---

## How it works (thin by design)

Use this when someone asks "what's under the hood?" or doubts the boundaries are real. Keep it short - Metra stays small on purpose.

**Route first, then answer**

> Every ask hits a map of everyday phrases to **one** project. The assistant starts in that folder's habits (`AGENTS.md`), not by scanning the whole drive. Wrong home is a routing miss - not "the model decided to explore."

**CLI first - Metra without AI**

> Metra is a PowerShell product. The same map and portfolio tools run from the terminal with no desk and no model:

```powershell
.\metra.ps1 routing -Query "ticket disk"
.\metra.ps1 ctx -Query "ticket disk"
.\metra.ps1 audit -Name TicketTracker,Solarwinds,Trivia
.\metra.ps1 list
```

> That is not a fallback for demos - it is the thin core. Ops and Ask sit on top. Coworkers who never open an AI chat can still route work and keep the registry honest.

**Answer on the desk; build in the editor**

> Metra Ops Ask is **answer-only**: read, explain, point at the next command. It does not edit your portfolio from the browser. When you need files changed, you open Cursor (or your editor) on that project and ask to build. That split is the boundary against carte blanche.

**Thin stack, clear owners**

```text
metra.ps1 (CLI core)
     |
Tray host  ->  Ops desk  ->  Ask engine   (all optional)
(keeps desk alive)  (home screen)  (optional AI brain)
```

> The CLI works alone. The tray only supervises the desk. The desk alone owns the AI engine. Cursor is one swappable engine behind a small loopback contract - not the product. If Ask is down, `routing` / `ctx` / classify still work.

**Two channels, two voices**

> Chat with you can sound like a calm coworker. Tickets, commits, and mail to others go through a **professional sink** - ordinary work prose, no Metra branding, and usually only when you ask to post. Personality never picks the project; routing always wins.

**Map stays data, not a second brain**

> Shared stubs (TicketTracker, Solarwinds, Trivia, ...) live in a small registry the team can ship. Your private folders stay local. Missing optional projects get honest advice instead of fake folders. Metra does not become a new ticket system, Orion, or warehouse - it points at the ones you already have.

**What Metra deliberately does not do**

- Own production systems of record
- Auto-post tickets or auto-edit the portfolio from Ops
- Index every sibling repo on every ask
- Turn into a Teams bot, mascot, or always-on agent with the keys

> Thin means: steer, answer, hand off. Depth lives in each project's own tools and rules.

---

## Q&A

**Do I have to use AI / Cursor?**  
No. `.\metra.ps1 routing`, `ctx`, `audit`, and `list` work with no AI and no Ops desk. Ask is optional. Adoption of an editor is optional.

**Is this going to change my tickets by itself?**  
No. In practice I ask it to update the ticket after we finish. It writes professional work history through TicketTracker when asked.

**Will it edit all my projects?**  
Not as the default story. Metra steers to one project and prefers answer-first help. File changes happen in the editor when you ask - review before you run.

**Is my data being trained on / sent somewhere?**  
Stay accurate to org policy. Cloud AI tools send prompts and often file context to a vendor unless you use an approved local setup. Do not paste passwords, PHI, or secrets. Point people at IT/security guidance.

**Will it replace my job / TicketTracker / Orion?**  
No. Guide and draft carefully. Tickets stay in iSupport; monitoring stays Solarwinds.

**How is this different from ChatGPT in a browser?**  
Browser chat usually cannot see our folders, our routing map, or our ticket habits. Metra is built for this multi-folder layout - and it refuses the "edit everything" extreme.

**Is Metra a bot in Teams?**  
No. Text helper and desk only - no avatar, no forced jokes. Incidents stay flat and useful.

**What if I do not have TicketTracker on my PC?**  
Fine. Optional stubs give advice when a folder is missing instead of pretending it exists.
