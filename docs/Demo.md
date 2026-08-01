# Metra demo (face-first)

Speaker notes for a coworker walkthrough. Most of the room has **little or no AI experience**, so keep jargon light - but lead with **what Metra looks like at the desk**, not with a long AI primer.

**Goal:** They leave knowing (1) Metra is a wayfinding layer for many project folders, (2) the Ops board answers "what's next" and "where do I resolve this," (3) chat tone and ticket text are different, (4) they do not need to become an AI expert to benefit later.

**Recommended length:** about **8 minutes** talk, then questions. A strict **5-minute cut** is in the timing section.

**Do not demo:** personal / iCloud roots, private local registry details, live production ticket posts, secrets, Canva/MCP, Decision Registry, or OCC deep dives. In day-to-day use you usually ask the assistant to update iSupport; for this talk, show a **draft** only and narrate the real post step.

---

## What you are teaching (keep this in your head)

| Idea | Plain English |
|------|----------------|
| Metra Ops board | The desk faceplate: what needs attention, and how to resolve the current ask |
| Routing | A map of everyday phrases -> **one** project, then follow that project's rules |
| AI assistant in the editor | A chat that can read project files and suggest (or make) changes when you ask in normal language |
| Prompt | The sentence you type into that chat |
| Workspace / folders | Our many sibling project folders (Solarwinds, TicketTracker, Trivia, ...) |
| Without Metra | The assistant often searches everywhere, mixes projects, or writes fluffy ticket notes |
| Metra (persona) | The chat "coworker" voice: clear, calm, slightly dry; not a cartoon character |
| Professional sink | Tickets, commits, and email to others stay normal work prose - no Metra branding |
| Ticket updates | On request, the assistant posts work history / recommendations into iSupport via TicketTracker - it does not update tickets unsolicited |

One sentence for the room:

> Metra is a thin guide for our many project folders. The Ops board is the desk - next work and a home for the ask - and chat stays helpful without turning iSupport into marketing copy.

---

## Prep (10 minutes before)

1. Open `Metra.code-workspace` (or your workspace that includes the Metra checkout).
2. For the Ops board faceplate: prefer **Cursor Light** for the demo shot (daily work can stay **Cursor Dark**). See [Brand.md](Brand.md) dual-mode checklist.
3. Terminal cwd: `C:\Projects\_metra` (or `_meta` / your Metra checkout).
4. Refresh the board so it is not stale:

```powershell
.\metra.ps1 snapshot
```

5. Open the Cursor Canvas **Metra Ops** (`metra-ops-board`) beside chat. Leave it on the **Route** tab.
6. Confirm shared stubs resolve:

```powershell
.\metra.ps1 routing -Name TicketTracker,Solarwinds,Trivia
```

7. Optional: pre-generate a context pack (skip in the strict cut):

```powershell
.\metra.ps1 ctx -Query "ticket disk"
```

8. Open a **new** Cursor chat with the Metra checkout in scope. Prefer **Ask** mode (read-only) so nothing changes by accident.
9. Have Prompts A and B on a second monitor or printed card.
10. Optional: one whiteboard or slide with the flow line below.

If Needs attention is empty, that is fine - use **Standing routes** (TicketTracker + pinned hubs) and say the queue is healthy right now.

---

## Timing

### Recommended (~8:00) then Q&A

| Clock | Segment | What the room learns |
|-------|---------|----------------------|
| 0:00-0:45 | Hook | Familiar pain without AI jargon |
| 0:45-2:15 | Face (Ops board) | Metra at the desk: next work + resolve this |
| 2:15-3:30 | Concepts | Routing map + chat vs ticket voice (short) |
| 3:30-6:30 | Live proof | CLI map + chat ask + ticket draft contrast |
| 6:30-8:00 | Close | Three takeaways; how to try later; invite questions |

### Strict 5-minute cut

| Clock | Segment |
|-------|---------|
| 0:00-0:30 | Hook (one sentence on many folders) |
| 0:30-1:45 | Ops board Route tab only |
| 1:45-2:30 | `routing` Triggers for three projects |
| 2:30-4:20 | Prompt A + Prompt B |
| 4:20-5:00 | Three takeaways |

Skip `ctx`, Teaching Mode, and the longer AI primer in the strict cut unless someone asks in Q&A.

---

### 0:00 - Hook (~45s)

Start from work they already know - not from "AI agents."

> We have a lot of project folders. When someone asks for help on a ticket, an Orion alert, or a Fun Committee printable, the first job is always the same: open the **right** folder and follow **that** project's habits.
>
> People are starting to use AI chat inside the editor for that. Left alone, it often digs through every folder at once, or drafts ticket notes that sound like a brochure. Metra is our small layer on top. Today you will see the desk first - then the map behind it - then how chat and tickets stay different.

Whiteboard / slide (optional):

```text
Your ask  -->  Metra picks ONE project  -->  That project's rules  -->  Answer or draft
```

---

### 0:45 - Face: Metra Ops (~90s)

Narrate while pointing at the canvas. Assume they have never seen this panel.

> This is **Metra Ops** - the face of the product in Cursor. Route is the home tab. Two questions drive it.

**Needs attention** (left):

> What is waiting on the portfolio - drift, hygiene, stewardship candidates when the snapshot includes them. Each row is one Resolve. We do not paste commands from this list into a terminal by habit - Resolve opens a briefing, then we prefer **Ask Metra** so chat continues the work.

**Resolve this** (right):

> Type a new symptom, or pick Resolve on a waiting item. You get issue-specific guidance - summary, detail, done-when - then **Ask Metra** (preferred) or **Copy for terminal** (self-serve).

If the queue is empty:

> Empty is a good day. **Standing routes** still let you jump into TicketTracker or a pinned hub without inventing work.

Point at the sticky tab bar briefly:

> Route / Portfolio / Stewardship stay reachable while you scroll. Portfolio is health detail; Stewardship is knowledge tending. We stay on Route for this talk.

One sentence:

> The board retrieves from homes we already have - routing, audit, ledgers. It is not a second place to store tickets or secrets.

---

### 2:15 - Concepts (~75s)

Speak slowly. Define terms once. Do not quiz the room.

**1. What is Metra? (~40s)**

> Metra is **not** a new ticket system and **not** a replacement for Solarwinds or iSupport. It is a portfolio helper beside our folders. Two parts matter today:
>
> - **Ops board + routing** - wayfinding: one project, clear next step
> - **Personality** - how the chat talks to **you** while you work
>
> The checkout folder is often named `_metra` (older clones may still use `_meta`). The product name is Metra. The command line tool is `metra.ps1`.

**2. Routing vs personality (~35s)**

> Routing decides **where** work happens. Personality decides **how** the chat sounds. Routing always wins.
>
> When we write something durable - an iSupport work-history line, a commit message, a Slack note for the team - Metra steps out of character. That is the professional sink.
>
> Day to day I usually ask it to **post that into the ticket** through TicketTracker. It does not update iSupport on its own.

If someone looks lost, one analogy:

> Like a dispatcher: the radio voice can be friendly, but the ticket still goes to the right truck.

Skip Teaching Mode, overlays, personal roots, and Decision Registry unless asked later.

---

### 3:30 - Live proof (~3 min)

**Part 1 - The map (CLI) (~60s)**

> The board is powered by the same map we maintain as a table. Watch the Triggers column - everyday phrases mapped to a project.

```powershell
.\metra.ps1 routing -Name TicketTracker,Solarwinds,Trivia
```

Point at:

- **TicketTracker** - ticket / iSupport / helpdesk
- **Solarwinds** - Orion / alert / monitor
- **Trivia** - Fun Committee / word search / printable

Say:

> TicketTracker and Solarwinds can be optional stubs. If that folder is not on your machine, Metra gives advice instead of failing mysteriously. Your private project list stays on your machine; the shared stub list stays small for the team.

If time allows (~15s), gesture at pre-built `docs/context-pack.md`:

> `ctx` builds a short handout so the AI does not need to scan the whole drive. Useful even outside Cursor.

**Part 2 - Chat with Metra (~2 min)**

> New chat. Normal Fun Committee question. Watch for two things: it should pick **Trivia**, and the reply should start with Metra naming itself.

Paste **Prompt A**:

```text
Fun Committee needs a tech-on-screen word search regenerated. Where do I start, and what command do I run?
```

Call out live:

- Banner line (`**Metra** · Model: ...`)
- Correct project (Trivia)
- One clear next step (command), not a 20-step lecture

Then **Prompt B**:

```text
Draft the iSupport work-history text I would post for regenerating that word search. Plain text only, headings and bullets.
```

Call out:

> Same chat, different job. This draft should sound like ticket notes - headings and bullets - not like a branded assistant. That is the professional sink.
>
> Day to day I usually say "post this to ticket N" and it writes the work history into iSupport for me. We are not posting live in this demo.

Optional bridge back to the board (~20s):

> On the Ops board, **Ask Metra** is the same idea - hand the briefing to chat instead of copy-pasting into a terminal.

If the room needs a third beat and you have 30s: backup Orion prompt (see card below). Otherwise stop.

---

### 6:30 - Close (~1.5 min)

Three takeaways (say them as bullets on a slide if you have one):

1. **Metra Ops is the desk** - what's next, then a home for the ask.
2. **Metra steers work to one project** so the AI does not rummage through everything.
3. **Chat can be a helpful coworker voice**; when a ticket is updated (usually on request), the text stays ordinary professional writing.

How to try later (do not live-clone unless asked):

```powershell
cd C:\Projects
git clone <Metra-repo-url> _metra
cd _metra
.\metra.ps1 import-profile -Path .\profiles\sample -Preview
```

> Preview first. No pressure to adopt Cursor this week. Questions are open.

Docs for people who want to read later:

- [Context-Routing.md](Context-Routing.md) - how routing and the Ops board refresh work
- [Brand.md](Brand.md) - Ops board look and professional sink
- [Customizing-Metra.md](Customizing-Metra.md) - persona and Origin (optional depth)
- [Integrations.md](Integrations.md) - what works without Cursor; optional MCP bindings
- [Decisions.md](Decisions.md) - short record of portfolio-wide Metra choices

---

## Live prompt card

| # | Paste this | Say while it runs |
|---|------------|-------------------|
| A | Fun Committee needs a tech-on-screen word search regenerated. Where do I start, and what command do I run? | "Watch: Trivia, not every folder. Metra banner. One next command." |
| B | Draft the iSupport work-history text I would post for regenerating that word search. Plain text only, headings and bullets. | "Normal ticket notes - no Metra voice. Live, I would usually ask it to post this." |
| Backup | We have an Orion disk alert. Which project should we open first, and what is a safe first command? | "Solarwinds. Filtered catalog / active alerts - not dumping the whole index." |

---

## Backup if something fails

| Problem | What to do |
|---------|------------|
| Ops board missing or stale | Run `.\metra.ps1 snapshot`; reopen the canvas panel; narrate from this doc if needed |
| Needs attention empty | Use Standing routes; say "healthy snapshot - the desk still has jump-ins" |
| Chat picks wrong project | Show `routing` Triggers row; restate "one project"; new chat + Prompt A |
| No Metra banner | Say "the rule requires it; value is still the route"; continue with Prompt B |
| Chat is slow or blank | Stay on Ops board + CLI `routing`; narrate Prompt A/B expected results from this doc |
| Someone asks to "make it change files" | Decline for this demo; Ask mode is intentional |

Do not open personal projects for this audience.

---

## Anticipated Q&A (beginner-friendly)

**Do I have to use AI / Cursor?**  
No. Metra's command-line map and docs are useful on their own. Cursor is the nicest place to see the Ops board and personality. Adoption is optional.

**Is this going to change my tickets by itself?**  
No - not unsolicited. In practice I usually ask it to update the ticket after we finish work. It uses TicketTracker (`post` / `recommend`) to write professional work history into iSupport. Today's demo only shows a draft so we do not touch a live ticket in the room.

**Is my data being trained on / sent somewhere?**  
Stay accurate to your org policy. In plain terms: cloud AI tools send prompts and often file context to a vendor unless you use an approved local/offline setup. Do not paste passwords, PHI, or secrets into chat. Point people at IT/security guidance rather than inventing a policy.

**Will it replace my job / TicketTracker / Orion?**  
No. It is a guide for finding the right project and drafting carefully. Source of truth for tickets stays iSupport; monitoring stays Solarwinds.

**What is a "prompt"?**  
Just the question you type. Everyday English is fine. Naming the project or the symptom helps (ticket, Orion alert, Fun Committee).

**What gets shared with the team vs private?**  
A small shared list (for example TicketTracker and Solarwinds stubs) can live in the repo. Your full private project map stays local and is not meant for coworker clones.

**What if I do not have TicketTracker on my PC?**  
That is fine. Optional stubs give advice when the folder is missing instead of pretending it exists.

**Is Metra a mascot or a bot in Teams?**  
Neither. Text in the editor chat only - no avatar, no voice, no forced jokes. During real incidents the tone stays flat and useful.

**Can it break production?**  
Only if someone allows file changes and runs unsafe commands. This demo uses Ask (read-only). Treat AI suggestions like a junior coworker: review before you run anything. Ticket posts are the same idea - they happen when asked, so you decide when iSupport gets updated.

**How is this different from ChatGPT in a browser?**  
Browser chat usually cannot see our project folders, our routing table, or the Ops board. Metra is built for this multi-folder work layout.

**What are Ask Metra vs Copy for terminal?**  
Ask Metra opens chat with a briefing so the assistant continues the work. Copy is only if you want to run the command yourself. Prefer Ask Metra in normal desk use.

**Does Teaching Mode quiz me?**  
No. When you are exploring, it should answer first, give one next step, and stop. No pop quizzes.

---

## One-line opener / closer

**Open:** Metra is the desk for our many project folders - see what's next, route the ask, keep ticket writing professional.  
**Close:** Remember the three points - Ops board as the desk, one project, chat vs ticket voice - then ask anything.
