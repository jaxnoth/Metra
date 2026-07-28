# Routing scenario checklist

Use after changing registries, project `AGENTS.md`, or `.cursorignore`.

| Scenario | Expected first stop | Pass criteria |
|----------|---------------------|---------------|
| Ticket / iSupport / helpdesk ask | TicketTracker | Load TT `AGENTS.md`; use `brief` not raw `data/tickets.json` |
| Ambiguous ticket text | TicketTracker then one technical project | `brief` RoutingTerms match registry triggers; optional `chats <id>` for prior Cursor clues |
| Orion alert / SAM / SWQL | Solarwinds | Load SW `AGENTS.md` + triage; use `Get-OrionCatalog` / active alerts; no full `catalog/index.*` |
| Fun Committee / IT printable / word search | Trivia (`C:\Projects\Trivia`) | Stay on work root; do not open personal bible games unless named |
| Personal bible bingo / quiz / roku | Matching personal root project | Stay on personal root; do not open work Trivia or Misc unless asked |
| Cross-root ask ("copy Misc sheets into Trivia") | Named destination first | Open the other root only for that handoff |
| Coworker clone missing TicketTracker / Solarwinds | Advice-only stub | `.\meta.ps1 routing -MissingOnly` shows `whenMissing`; not drift |
| Cross-project (e.g. Pharos + Colleague) | TicketTracker -> primary technical repo | Open related project only after primary evidence; same root |

## Persona smoke (Metra)

Use after changing `.cursor/rules/metra-persona.mdc` or the Persona section in `AGENTS.md`.

| Scenario | Pass criteria |
|----------|---------------|
| Fun Committee / word search ask | Routes to Trivia; chat tone is Metra (verdict-first, light dry) |
| Draft iSupport `post` text | Professional bullets/headings; no Metra voice or AI puffery |
| "Draft a Slack update about X" | Metra voice OK; still sendable and concrete |
| Ambiguous "quiz" | Clarify once or prefer work Trivia triggers; do not invent personal paths |
| Paraphrase the same route ask twice | Recognizably Metra without a catchphrase |

### Personality change vet

Before merging a persona edit: improves portfolio (routing/code/docs/tickets)? No regression to routing, root isolation, or professional sink? Not "protect old voice"? Blast radius limited to persona rule + AGENTS examples? Re-run this smoke table.

## Fixture checks (automated smoke)

```powershell
Test-Path .\projects.json
Test-Path .\projects.local.json
Test-Path ..\TicketTracker\AGENTS.md
Test-Path ..\Trivia\AGENTS.md
Test-Path ..\Solarwinds\docs\Ticket-Triage.md
Select-String -Path ..\TicketTracker\TicketTracker.ps1 -Pattern "'brief'"
Select-String -Path ..\TicketTracker\TicketTracker.ps1 -Pattern "'chats'"
.\meta.ps1 roots
.\meta.ps1 routing -Name TicketTracker,Solarwinds,Trivia
.\meta.ps1 audit -Name Solarwinds,TicketTracker,Trivia -DriftOnly
.\meta.ps1 chats -Name Solarwinds -Query "alert" -Limit 3
```
