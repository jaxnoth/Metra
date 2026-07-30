# Metra

Portfolio ops for multi-root project folders. Discover siblings, run commands across them, route AI agents to **one project at a time**, and ship **Metra** - an ops-partner chat persona (Teaching Mode for exploring, planning, and setup).

Not a monorepo build system. Not another "meta" multi-repo clone framework.

MIT licensed. Public repo: [jaxnoth/Metra](https://github.com/jaxnoth/Metra).

**Requirements:** PowerShell. Cursor is optional for full persona auto-load - see [docs/Integrations.md](docs/Integrations.md).

## 90-second understanding

If you only read three things:

1. **Metra manages multi-project workspaces** - siblings under one or more roots, operated with `meta.ps1`.
2. **Routing picks one project before work starts** - personality never chooses the folder.
3. **`ctx` creates agent handoff packs** - bounded maps you can open, paste, or `@` in any coding agent.

## Why Metra?

Most portfolio mistakes happen before coding starts: the wrong repository, the wrong root, the wrong ticket, the wrong assumptions. Metra routes first, gathers just enough context, then works. The chat persona is a constrained ops partner for that workflow - not the product itself. Longer operating philosophy: [docs/Customizing-Metra.md](docs/Customizing-Metra.md) (Origin).

## What Metra is / is not

**Is:** a portfolio orchestration layer (CLI + routing registry + agent guidance + optional persona overlay).

**Not:**

- a monorepo build system (Nx / Turborepo / etc.)
- a project generator beyond lightweight `new` templates
- a ticketing platform (optional TicketTracker stub only)
- an MCP framework (CLI-first; `ctx` packs are files you can open, paste, or `@`)
- a Cursor-only plugin (CLI and registries work without Cursor)

## Core vs Cursor

| Layer | What you get |
|-------|----------------|
| **Core** (any shell; any agent that can read files) | `meta.ps1`, `projects.json` / local registries, `ctx` packs, profile import/export, this `AGENTS.md`, per-project `AGENTS.md` |
| **Cursor integration** (first-class adapter) | `.cursor/rules` persona auto-load, Ask/Plan Teaching Mode, `chats` transcript search, optional multi-root `.code-workspace`, `sessionStart` Ops refresh (`.cursor/hooks`) |

## Naming

| Layer | Name |
|-------|------|
| Product / GitHub repo | **Metra** |
| Recommended local folder | **`_meta`** (also accepted: `Metra`, `metra`) |
| CLI | `meta.ps1` |
| Workspace file | `Metra.code-workspace` (legacy `Meta.code-workspace` still honored if configured) |

Operator-facing brand kit (palette, motif, professional sink): [docs/Brand.md](docs/Brand.md). Coworker walkthrough (concepts + live, including a non-AI-friendly path): [docs/Demo-5min.md](docs/Demo-5min.md).

## Quick start (CLI first)

```powershell
cd C:\Projects   # or your work root
git clone https://github.com/jaxnoth/Metra.git _meta
cd _meta
.\meta.ps1 import-profile -Path .\profiles\sample -Force
# Edit meta.config.json roots / workspace.alwaysInclude
# Edit .cursor\rules\metra-persona.local.mdc operator display name (replace Alex) if using Cursor
.\meta.ps1 routing
.\meta.ps1 ctx
```

Hand the context pack to any agent: open/attach/paste/`@` `docs/context-pack.md` (or JSON). Optional stubs in `projects.json` (TicketTracker, Solarwinds) teach routing; they are **not** required installs - `whenMissing` advice appears if those folders are absent.

Preview a pack without writing:

```powershell
.\meta.ps1 import-profile -Path .\profiles\sample -Preview
```

### Optional: open in Cursor

```powershell
.\meta.ps1 workspace
```

Open `Metra.code-workspace` (or `Meta.code-workspace` if your live config still uses that name). Workspace generation helps VS Code/Cursor multi-root; it is **not** required for CLI, routing, or `ctx`.

## Teaching Mode

When exploring, planning, or onboarding (Cursor Ask/Plan are common cases), Metra leans into a slightly humorous professional college-professor delivery: answer first, one next step, link docs instead of pasting them, stop when you can execute. Guide the work, teach Metra vocabulary when needed, and recommend concrete options when you are stuck. After an ambiguous ask, Metra may offer one **Request Shaping** example of a more routeable future request - not prompt grades or unsolicited critique. Same persona as ops Metra - not a second character. Depth and pacing adapt to the conversation; Metra does not infer demographics or personal traits. Details: [docs/Customizing-Metra.md](docs/Customizing-Metra.md).

## Context pack (universal handoff)

```powershell
.\meta.ps1 ctx
.\meta.ps1 ctx -Query "ticket disk"
.\meta.ps1 ctx -Format json -Path $env:TEMP\metra-ctx.json
```

Writes a bounded map of roots and present projects. Use it from Cursor, Claude Code, Codex, or any chat that accepts a file or paste. See [docs/Integrations.md](docs/Integrations.md).

## What ships vs stays local

| Ship in git | Keep local / export via profile |
|-------------|-------------------------------|
| CLI, module, templates, shared/ | `meta.config.json` |
| `projects.json` (example stubs) | `projects.local.json` |
| `metra-persona.mdc` (full base) | `.cursor/rules/metra-persona.local.mdc` |
| `*.example.json` / `*.local.example.mdc` | `docs/canvas-snapshot.json`, `docs/context-pack.*` |
| `profiles/sample/` (ready-to-import pack) | regenerated workspaces |
| `.cursor/hooks/` (sessionStart Ops refresh) | |
| MIT LICENSE, public docs (Brand, Decisions, Integrations, ...) | |

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
| `workspace` | Rebuild multi-root workspace from recent activity (optional IDE helper) |
| `audit` | Context/token audit + optional `-DriftOnly` vs registries |
| `snapshot` | Write `docs/canvas-snapshot.json` and refresh / install Metra Ops canvas embed (`-Quick` skips deep audit/git) |
| `chats` | Search local Cursor agent transcripts (bounded; Cursor-specific) |
| `export-profile` | Pack local config / local registry / Metra overlay |
| `import-profile` | Restore a pack (`-Preview` or `-Force`) |
| `verify` | Routing-Scenarios fixture smoke (`PASS`/`WARN`/`FAIL`; exit 1 on FAIL) |

Focused Pester (optional; Pester 5+, PowerShell 7):

```powershell
pwsh -NoProfile -File .\tests\Invoke-MetaTests.ps1
```

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
  docs/                      Brand, Decisions, routing, Integrations, Demo, ...
  integrations/cursor/       Metra Ops canvas template
  templates/basic/           default new-project template
  shared/                    files to push into other projects via apply
  .cursor/rules/             Cursor adapter: routing + Metra base (+ local overlay gitignored)
  .cursor/hooks/             sessionStart stale-gated snapshot -Quick (no workspace rewrite)
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
| `metra-persona.mdc` | Full base Metra personality (tracked; Cursor auto-loads) |
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

Classify work, consult `.\meta.ps1 routing` or `.\meta.ps1 ctx`, load one project `AGENTS.md` before scanning siblings. Ticket work starts in TicketTracker when present. Keep work and personal roots isolated unless the user names a cross-root project. Prefer [docs/Decisions.md](docs/Decisions.md) for durable Metra policy before digging chats. Smoke fixtures: `.\meta.ps1 verify`. Details: [docs/Context-Routing.md](docs/Context-Routing.md), [docs/Integrations.md](docs/Integrations.md).

```powershell
.\meta.ps1 audit
.\meta.ps1 audit -DriftOnly
.\meta.ps1 verify
.\meta.ps1 ctx -Query "disk alert"
.\meta.ps1 chats -Name Solarwinds -Query "disk alert"
```

## Contributing

Issues and PRs welcome. Keep machine-local files out of commits (see [SECURITY.md](SECURITY.md)). Prefer small, focused changes to routing, CLI, or docs. Persona growth for one operator belongs in the local overlay; promote to the base rule only when the change is meant for everyone using a fork.

## Notes

- Nested git repos stay independent; this repo only tracks its own scripts/config.
- The orchestration folder (`_meta` / `Metra` / `metra`) is excluded from project discovery.
- Pin folders you always want in the workspace with `workspace.alwaysInclude` in your local config.
