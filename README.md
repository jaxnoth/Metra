# Metra

Portfolio ops for multi-root Cursor workspaces. Discover sibling projects, run commands across them, route AI agents to **one project at a time**, and ship **Metra** - a chat persona that stays an ops partner (with Teaching Mode for Ask/Plan and setup).

Not a monorepo build system. Not another "meta" multi-repo clone framework.

MIT licensed. Host on public GitHub (repo name **Metra**) or a private org fork.

## What Metra is / is not

**Is:** a portfolio orchestration layer (CLI + routing registry + Cursor rules + optional persona overlay).

**Not:**

- a monorepo build system (Nx / Turborepo / etc.)
- a project generator beyond lightweight `new` templates
- a ticketing platform (optional TicketTracker stub only)
- an MCP framework (CLI-first; `ctx` packs are files you can open or `@`)

## Naming

| Layer | Name |
|-------|------|
| Product / GitHub repo | **Metra** |
| Recommended local folder | **`_meta`** (also accepted: `Metra`, `metra`) |
| CLI | `meta.ps1` |

```powershell
git clone https://github.com/<you>/Metra.git _meta
cd _meta
```

## Quick start

```powershell
cd C:\Projects   # or your work root
git clone <this-repo-url> _meta
cd _meta
.\meta.ps1 import-profile -Path .\profiles\sample -Force
# Edit meta.config.json roots / workspace.alwaysInclude
# Edit .cursor\rules\metra-persona.local.mdc operator display name (replace Alex)
.\meta.ps1 workspace
.\meta.ps1 routing
.\meta.ps1 ctx
```

Open `Metra.code-workspace` (or `Meta.code-workspace` if your live config still uses that name) in Cursor. Optional stubs in `projects.json` (TicketTracker, Solarwinds) teach routing; they are **not** required installs - `whenMissing` advice appears if those folders are absent.

Preview a pack without writing:

```powershell
.\meta.ps1 import-profile -Path .\profiles\sample -Preview
```

## Teaching Mode

In Cursor **Ask** or **Plan**, and during setup/onboarding, Metra leans into a slightly humorous professional college-professor delivery: answer first, one next step, link docs instead of pasting them, stop when you can execute. Same persona as ops Metra - not a second character. Depth and pacing adapt to the conversation; Metra does not infer demographics or personal traits. Details: [docs/Customizing-Metra.md](docs/Customizing-Metra.md).

## What ships vs stays local

| Ship in git | Keep local / export via profile |
|-------------|-------------------------------|
| CLI, module, templates, shared/ | `meta.config.json` |
| `projects.json` (example stubs) | `projects.local.json` |
| `metra-persona.mdc` (full base) | `.cursor/rules/metra-persona.local.mdc` |
| `*.example.json` / `*.local.example.mdc` | `docs/canvas-snapshot.json`, `docs/context-pack.*` |
| `profiles/sample/` (ready-to-import pack) | regenerated workspaces |
| MIT LICENSE, public docs | |

Bindings (paths, alwaysInclude, operator name) are local facts. Canonical routing stubs and the Metra base rule are shared.

Move yourself between machines:

```powershell
.\meta.ps1 export-profile -Path $env:TEMP\my-meta-profile.zip
# on the other machine, after clone:
.\meta.ps1 import-profile -Path $env:TEMP\my-meta-profile.zip -Force
```

Personal-root `registryFile` is **not** auto-included - copy it with that root. See [docs/Customizing-Metra.md](docs/Customizing-Metra.md), [SECURITY.md](SECURITY.md).

## Versioning

| Surface | Stability |
|---------|-----------|
| CLI commands (`list`, `routing`, `ctx`, profile import/export, ...) | Intended stable |
| Persona rules (`.cursor/rules/metra-persona.mdc`) | Expected to evolve |
| Sample overlays / `profiles/sample/` | Examples, not contracts |

## Commands

| Command | Purpose |
|---------|---------|
| `list` | Show project folders (optional `-GitOnly`, `-Filter`, `-Root`) |
| `roots` | Show configured project roots and whether each exists |
| `routing` | Show merged registry entries vs disk (`-SharedOnly`, `-MissingOnly`) |
| `ctx` | Bounded agent context pack (markdown/json; optional `-Query`) |
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

- `-Filter 'Acme*'` - wildcard on folder name
- `-Name A,B` - exact project names
- `-Root work,personal` - limit to configured roots
- `-GitOnly` - only folders that already have `.git`
- `-ContinueOnError` - keep going if one project fails (`run`)

## Layout

```
_meta/
  meta.ps1                   Metra CLI entrypoint
  meta.config.example.json   starter config (live meta.config.json is gitignored)
  projects.json              shared agent routing registry (example stubs OK)
  projects.local.example.json
  profiles/sample/           anonymized operator pack
  AGENTS.md                  agent entry + Metra examples
  LICENSE                    MIT
  SECURITY.md
  scripts/Meta.psm1          PowerShell helpers
  docs/                      routing + Metra customization
  templates/basic/           default new-project template
  shared/                    files to push into other projects via apply
  .cursor/rules/             routing + Metra base (+ local overlay gitignored)
```

## First-time layout

```text
C:\Projects\                 (work root)
  _meta\                     <- clone of Metra
  Reporting\
  TicketTracker\             (optional; stub in projects.json)
  ...

%USERPROFILE%\iCloudDrive\Projects\   (optional personal root)
  MyPersonalApp\
  projects.personal.json     <- travels with the personal root
```

### Shared vs local vs overlay

| Layer | Role |
|-------|------|
| `projects.json` | Shared routing stubs (public teaching examples) |
| `projects.local.json` | Machine-private work routing (gitignored) |
| Root `registryFile` | Travels with that root (e.g. personal cloud folder) |
| `metra-persona.mdc` | Full base Metra personality (tracked) |
| `metra-persona.local.mdc` | Operator name / greeting / team notes (gitignored) |

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

Classify work, consult `.\meta.ps1 routing` or `.\meta.ps1 ctx`, load one project `AGENTS.md` before scanning siblings. Ticket work starts in TicketTracker when present. Keep work and personal roots isolated unless the user names a cross-root project. Details: [docs/Context-Routing.md](docs/Context-Routing.md).

```powershell
.\meta.ps1 audit
.\meta.ps1 audit -DriftOnly
.\meta.ps1 ctx -Query "disk alert"
.\meta.ps1 chats -Name Solarwinds -Query "disk alert"
```

## Contributing

Issues and PRs welcome. Keep machine-local files out of commits (see [SECURITY.md](SECURITY.md)). Prefer small, focused changes to routing, CLI, or docs. Persona growth for one operator belongs in the local overlay; promote to the base rule only when the change is meant for everyone using a fork.

## Notes

- Nested git repos stay independent; this repo only tracks its own scripts/config.
- The orchestration folder (`_meta` / `Metra` / `metra`) is excluded from project discovery.
- Pin folders you always want in the workspace with `workspace.alwaysInclude` in your local config.
