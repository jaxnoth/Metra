# Routing scenario checklist

Use after changing `projects.json`, project `AGENTS.md`, or `.cursorignore`.

| Scenario | Expected first stop | Pass criteria |
|----------|---------------------|---------------|
| Ticket / iSupport / helpdesk ask | TicketTracker | Load TT `AGENTS.md`; use `brief` not raw `data/tickets.json` |
| Ambiguous ticket text | TicketTracker then one technical project | `brief` RoutingTerms match `_meta/projects.json` triggers; optional `chats <id>` for prior Cursor clues |
| Orion alert / SAM / SWQL | Solarwinds | Load SW `AGENTS.md` + triage; use `Get-OrionCatalog` / active alerts; no full `catalog/index.*` |
| Cross-project (e.g. Pharos + Colleague) | TicketTracker -> primary technical repo | Open related project only after primary evidence |

## Fixture checks (automated smoke)

```powershell
Test-Path .\projects.json
Test-Path ..\TicketTracker\AGENTS.md
Test-Path ..\Solarwinds\docs\Ticket-Triage.md
Select-String -Path ..\TicketTracker\TicketTracker.ps1 -Pattern "'brief'"
Select-String -Path ..\TicketTracker\TicketTracker.ps1 -Pattern "'chats'"
.\meta.ps1 audit -Name Solarwinds,TicketTracker -DriftOnly
.\meta.ps1 chats -Name Solarwinds -Query "alert" -Limit 3
```
