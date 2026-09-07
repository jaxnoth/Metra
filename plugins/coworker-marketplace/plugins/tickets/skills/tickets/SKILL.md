---
name: tickets
description: >-
  TicketTracker desk skill for helpdesk tickets: brief, assess, Recommend
  Preview, durable text shape for recommend/post/resolve, and related ticket-ops.
  Use for ticket ids, iSupport work, Metra AI Recommendation preview, or
  formatting ticket bodies. Default Off; zero iSupport write authority. Invokes
  TicketTracker CLI only; does not define recommendation policy.
disable-model-invocation: true
---

# Tickets

Single TicketTracker procedure skill for ticket work. Expandable over time.
**Skill is not authority.** Assessment logic, gates, quality, and publish rules
live in TicketTracker CLI and playbooks. This skill sequences commands and
reminds format rules only.

**Maintainer source of truth:** TicketTracker checkout
`.cursor\skills\tickets\SKILL.md` (sync into this plugin with
`.\scripts\Sync-TicketsSkill.ps1` from the marketplace root).

## Authority

| Owns | Does not own |
|------|--------------|
| Pointing at `.\TicketTracker.ps1 brief` / `assess` / Preview | Recommendation policy, ranking, confidence wording |
| Reminding S1a ceilings and hop return | iSupport writes (`post` / `recommend` / `resolve`) |
| Plain-text body shape for CLI HTML conversion | Whether to recommend / post / resolve |
| Keeping ticket-ops in TicketTracker | Metra routing, registry, persona, inspect |

Skills **invoke** existing TicketTracker workflows. Skills **may not** define
recommendation policy.

## Workflow

Run from `<TicketTracker checkout>` (or with that as working directory):

1. **`brief`** - local orientation packet (prefer over `show`).
2. **`assess`** - gate + packet + draft; local artifact under `data/assessments/`.
3. **`assess ... -Recommend -Preview`** - full publish decision path with
   **zero** durable writes (`WriteAttempts=0`).

```powershell
.\TicketTracker.ps1 brief <id|NUMBER>
.\TicketTracker.ps1 assess <id|NUMBER>
.\TicketTracker.ps1 assess <id|NUMBER> -Recommend -Preview -Minutes 15
```

Stop after Preview unless the **operator** explicitly asks for a durable write
via existing commands (`assess -Recommend` without `-Preview`, or manual
`recommend` / `post` / `resolve`).

Optional local-only helpers (still no iSupport write):

```powershell
.\TicketTracker.ps1 assess <id> -FactsOnly
.\TicketTracker.ps1 assess <id> -DraftRecommend
```

## S1a ceilings (encode; do not reinvent)

Read TicketTracker `docs\playbooks\ticket-assess.md` when depth is needed.
Hard rules for this skill:

1. **Assess is not publication.** Packet, gate, draft, quality, and Preview stay
   local until deliberate `-Recommend` **without** `-Preview`.
2. **Never auto** `post` / `recommend` / `resolve` (including TicketWatch).
3. **Ticket-ops stay in TicketTracker** (drafts, status, durable commands).
4. **One technical investigate hop** only when needed, then **return** to
   TicketTracker for any durable outcome (see
   `docs\playbooks\technical-investigate-hop.md`).
5. Prefer no recommend over junk; quality/safety must pass before any description
   write (CLI enforces; skill does not invent a second policy).
6. Description `Metra AI Recommendation:` is write-once after first good publish;
   later assess publish is history-oriented (CLI lock).

## Ticket-ops vs investigate

| Ask | Where |
|-----|--------|
| Status, drafts, Preview, `post` / `recommend` / `resolve` | TicketTracker only |
| Live system evidence for a named hop | One technical project, then return |

Do not open sibling repos from symptom words alone. Do not treat this skill as a
Metra product entry.

## Durable text shape (format only)

When the operator already supplied substance for `recommend` / `post` /
`resolve`, shape plain text for `ConvertTo-ISupportHtml`. Does not invent
diagnoses, rank evidence, set confidence language, or decide whether to publish.

Professional sink: durable ticket text is ordinary professional prose - no Metra
chat voice, no logos/chrome, no personality in bodies.

Read when formatting (TicketTracker checkout):

- `docs\playbooks\isupport-text-format.md`
- `docs\playbooks\durable-edits.md`

Pass structured plain text (PowerShell here-string), **not** raw HTML and not one
unbroken paragraph.

| Plain text | Renders as |
|------------|------------|
| Line ending in `:` | Bold paragraph heading |
| Consecutive lines starting with `- ` | Unordered list |
| `[label](https://...)` / `[label](http://...)` | Clickable link (e.g. Codex KB cites) |
| `[label](stub:...)` or non-http schemes | Literal encoded text (not an anchor) |
| Blocks separated by a blank line | Separate paragraphs |

Recommend body reminders:

- Pass **body content only** to `recommend` - the CLI prefixes
  `Metra AI Recommendation:`. Do **not** include that heading in the argument.
- Prefer short headings plus bullets over a wall of text.
- No Metra logos or Metra chrome in description / work history.

Example shape (illustrative only - not a live write):

```powershell
.\TicketTracker.ps1 recommend <id> @'
Next step:
- Confirm X with requester.
- Cite: [Article title](https://...)

Evidence:
- Similar ticket NNNNNN matched symptom Y.
'@ -Minutes 15
```

Do not run durable writes during skill smoke unless the operator explicitly asks.

## Hard offs

- Extra marketplace skills for TicketTracker format/assess slices (grow this skill)
- Marketplace / Cloud Required publish
- Replacing `metra.ps1 routing` or duplicating Metra registry / persona / inspect
- Auto-write or Confirm-bypass language
- Defining recommendation generation, evidence ranking, confidence wording, or
  publish policy in this skill
- Raw HTML in CLI text arguments

## Smoke (no live iSupport write)

1. Pick a known local/fixture ticket id (or operator-supplied open ticket).
2. Run `brief` then `assess` (local artifact OK).
3. Run `assess <id> -Recommend -Preview -Minutes 15`.
4. Confirm Preview reports no durable write (`WriteAttempts=0` or equivalent).
5. Optionally draft a here-string with heading `:` lines, `- ` bullets, and one
   http cite; omit the `Metra AI Recommendation:` heading.
6. Do **not** run `assess -Recommend` without `-Preview`, `recommend`, `post`, or
   `resolve` during smoke.
