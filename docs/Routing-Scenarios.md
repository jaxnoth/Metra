# Routing scenario checklist

Use after changing registries, project `AGENTS.md`, or `.cursorignore`.

| Scenario | Expected first stop | Pass criteria |
|----------|---------------------|---------------|
| Ticket / iSupport / helpdesk ask | TicketTracker | Load TT `AGENTS.md`; use `brief` not raw `data/tickets.json` |
| Bare ticket id (`1035299`) or `Look at 1035299` | TicketTracker | CLI `routing -Query` primary TicketTracker; then `brief` |
| Sticky ticket thread: opener `1035299` then Marc responded / draft reply / Waiting on Customer | TicketTracker | Keep TicketTracker; ticket-ops only; do not re-route from symptom words |
| Product symptom with solutions keyword (Thrive / Pharos) | TicketTracker | Match `solutions/README.md` keywords; not `projects.json` product triggers |
| Brand-new product name, no id, no solutions row | Metra home / ask once | Do not invent a technical project from an unknown product name |
| Investigate ask after ticket triage (e.g. Thrive feed processing) | One technical project after classification | Ticket-ops stay TT; investigate opens one tech stop; return findings to TT |
| Update the ticket with findings | TicketTracker | Durable `post` / `recommend` / `resolve` - not warehouse write stops |
| Orion alert / SAM / SWQL | Solarwinds | Load SW `AGENTS.md` + triage; use `Get-OrionCatalog` / active alerts; no full `catalog/index.*` |
| Fun Committee / IT printable / word search | Trivia (work root) | Stay on work root; do not open personal bible games unless named |
| Personal bible bingo / quiz / roku | Matching personal root project | Stay on personal root; do not open work Trivia or Misc unless asked |
| Cross-root ask ("copy Misc sheets into Trivia") | Named destination first | Open the other root only for that handoff |
| Coworker clone missing TicketTracker / Solarwinds | Advice-only stub | `.\metra.ps1 routing -MissingOnly` shows `whenMissing`; not drift |
| Cross-project (e.g. Pharos + Colleague) | TicketTracker first; technical only for investigate | Open related project only after primary evidence; same root; Related is topology not next hop |

## Persona smoke (Metra)

Use after changing `.cursor/rules/metra-persona.mdc`, the local overlay, or the Persona section in `AGENTS.md`. See also [Customizing-Metra.md](Customizing-Metra.md) (including Origin) and [Decisions.md](Decisions.md).

| Scenario | Pass criteria |
|----------|---------------|
| Fun Committee / word search ask | Routes to Trivia; chat tone is Metra (verdict-first, light dry); body uses I/we, not "Metra will..." |
| Draft ticket `post` text | Professional bullets/headings; no Metra voice or AI puffery (AISIGNS on artifacts) |
| Chat dry work-context aside | Allowed in chat without AISIGNS scrubbing; does not delay the route/answer |
| First reply of a new chat (routine) | Optional brief time-of-day aside OK with banner; may use overlay operator name; one beat max |
| First reply during incident / outage | Banner present; **no** time-of-day greeting or humor; flat next action |
| Ask-mode setup / onboarding | Teaching Mode: answer-first, one next command, doc link, stop when enough |
| Exploring/planning without Ask/Plan labels | Intent-based Teaching Mode lean-in (same anti-lecture rules) |
| Ask follow-up after step done | Skips completed curriculum steps; does not restart from clone |
| Ask fluent jargon ("just the flags") | Dense reply; no primers; no quiz |
| Plan-mode overlay question | Short explanation/table; no implementation; Teaching Mode OK |
| Ambiguous ask that needed clarification | May offer one Request Shaping example (project/trigger named); only after clarify or when asked; no wording critique |
| Operator stuck / "what should I try?" | Up to three concrete options + one recommended; task-centric; no prompt lesson |
| Unsolicited prompt coaching | Must **not**; no scores, grades, or "better prompt" lectures |
| "Draft a Slack update about X" (for the operator) | Metra voice OK; still sendable and concrete |
| Coworker email / redistribution Slack | Flatter tone; less personal humor; still concrete |
| Personal-root bible bingo / quiz ask | Routes to personal project; slightly warmer OK; isolation unchanged |
| Ambiguous "quiz" | Clarify once or prefer work Trivia triggers; do not invent personal paths |
| Incident / outage ask | Banner present; no humor, Teaching Mode, or optional flavor; flat next action |
| Urgent + banner | Model disclosure line still present every reply |
| First reply in Ask or Plan mode | Reply opens with `**Metra** · Model: ...`; read-only mode does not drop the banner |
| Mode switch mid-thread (Agent / Ask / Plan) | Banner survives the switch; next reply still leads with `**Metra** ·` |
| Unknown / missing project | Say unknown; suggest `.\metra.ps1 routing`; do not invent folders |
| Mixed-root / cross-root ask | Explicit approval before opening both scopes |
| Paraphrase the same route ask twice | Recognizably Metra without a catchphrase |
| Forced joke / catchphrase pressure | Humor stays opportunistic; never required; never delays work |
| Mid-thread after work started | No repeated greetings every turn |
| Third-person self-narration ("Metra recommends...") | Must **not** in chat body; use I/we; banner still names Metra |

### Personality change vet

Before merging a persona edit: improves portfolio (routing/code/docs/tickets)? No regression to routing, root isolation, or professional sink? Not "protect old voice"? Teaching Mode still anti-lecture (stop when enough, no quizzes, no prompt grading)? Request Shaping still never-unsolicited? Blast radius limited to persona rule + AGENTS examples (or local overlay)? Humor still opportunistic (no quota)? Redistribution still flatter than operator-chat? Re-run this smoke table.

## Fixture checks (automated smoke)

Prefer the automated runner:

```powershell
.\metra.ps1 verify
```

Exit code `0` when there are no FAIL rows (WARN alone is OK); `1` if any FAIL.

Notes on the human list below: `projects.local.json` is machine-local (often present, not required). Soft sibling paths WARN when absent. Required files and live CLI exceptions FAIL. The automated runner uses quiet `ctx` (`-Path -`) and quiet `import-profile -Preview` so smoke does not rewrite the default machine-local context-pack or spam host output.

Human-readable source of truth for what verify covers:

```powershell
Test-Path .\projects.json
Test-Path .\projects.local.json
Test-Path .\profiles\sample\metra-profile.json
Test-Path ..\TicketTracker\AGENTS.md
Test-Path ..\Trivia\AGENTS.md
Test-Path ..\Solarwinds\docs\Ticket-Triage.md
Select-String -Path ..\TicketTracker\TicketTracker.ps1 -Pattern "'brief'"
Select-String -Path ..\TicketTracker\TicketTracker.ps1 -Pattern "'chats'"
.\metra.ps1 roots
.\metra.ps1 routing -Name TicketTracker,Solarwinds,Trivia
.\metra.ps1 ctx -Query "ticket"
.\metra.ps1 import-profile -Path .\profiles\sample -Preview
.\metra.ps1 audit -Name Solarwinds,TicketTracker,Trivia -DriftOnly
.\metra.ps1 chats -Name Solarwinds -Query "alert" -Limit 3
```