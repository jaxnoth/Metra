# Metra demo (concepts + live)

Speaker notes for a coworker walkthrough. Most of the room has **little or no AI experience**, so teach a few plain ideas first, then show a short live proof.

**Goal:** They leave knowing (1) what Metra is, (2) why routing matters, (3) that chat tone and ticket text are different, (4) they do not need to become an AI expert to benefit later.

**Recommended length:** about **8 minutes** talk, then questions. A strict **5-minute cut** is at the end of the timing section.

**Do not demo:** personal / iCloud roots, private local registry details, live production ticket posts, or secrets. In day-to-day use you usually ask the assistant to update iSupport; for this talk, show a **draft** only and narrate the real post step.

---

## What you are teaching (keep this in your head)

| Idea | Plain English |
|------|----------------|
| AI assistant in the editor | A chat that can read project files and suggest (or make) changes when you ask in normal language |
| Prompt | The sentence you type into that chat |
| Workspace / folders | Our many sibling project folders (Solarwinds, TicketTracker, Trivia, ...) |
| Without Metra | The assistant often searches everywhere, mixes projects, or writes fluffy ticket notes |
| Routing | A map of everyday phrases -> **one** project, then follow that project's rules |
| Metra (persona) | The chat "coworker" voice: clear, calm, slightly dry; not a cartoon character |
| Professional sink | Tickets, commits, and email to others stay normal work prose - no Metra branding |
| Ticket updates | On request, the assistant posts work history / recommendations into iSupport via TicketTracker - it does not update tickets unsolicited |

One sentence for the room:

> Metra is a thin guide for our many project folders. It steers the AI to the right place and keeps chat helpful without turning iSupport into marketing copy.

---

## Prep (10 minutes before)

1. Open `Metra.code-workspace` (or your workspace that includes `_meta`).
2. Optional for the Ops board faceplate shot: **Cursor Light** (daily work can stay **Cursor Dark**). See [Brand.md](Brand.md) dual-mode checklist.
3. Terminal cwd: `C:\Projects\_meta` (or your Metra checkout).
4. Confirm shared stubs resolve:

```powershell
.\meta.ps1 routing -Name TicketTracker,Solarwinds,Trivia
```

5. Pre-generate a context pack (so you do not wait live):

```powershell
.\meta.ps1 ctx -Query "ticket disk"
```

6. Open a **new** Cursor chat with `_meta` in scope. Prefer **Ask** mode (read-only) so nothing changes by accident.
7. Have Prompts A and B on a second monitor or printed card.
8. Optional: one whiteboard or slide with the flow line below.

---

## Timing

### Recommended (~8:00) then Q&A

| Clock | Segment | What the room learns |
|-------|---------|----------------------|
| 0:00-1:00 | Hook | Familiar pain without AI jargon |
| 1:00-3:30 | Concepts | What an editor AI is; what Metra adds; routing vs personality |
| 3:30-6:30 | Live demo | CLI map + chat ask + ticket draft contrast |
| 6:30-8:00 | Close | Three takeaways; how to try later; invite questions |

### Strict 5-minute cut

| Clock | Segment |
|-------|---------|
| 0:00-0:40 | Hook (skip long AI primer; one sentence: "chat that can read our folders") |
| 0:40-2:00 | Concepts compressed: routing map + chat vs ticket voice |
| 2:00-4:20 | Live: `routing` only + Prompt A + Prompt B |
| 4:20-5:00 | Three takeaways |

Skip `ctx` and Teaching Mode in the strict cut unless someone asks in Q&A.

---

### 0:00 - Hook (~1 min)

Start from work they already know - not from "AI agents."

> We have a lot of project folders. When someone asks for help on a ticket, an Orion alert, or a Fun Committee printable, the first job is always the same: open the **right** folder and follow **that** project's habits.
>
> People are starting to use AI chat inside the editor for that. Left alone, it often digs through every folder at once, or drafts ticket notes that sound like a brochure. Metra is our small layer on top: point the chat at one project, and keep the writing style sane for real work.

Whiteboard / slide (optional):

```text
Your ask  -->  Metra picks ONE project  -->  That project's rules  -->  Answer or draft
```

---

### 1:00 - Concepts (~2.5 min)

Speak slowly. Define terms once. Do not quiz the room.

**1. What is the AI piece? (~45s)**

> Think of Cursor (or similar tools) as a chat window next to your code. You type a normal request. It can look at files and reply with steps, or - if you allow it - change files. You do not need to know how the model works. You need good habits: ask clearly, check the answer, do not paste secrets.

**2. What is Metra? (~45s)**

> Metra is **not** a new ticket system and **not** a replacement for Solarwinds or iSupport. It is a portfolio helper that sits beside our folders. Two parts matter today:
>
> - **Routing** - a shared list of trigger words that say "this ask belongs in TicketTracker / Solarwinds / Trivia / ..."
> - **Personality** - how the chat talks to **you** while you work
>
> The checkout folder is often named `_meta`. The product name is Metra. The command line tool is `meta.ps1`.

**3. Routing vs personality (~60s)**

> Routing decides **where** work happens. Personality decides **how** the chat sounds.
>
> Routing always wins. A friendly chat does not get to open the wrong repo.
>
> When we write something durable - an iSupport work-history line, a commit message, a Slack note for the team - Metra steps out of character. The text should look like any careful coworker wrote it.
>
> In my normal workflow I usually ask it to **post that into the ticket** through TicketTracker. It does not update iSupport on its own - I have to request it - but most of the time I do request it, so the professional wording actually lands in the ticket.

If someone looks lost, one analogy:

> Like a dispatcher: the radio voice can be friendly, but the ticket still goes to the right truck.

Skip Teaching Mode, overlays, and personal roots unless asked later.

---

### 3:30 - Live demo (~3 min)

Narrate what you are doing. Assume they have never seen this screen.

**Part 1 - The map (CLI) (~75s)**

> This is not magic. It is a table we maintain. Watch the Triggers column - everyday phrases mapped to a project.

```powershell
.\meta.ps1 routing -Name TicketTracker,Solarwinds,Trivia
```

Point at:

- **TicketTracker** - ticket / iSupport / helpdesk
- **Solarwinds** - Orion / alert / monitor
- **Trivia** - Fun Committee / word search / printable

Say:

> TicketTracker and Solarwinds can be optional stubs. If that folder is not on your machine, Metra gives advice instead of failing mysteriously. Your private project list stays on your machine; the shared stub list stays small for the team.

If time allows (~20s), open the already-built `docs/context-pack.md`:

> `ctx` builds a short handout the AI can read so it does not need to scan the whole drive. Useful even if you never open Cursor - you can paste that file into another tool later.

**Part 2 - Chat with Metra (~90s)**

> New chat. I will type a normal Fun Committee question. Watch for two things: it should pick **Trivia**, and the reply should start with Metra naming itself.

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
> Day to day I usually say "post this to ticket N" and it writes the work history into iSupport for me. We are not posting live in this demo - you are seeing the wording that would go in.

If the room needs a third beat and you have 30s: backup Orion prompt (see card below). Otherwise stop.

---

### 6:30 - Close (~1.5 min)

Three takeaways (say them as bullets on a slide if you have one):

1. **Metra steers the AI to one project** so it does not rummage through everything.
2. **Chat can be a helpful coworker voice**; when a ticket is updated (usually on request), the text stays ordinary professional writing.
3. **You can start small** - even looking at the routing table helps you see how we organize work. Using the AI chat is optional.

How to try later (do not live-clone unless asked):

```powershell
cd C:\Projects
git clone <Metra-repo-url> _meta
cd _meta
.\meta.ps1 import-profile -Path .\profiles\sample -Preview
```

> Preview first. No pressure to adopt Cursor this week. Questions are open.

Docs for people who want to read later:

- [Context-Routing.md](Context-Routing.md) - how routing works
- [Customizing-Metra.md](Customizing-Metra.md) - persona and Origin (optional depth)
- [Integrations.md](Integrations.md) - what works without Cursor
- [Brand.md](Brand.md) - Ops board look (optional)
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
| Chat picks wrong project | Show `routing` Triggers row; restate "one project"; new chat + Prompt A |
| No Metra banner | Say "the rule requires it; value is still the route"; continue with Prompt B |
| Chat is slow or blank | Skip to CLI `routing` table; narrate Prompt A/B expected results from this doc |
| Someone asks to "make it change files" | Decline for this demo; Ask mode is intentional |

Do not open personal projects for this audience.

---

## Anticipated Q&A (beginner-friendly)

**Do I have to use AI / Cursor?**  
No. Metra's command-line map and docs are useful on their own. Cursor is the nicest place to see the personality. Adoption is optional.

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
Browser chat usually cannot see our project folders or our routing table. Metra is built for this multi-folder work layout.

**Does Teaching Mode quiz me?**  
No. When you are exploring, it should answer first, give one next step, and stop. No pop quizzes.

---

## One-line opener / closer

**Open:** Metra helps an editor AI find the right project folder and keep ticket writing professional.  
**Close:** Remember the three points - one project, chat vs ticket voice, start when you are ready - then ask anything.
