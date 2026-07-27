# Meta agent guide

Orchestration repo for sibling folders under `C:\Projects`. Prefer routing over broad multi-repo search.

## Route first

1. Read [`projects.json`](projects.json) and match trigger terms to one project.
2. For tickets / iSupport / helpdesk: start in **TicketTracker**, then route to one technical project.
3. Load that project's `AGENTS.md` (or README if none). Do not scan other repos yet.
4. Broaden to `related` projects only when evidence requires it.

## Commands

```powershell
.\meta.ps1 list
.\meta.ps1 audit
.\meta.ps1 audit -Name Solarwinds,TicketTracker
.\meta.ps1 audit -DriftOnly
.\meta.ps1 workspace
.\meta.ps1 chats -Name Solarwinds -Query "disk alert"
```

## Token rules

- Do not open generated catalogs, inventory dumps, `node_modules`, or local ticket caches unless required.
- Prefer project CLI filters (`Get-OrionCatalog`, `TicketTracker.ps1 brief` / `chats`) over reading large JSON/YAML or full agent transcripts wholesale.
- Keep `_meta` guidance short; project details stay local. Promote durable chat clues into TicketTracker `note` / `solutions/`.

## Maintenance

Re-run `.\meta.ps1 audit` after adding a project or changing layout. Update `projects.json`, project `AGENTS.md`, and `.cursorignore` only when audit reports drift. See [docs/Context-Routing.md](docs/Context-Routing.md).
