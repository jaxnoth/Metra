# Projects Meta Repo

Orchestration repo for sibling folders under `C:\Projects`. It does **not** absorb other repos; it discovers them and runs commands across them, and can create new project folders.

## Quick start

From this folder (`C:\Projects\_meta`):

```powershell
.\meta.ps1 list
.\meta.ps1 status
.\meta.ps1 pull
.\meta.ps1 new MyProject -Description "What this is for"
.\meta.ps1 run "git status -sb" -GitOnly
.\meta.ps1 apply .\shared\.editorconfig -RelativePath .editorconfig -Filter "IWU*"
```

Import the module directly if you prefer:

```powershell
Import-Module .\scripts\Meta.psm1 -Force
Get-MetaProjects
Invoke-AcrossProjects -Command 'git remote -v' -GitOnly
New-MetaProject -Name DemoOps -Description 'scratch'
```

## Commands

| Command | Purpose |
|---------|---------|
| `list` | Show project folders (optional `-GitOnly`, `-Filter`) |
| `status` | `git status -sb` in each git project |
| `pull` / `fetch` | Fast-forward pull or fetch across git projects |
| `run <cmd>` | Run any shell command in each matching project |
| `new <Name>` | Create a new sibling project from a template + `git init` |
| `apply <file>` | Copy a shared file into matching projects |
| `workspace` | Rebuild multi-root workspace from recent activity |
| `audit` | Context/token audit + optional `-DriftOnly` vs `projects.json` |
| `snapshot` | Write `docs/canvas-snapshot.json` and refresh Ops canvas embed |
| `chats` | Search local Cursor agent transcripts for ticket/keyword clues (bounded) |

### Filters

- `-Filter 'IWU*'` - wildcard on folder name
- `-Name A,B` - exact project names
- `-GitOnly` - only folders that already have `.git`
- `-ContinueOnError` - keep going if one project fails (`run`)

## Layout

```
_meta/
  meta.ps1              CLI entrypoint
  meta.config.json      projects root + excludes
  projects.json         agent routing registry
  AGENTS.md             meta agent entry
  scripts/Meta.psm1     PowerShell helpers
  docs/                 context routing + audit cadence
  templates/basic/      default new-project template
  shared/               files to push into other projects via apply
```

Edit `meta.config.json` to change the projects root (default `..` = `C:\Projects`) or exclude folders.

## Creating projects

```powershell
.\meta.ps1 new ReportingOps -Description "Ops scripts for reporting"
.\meta.ps1 new ScratchPad -Template basic -NoGit
```

New folders are created as siblings of `_meta` (under `C:\Projects`), not inside this repo.

## Cross-project adjustments

Run a one-off:

```powershell
.\meta.ps1 run "git checkout main" -GitOnly -ContinueOnError
```

Push a shared file:

```powershell
.\meta.ps1 apply .\shared\.editorconfig -RelativePath .editorconfig
```

Scripted batch work:

```powershell
Import-Module .\scripts\Meta.psm1 -Force
Invoke-AcrossProjects -Filter 'Colleague*' -ScriptBlock {
    if (Test-Path .\package.json) { npm ci }
}
```

## Agent routing

Agents should classify work, consult [`projects.json`](projects.json), and load one project `AGENTS.md` before scanning siblings. Ticket work starts in TicketTracker. Details: [docs/Context-Routing.md](docs/Context-Routing.md). Visual board: ask Cursor to open the Meta Ops canvas, then refresh with:

```powershell
.\meta.ps1 audit
.\meta.ps1 audit -DriftOnly
.\meta.ps1 snapshot
.\meta.ps1 chats -Name Solarwinds -Query "disk alert"
```

Ticket triage can also run `.\TicketTracker.ps1 chats <id>` to search related Cursor chats, then promote durable findings with `note -Tags chat`. Details: [docs/Context-Routing.md](docs/Context-Routing.md).

## Notes

- Nested git repos stay independent; this meta repo only tracks its own scripts/config.
- Do not commit secrets into `shared/` and then `apply` them into every project.
- `_meta` is excluded from discovery via `meta.config.json`.
- Solarwinds and TicketTracker are pinned via `workspace.alwaysInclude`.
