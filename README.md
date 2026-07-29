# Meta (portfolio ops + Metra)

Orchestration repo for project folders under one or more roots. It discovers sibling projects, runs commands across them, routes AI agents to one project at a time, and ships **Metra** - a chat persona for portfolio ops (routing wins; durable artifacts stay professional).

MIT licensed. Host on public GitHub or a private org fork.

## Quick start (public clone)

```powershell
cd C:\Projects   # or your work root
git clone <this-repo-url> _meta
cd _meta
.\meta.ps1 import-profile -Path .\profiles\sample -Force
# Edit meta.config.json roots / workspace.alwaysInclude
# Edit .cursor\rules\metra-persona.local.mdc operator display name (replace Alex)
.\meta.ps1 workspace
.\meta.ps1 audit
.\meta.ps1 routing
```

Open `Meta.code-workspace` in Cursor. Optional stubs in `projects.json` (TicketTracker, Solarwinds) teach routing; they are **not** required installs - `whenMissing` advice appears if those folders are absent.

Preview a pack without writing:

```powershell
.\meta.ps1 import-profile -Path .\profiles\sample -Preview
```

## What ships vs stays local

| Ship in git | Keep local / export via profile |
|-------------|-------------------------------|
| CLI, module, templates, shared/ | `meta.config.json` |
| `projects.json` (example stubs) | `projects.local.json` |
| `metra-persona.mdc` (full base) | `.cursor/rules/metra-persona.local.mdc` |
| `*.example.json` / `*.local.example.mdc` | `docs/canvas-snapshot.json` |
| `profiles/sample/` (ready-to-import pack) | regenerated workspaces |
| MIT LICENSE, public docs | |

Move yourself between machines:

```powershell
.\meta.ps1 export-profile -Path $env:TEMP\my-meta-profile.zip
# on the other machine, after clone:
.\meta.ps1 import-profile -Path $env:TEMP\my-meta-profile.zip -Force
```

Personal-root `registryFile` (e.g. `projects.personal.json` beside personal projects) is **not** auto-included in profile packs - copy it with that root. Details: [docs/Customizing-Metra.md](docs/Customizing-Metra.md), [SECURITY.md](SECURITY.md).

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
| `chats` | Search local Cursor agent transcripts (bounded) |
| `export-profile` | Pack local config / local registry / Metra overlay |
| `import-profile` | Restore a pack (`-Preview` or `-Force`) |

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
  meta.config.example.json   starter config (live meta.config.json is gitignored)
  projects.json              shared agent routing registry (example stubs OK)
  projects.local.example.json
  profiles/sample/           anonymized operator pack
  AGENTS.md                  meta agent entry
  LICENSE                    MIT
  SECURITY.md
  scripts/Meta.psm1          PowerShell helpers
  docs/                      routing + Metra customization
  templates/basic/           default new-project template
  shared/                    files to push into other projects via apply
  .cursor/rules/             routing + Metra base (+ local overlay gitignored)
```

## Distribute / first-time layout

```text
C:\Projects\                 (work root)
  _meta\                     <- clone of this repo
  Reporting\
  TicketTracker\             (optional; stub in projects.json)
  ...

%USERPROFILE%\iCloudDrive\Projects\   (optional personal root)
  MyPersonalApp\
  projects.personal.json     <- travels with the personal root
```

```powershell
Copy-Item .\meta.config.example.json .\meta.config.json   # if not using import-profile
# or: .\meta.ps1 import-profile -Path .\profiles\sample -Force
.\meta.ps1 workspace
.\meta.ps1 audit
```

### Shared vs local vs overlay

| Layer | Role |
|-------|------|
| `projects.json` | Shared routing stubs (coworkers / public teaching examples) |
| `projects.local.json` | Machine-private work routing (gitignored) |
| Root `registryFile` | Travels with that root (e.g. personal iCloud) |
| `metra-persona.mdc` | Full base Metra personality (tracked) |
| `metra-persona.local.mdc` | Operator name / greeting / team notes (gitignored) |

TicketTracker and Solarwinds entries in `projects.json` are optional examples: routing advice when missing, not hard dependencies.

### Do not package

- Sibling repos inside `_meta`
- Live `meta.config.json`, local registries, overlays, or canvas snapshots as the public source of truth (sample under `profiles/sample/` is intentional and anonymized)
- Secrets under `shared/` then `apply` across projects

## Creating projects

```powershell
.\meta.ps1 new ReportingOps -Description "Ops scripts for reporting"
.\meta.ps1 new ScratchPad -Template basic -NoGit
.\meta.ps1 new SermonNotes -Root personal
```

## Cross-project adjustments

```powershell
.\meta.ps1 run "git status -sb" -Root work -GitOnly
.\meta.ps1 apply .\shared\.editorconfig -RelativePath .editorconfig
```

## Agent routing

Classify work, consult `.\meta.ps1 routing`, load one project `AGENTS.md` before scanning siblings. Ticket work starts in TicketTracker when present. Keep work and personal roots isolated unless the user names a cross-root project. Details: [docs/Context-Routing.md](docs/Context-Routing.md).

Workspace chats may use **Metra** (ops/dev partner); see [AGENTS.md](AGENTS.md), [docs/Customizing-Metra.md](docs/Customizing-Metra.md), and `.cursor/rules/metra-persona.mdc`. Code, docs, and ticket text stay professional.

```powershell
.\meta.ps1 audit
.\meta.ps1 audit -DriftOnly
.\meta.ps1 snapshot
.\meta.ps1 chats -Name Solarwinds -Query "disk alert"
```

## Contributing

Issues and PRs welcome on the public repo. Keep machine-local files out of commits (see [SECURITY.md](SECURITY.md)). Prefer small, focused changes to routing, CLI, or docs. Persona growth for one operator belongs in the local overlay; promote to the base rule only when the change is meant for everyone using a fork.

## Notes

- Nested git repos stay independent; this meta repo only tracks its own scripts/config.
- `_meta` is excluded from discovery via `meta.config.json`.
- Pin folders you always want in the workspace with `workspace.alwaysInclude` in your local config.
