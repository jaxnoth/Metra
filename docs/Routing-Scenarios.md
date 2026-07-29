# Routing scenario checklist

Use after changing registries, project `AGENTS.md`, or `.cursorignore`.

| Scenario | Expected first stop | Pass criteria |
|----------|---------------------|---------------|
| Ticket / iSupport / helpdesk ask | TicketTracker | Load TT `AGENTS.md`; use `brief` not raw `data/tickets.json` |
| Ambiguous ticket text | TicketTracker then one technical project | `brief` RoutingTerms match registry triggers; optional `chats <id>` for prior Cursor clues |
| Orion alert / SAM / SWQL | Solarwinds | Load SW `AGENTS.md` + triage; use `Get-OrionCatalog` / active alerts; no full `catalog/index.*` |
| Fun Committee / IT printable / word search | Trivia (work root) | Stay on work root; do not open personal bible games unless named |
| Personal bible bingo / quiz / roku | Matching personal root project | Stay on personal root; do not open work Trivia or Misc unless asked |
| Cross-root ask ("copy Misc sheets into Trivia") | Named destination first | Open the other root only for that handoff |
| Coworker clone missing TicketTracker / Solarwinds | Advice-only stub | `.\meta.ps1 routing -MissingOnly` shows `whenMissing`; not drift |
| Cross-project (e.g. Pharos + Colleague) | TicketTracker -> primary technical repo | Open related project only after primary evidence; same root |

## Persona smoke (Metra)

Use after changing `.cursor/rules/metra-persona.mdc`, the local overlay, or the Persona section in `AGENTS.md`. See also [Customizing-Metra.md](Customizing-Metra.md).

| Scenario | Pass criteria |
|----------|---------------|
| Fun Committee / word search ask | Routes to Trivia; chat tone is Metra (verdict-first, light dry) |
| Draft ticket `post` text | Professional bullets/headings; no Metra voice or AI puffery (AISIGNS on artifacts) |
| Chat dry work-context aside | Allowed in chat without AISIGNS scrubbing; does not delay the route/answer |
| First reply of a new chat (routine) | Optional brief time-of-day aside OK with banner; may use overlay operator name; one beat max |
| First reply during incident / outage | Banner present; **no** time-of-day greeting or humor; flat next action |
| "Draft a Slack update about X" (for the operator) | Metra voice OK; still sendable and concrete |
| Coworker email / redistribution Slack | Flatter tone; less personal humor; still concrete |
| Personal-root bible bingo / quiz ask | Routes to personal project; slightly warmer OK; isolation unchanged |
| Ambiguous "quiz" | Clarify once or prefer work Trivia triggers; do not invent personal paths |
| Incident / outage ask | Banner present; no humor or optional flavor; flat next action |
| Urgent + banner | Model disclosure line still present every reply |
| Unknown / missing project | Say unknown; suggest `.\meta.ps1 routing`; do not invent folders |
| Mixed-root / cross-root ask | Explicit approval before opening both scopes |
| Paraphrase the same route ask twice | Recognizably Metra without a catchphrase |
| Forced joke / catchphrase pressure | Humor stays opportunistic; never required; never delays work |
| Mid-thread after work started | No repeated greetings every turn |

### Personality change vet

Before merging a persona edit: improves portfolio (routing/code/docs/tickets)? No regression to routing, root isolation, or professional sink? Not "protect old voice"? Blast radius limited to persona rule + AGENTS examples (or local overlay)? Humor still opportunistic (no quota)? Redistribution still flatter than operator-chat? Re-run this smoke table.

## Fixture checks (automated smoke)

```powershell
Test-Path .\projects.json
Test-Path .\projects.local.json
Test-Path .\profiles\sample\meta-profile.json
Test-Path ..\TicketTracker\AGENTS.md
Test-Path ..\Trivia\AGENTS.md
Test-Path ..\Solarwinds\docs\Ticket-Triage.md
Select-String -Path ..\TicketTracker\TicketTracker.ps1 -Pattern "'brief'"
Select-String -Path ..\TicketTracker\TicketTracker.ps1 -Pattern "'chats'"
.\meta.ps1 roots
.\meta.ps1 routing -Name TicketTracker,Solarwinds,Trivia
.\meta.ps1 import-profile -Path .\profiles\sample -Preview
.\meta.ps1 audit -Name Solarwinds,TicketTracker,Trivia -DriftOnly
.\meta.ps1 chats -Name Solarwinds -Query "alert" -Limit 3
```
