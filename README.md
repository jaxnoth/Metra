# Projects Meta Repo

Orchestration repo for project folders under one or more roots (default work root `C:\Projects`, optional personal roots). It does **not** absorb other repos; it discovers them and runs commands across them, and can create new project folders.

## Quick start

From this folder (`C:\Projects\_meta`):

```powershell
.\meta.ps1 list
.\meta.ps1 list -Root personal
.\meta.ps1 roots
.\meta.ps1 routing
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
Get-MetaRoots
Get-MetaRoutingTable
Invoke-AcrossProjects -Command 'git remote -v' -GitOnly
New-MetaProject -Name DemoOps -Description 'scratch'
```

## Commands

| Command | Purpose |
|---------|---------|
| `list` | Show project folders (optional `-GitOnly`, `-Filter`, `-Root`) |
| `roots` | Show configured project roots and whether each exists |
| `routing` | Show merged registry entries vs disk (`-SharedOnly`, `-MissingOnly`) |
| `status` | `git status -sb` in each git project |
| `pull` / `fetch` | Fast-forward pull or fetch across git projects |
| `run <cmd>` | Run any shell command in each matching project |
| `new <Name>` | Create a new project under the primary root (or `-Root`) |
| `apply <file>` | Copy a shared file into matching projects |
| `workspace` | Rebuild multi-root workspace from recent activity |
| `audit` | Context/token audit + optional `-DriftOnly` vs registries |
| `snapshot` | Write `docs/canvas-snapshot.json` and refresh Ops canvas embed |
| `chats` | Search local Cursor agent transcripts for ticket/keyword clues (bounded) |

### Filters

- `-Filter 'IWU*'` - wildcard on folder name
- `-Name A,B` - exact project names
- `-Root work,personal` - limit to configured roots
- `-GitOnly` - only folders that already have `.git`
- `-ContinueOnError` - keep going if one project fails (`run`)

## Layout

```
_meta/
  meta.ps1                   CLI entrypoint
  meta.config.json           local roots + excludes (from example)
  meta.config.example.json   starter config for new machines
  projects.json              shared agent routing registry
  projects.local.json        machine-private routing (gitignored)
  projects.local.example.json
  AGENTS.md                  meta agent entry
  scripts/Meta.psm1          PowerShell helpers
  docs/                      context routing + audit cadence
  templates/basic/           default new-project template
  shared/                    files to push into other projects via apply
```

Edit `meta.config.json` to change roots (or the legacy single `projectsRoot`). Start from [`meta.config.example.json`](meta.config.example.json) when setting up a new machine.

## Distribute

`_meta` is the shareable piece - not a zip of every sibling under `C:\Projects`. Put this repo on a private remote, then clone it beside project folders.

### Layout on each machine

```text
C:\Projects\                 (work root)
  _meta\                     ← clone of this repo
  Reporting\
  TicketTracker\
  Trivia\
  ...

%USERPROFILE%\iCloudDrive\Projects\   (optional personal root)
  BibleBingo\
  projects.personal.json     ← travels with the personal root
```

### First-time setup (coworkers or personal)

```powershell
cd C:\Projects
git clone <meta-remote-url> _meta
cd _meta
Copy-Item .\meta.config.example.json .\meta.config.json
# Adjust roots / exclude / workspace.alwaysInclude if needed
# Optionally copy projects.local.example.json -> projects.local.json for private entries
.\meta.ps1 workspace
.\meta.ps1 audit
.\meta.ps1 snapshot
```

Open `Meta.code-workspace` (or the root `Meta.code-workspace` sibling) in Cursor.

### What is shared vs local

| Ship in git | Keep local / regenerate |
|-------------|-------------------------|
| `meta.ps1`, `scripts/`, `templates/`, `shared/` | `meta.config.json` (from example; machine paths differ) |
| `projects.json` (shared stubs only), `AGENTS.md`, routing docs | `projects.local.json` (private work routing) |
| `.cursor/rules/` | Root `registryFile` beside personal projects |
| `meta.config.example.json`, `projects.local.example.json` | `Meta.code-workspace` (`.\meta.ps1 workspace`) |
| | `docs/canvas-snapshot.json` (`.\meta.ps1 snapshot`) |
| | TicketTracker `data/`, secrets, Solarwinds inventory |

### Coworkers (shared IWU portfolio)

- Use the shared `projects.json` so agent routing matches for designated projects (TicketTracker, Solarwinds).
- Optional stubs give advice when those folders are missing instead of failing loudly.
- Set `workspace.alwaysInclude` to pinned folders you always want in the multi-root workspace.
- They do not need your `projects.local.json`, ticket cache, Orion inventory dumps, or secrets.

### Personal project folders

- Add an optional root in `meta.config.json` pointing at the synced folder (env vars like `%USERPROFILE%` are expanded).
- Put personal routing in that root's `registryFile` so it syncs with the projects.
- Keep work and personal roots isolated unless a chat explicitly asks to move material between them.

### Do not package

- Sibling repos inside `_meta`
- Machine-specific snapshots as the source of truth
- Secrets under `shared/` then `apply` across projects

## Creating projects

```powershell
.\meta.ps1 new ReportingOps -Description "Ops scripts for reporting"
.\meta.ps1 new ScratchPad -Template basic -NoGit
.\meta.ps1 new SermonNotes -Root personal
```

New folders are created under the primary root (or `-Root`), not inside this repo.

## Cross-project adjustments

Run a one-off:

```powershell
.\meta.ps1 run "git checkout main" -GitOnly -ContinueOnError
.\meta.ps1 run "git status -sb" -Root work -GitOnly
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

Agents should classify work, consult the merged registry (`.\meta.ps1 routing`), and load one project `AGENTS.md` before scanning siblings. Ticket work starts in TicketTracker. Keep work and personal roots isolated unless the user names a cross-root project. Details: [docs/Context-Routing.md](docs/Context-Routing.md). Visual board: ask Cursor to open the Meta Ops canvas, then refresh with:

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
- Solarwinds, TicketTracker, Misc, and Trivia are pinned via `workspace.alwaysInclude`.
