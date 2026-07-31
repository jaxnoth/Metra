# Metra

**Portfolio operations for humans and coding agents. Route work, load context, preserve decisions, and communicate consistently.**

Desk partner for multi-root portfolios: land in the right project, load bounded context, keep operational why inspectable, and keep chat useful while tickets and commits stay flat.

Discover sibling projects, run commands across them with PowerShell (`metra.ps1` / importable module), route work to **one project at a time**, and generate context packs for Cursor, Claude Code, Codex, or other coding agents. The **Metra** persona is that desk partner in chat - route-first, Teaching Mode when exploring, and a professional sink so tickets, commits, ADRs, and handoffs stay flat.

Not a monorepo build system. Not another "meta" multi-repo clone framework.

MIT licensed. Public repo: [jaxnoth/Metra](https://github.com/jaxnoth/Metra).

**Requirements:** PowerShell. Cursor is optional for full persona auto-load - see [docs/Integrations.md](docs/Integrations.md).

## 90-second understanding

If you only read four things:

1. **Routing + context + communication** - the product triangle. PowerShell tooling manages the portfolio; the Metra persona manages the conversation around that work.
2. **Routing picks one project before work starts** - personality never chooses the folder; the registry does.
3. **`ctx` creates agent handoff packs** - bounded maps you can open, paste, or `@` in any coding agent.
4. **Professional sink** - chat may sound like Metra; tickets, commits, ADRs, and coworker handoffs do not.

## Why Metra?

Most portfolio mistakes happen before coding starts:

- the wrong repository
- the wrong root
- the wrong ticket
- the wrong assumption

Most AI workflow problems happen after routing fails:

- agents wander across projects
- conversations lose context
- ticket history gets ignored
- artifacts drift from the discussion

Metra was designed to address both.

**Routing** defines where work happens. **Context** defines what evidence is loaded. **Communication** defines how work is discussed once it gets there - including the professional sink that keeps durable writes flat.

### Portfolio operations homes

Every portfolio fact should have a home. The product triangle is the pitch; this table is the operator cheat sheet:

| Question | Home |
|----------|------|
| Where? | Routing registry / `routing` |
| What? | Context / `ctx`, project `AGENTS.md` |
| Why? (operational) | Decision Registry + Why Here |
| Why? (product policy) | [docs/Decisions.md](docs/Decisions.md) |
| How? | OCC / `profile` + communication model |
| Health? | Ops board / `audit` / `verify` |

Prefer retrieval over dumping: route, then load only relevant context and decisions. Principles: [docs/Decisions.md](docs/Decisions.md) (Portfolio Operations Principles).

PowerShell tooling is how you operate the portfolio. The Metra persona is how you stay aligned in agent chat. Neither is a bolt-on. Longer operating philosophy: [docs/Customizing-Metra.md](docs/Customizing-Metra.md) (Origin).

## Why not just use a coding agent?

Coding agents can write code.

Metra helps decide:

- which project owns the request
- what context should be loaded
- which evidence matters
- how discussion and artifacts stay aligned

Metra is not another coding agent. It is a routing, context, and communication layer that works **across** them.

## What Metra is / is not

**Is:** a portfolio operations system - PowerShell CLI/module + routing registry + `ctx` packs + a Metra communication model (persona, Teaching Mode, professional sink).

**Not:**

- a monorepo build system (Nx / Turborepo / etc.)
- a project generator beyond lightweight `new` templates
- a ticketing platform (optional TicketTracker stub only)
- an MCP framework (CLI-first; `ctx` packs are files you can open, paste, or `@`)
- a Cursor-only plugin (CLI and registries work without Cursor; persona auto-load is the Cursor adapter)
- another coding agent (it routes and disciplines work *for* agents)

## Operating model and adapters

| Layer | What you get |
|-------|----------------|
| **Routing + context (ops)** | `metra.ps1`, importable `scripts/Metra.psd1` (17 public commands + Get-Help), `projects.json` / local registries, `ctx` packs, profile import/export |
| **Communication model** | Base Metra persona (`metra-persona.mdc` / this `AGENTS.md`), Teaching Mode, professional sink, per-project `AGENTS.md` |
| **Cursor adapter** (nicest full load) | `.cursor/rules` auto-load, Ask/Plan Teaching Mode, `chats` transcript search, optional multi-root `.code-workspace`, `sessionStart` Ops refresh (`.cursor/hooks`) |

CLI-only operators get full routing and context value without Cursor. Agents in other harnesses still pick up the communication model from `AGENTS.md` and `ctx` when those files are in scope.

## Naming

| Layer | Name |
|-------|------|
| Product / GitHub repo | **Metra** |
| Recommended local folder | **`_metra`** (also accepted: `_meta`, `Metra`, `metra`) |
| CLI (routing + context) | `metra.ps1` |
| Communication model | **Metra** persona - base + overlay + optional add-ons + learned contract (`profile`) |
| Workspace file | `Metra.code-workspace` (legacy `Meta.code-workspace` still honored if configured) |

Operator-facing brand kit (palette, motif, professional sink): [docs/Brand.md](docs/Brand.md). Coworker walkthrough (concepts + live, including a non-AI-friendly path): [docs/Demo-5min.md](docs/Demo-5min.md).

## Quick start (CLI first)

```powershell
cd C:\Projects   # or your work root
git clone https://github.com/jaxnoth/Metra.git _metra
cd _metra
# Once per machine (Windows): allow local scripts for your user
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
# Bare clone: seeds metra.config.json from the example, builds workspace, routing, ctx
.\metra.ps1 setup
# Or with a pack (sample or your export zip):
# .\metra.ps1 setup -Profile .\profiles\sample -Force
# Edit metra.config.json roots / alwaysInclude if paths differ, then re-run:
# .\metra.ps1 setup
```

After `setup`, you have a working CLI *and* an agent-ready map: open `docs/context-pack.md`, paste it into a chat, or `@` it in Cursor. Routing stubs in `projects.json` teach agents (and humans) which folder owns which ask. In Cursor (or any harness that loads `AGENTS.md`), the Metra communication model kicks in - route first, then talk like a desk partner.

### What setup did

| Piece | Meaning |
|-------|---------|
| `roots` | Disk locations Metra scans for sibling project folders |
| `workspace` | Rebuilds `Metra.code-workspace` folder list from those roots (recent activity + `alwaysInclude`) |
| `routing` | Named registry projects + triggers vs `Present` on disk (`whenMissing` advice if absent) |
| `ctx` | Writes `docs/context-pack.md` - bounded context for any agent |

Editing `roots` alone does **not** change Cursor folders until `setup` (or `.\metra.ps1 workspace`) runs again. Optional personal/cloud root snippets (iCloud, OneDrive, ...): [docs/Customizing-Metra.md](docs/Customizing-Metra.md).

Shared stubs in `projects.json` (TicketTracker, Solarwinds) teach routing; they are **not** required installs.

Preview without writing:

```powershell
.\metra.ps1 setup -Preview
.\metra.ps1 setup -Profile .\profiles\sample -Preview
```

### PowerShell-native commands

Import the module instead of (or alongside) the script dispatcher:

```powershell
Import-Module .\scripts\Metra.psd1
Get-MetraProject -Root work -GitOnly
Get-MetraRouting -Name TicketTracker
Export-MetraContext -Query "ticket disk"
```

**Supported public surface** (17 commands - treat each addition as an API commitment):

| Area | Commands |
|------|----------|
| Setup / validation | `Initialize-Metra`, `Test-MetraInstallation` |
| Discovery | `Get-MetraProject`, `Get-MetraProjectRoot`, `Get-MetraRouting` |
| Operations | `Get-MetraProjectStatus`, `Update-MetraProject`, `Invoke-MetraProjectCommand`, `Copy-MetraProjectFile`, `New-MetraProject` |
| Workspace | `Update-MetraWorkspace` |
| Context / AI | `Test-MetraProjectContext`, `Export-MetraSnapshot`, `Get-MetraChat`, `Export-MetraContext` |
| Profiles | `Export-MetraProfile`, `Import-MetraProfile` |

**Documentation:** `Get-Help <command> -Full` is the source of truth for parameters, examples, and outputs. This README stays workflow-oriented - do not expect a parallel hand-maintained API markdown file.

Tab completion covers command and parameter names, project and root values, and fixed choices such as `Export-MetraContext -Format`. Add `Import-Module` with an absolute path to `$PROFILE` when the commands should load in every session.

Common `metra.ps1` equivalents:

- `setup` -> `Initialize-Metra`
- `list` / `roots` / `routing` -> `Get-MetraProject` / `Get-MetraProjectRoot` / `Get-MetraRouting`
- `status` / `pull` / `fetch` -> `Get-MetraProjectStatus` / `Update-MetraProject`
- `run` / `apply` -> `Invoke-MetraProjectCommand` / `Copy-MetraProjectFile`
- `audit` / `snapshot` / `chats` -> `Test-MetraProjectContext` / `Export-MetraSnapshot` / `Get-MetraChat`
- `ctx` / `verify` -> `Export-MetraContext` / `Test-MetraInstallation`

`Get-Command -Module Metra` also lists one-release compatibility helpers and former `*-Meta*` aliases. New scripts should use only the 17 commands above. `metra.ps1` remains fully supported.

### Communication model in Cursor

`setup` generates one workspace file, `Metra.code-workspace`, in the Metra checkout. It is gitignored (the tracked starter is `Metra.code-workspace.example`), so your real project names never land in git. Reopen or reload that file after `setup` so sibling projects appear, and keep opening the same file - Cursor tracks chat history per workspace, so a second copy in another folder splits your chat context. Workspace multi-root helps VS Code/Cursor; it is **not** required for CLI, routing, or `ctx`.

In Cursor, Metra's persona auto-loads from `.cursor/rules` - route first, stay in one project, Teaching Mode when exploring, professional sink for anything that leaves chat. Set your display name in `.cursor\rules\metra-persona.local.mdc` after importing a profile. Prefer a different coding agent? Same `routing` / `ctx` / `AGENTS.md` story still applies; follow `AGENTS.md` for Metra voice when your harness loads project guidance.

## Communication model (Metra persona)

Routing gets you to the right folder. Context loads what matters. The communication model is how Metra *talks* once you are there - a workflow capability, not a character feature.

| Piece | Role |
|-------|------|
| Base persona | Route-first ops partner; answer-first; dry desk humor when it helps |
| Teaching Mode | Same Metra when exploring or stuck - answer, one next step, then stop |
| Professional sink | Chat may have voice; tickets, commits, ADRs, and coworker handoffs stay flat |
| Overlay / add-ons / learned | Name + tone dials; Operator Communication Contract (`profile`) for soft working guidelines |

### Teaching Mode

Routine work stays terse ops partner. Teaching Mode kicks in for "how does this work?", first-time setup, planning, or "I'm stuck" - Cursor Ask/Plan are common cases, but intent matters more than the mode name.

Instead of dumping the README:

1. Answer the question first
2. Give **one** next command or edit
3. Link the doc if you want depth - then stop

If a request was too vague to route, Metra may offer one clearer future ask (name the project or trigger) - not a prompt critique. Same desk partner as ops Metra; incidents stay flat. Details: [docs/Customizing-Metra.md](docs/Customizing-Metra.md).

## Context pack (universal handoff)

Bounded context for any agent - the middle of the triangle:

```powershell
.\metra.ps1 ctx
.\metra.ps1 ctx -Query "ticket disk"
.\metra.ps1 ctx -Format json -Path $env:TEMP\metra-ctx.json
```

Writes a map of roots and present projects - enough to pick a stop without dumping the whole portfolio. Pair it with the Metra persona / `AGENTS.md` so chat stays route-first after the pack is loaded. Use it from Cursor, Claude Code, Codex, or any chat that accepts a file or paste. See [docs/Integrations.md](docs/Integrations.md).

## What ships vs stays local

| Ship in git | Keep local / export via profile |
|-------------|-------------------------------|
| CLI, module, templates, shared/ | `metra.config.json` |
| `projects.json` (example stubs) | `projects.local.json` |
| `metra-persona.mdc` (full base) | `.cursor/rules/metra-persona.local.mdc` |
| `profiles/addons/` (opt-in Persona Add-ons) | `.cursor/rules/metra-humor.local.mdc`, `metra-teaching-gentle.local.mdc` (after import) |
| `*.example.json` / `*.local.example.mdc` | `docs/canvas-snapshot.json`, `docs/context-pack.*`, `docs/decision-registry.json`, `docs/operator-contract.json` |
| `profiles/sample/` (ready-to-import pack) | generated `Metra.code-workspace` (after `.\metra.ps1 workspace`) |
| `Metra.code-workspace.example` (Metra-only starter) | |
| `.cursor/hooks/` (sessionStart Ops refresh) | |
| MIT LICENSE, public docs (Brand, Decisions, Integrations, ...) | |

Bindings (paths, alwaysInclude, operator name) are local facts. Canonical routing stubs and the Metra base persona are shared product - routing registry plus communication model.

Move yourself between machines:

```powershell
.\metra.ps1 export-profile -Path $env:TEMP\my-metra-profile.zip
# on the other machine, after clone:
.\metra.ps1 import-profile -Path $env:TEMP\my-metra-profile.zip -Force
```

Personal-root `registryFile` is **not** auto-included - copy it with that root. See [docs/Customizing-Metra.md](docs/Customizing-Metra.md), [SECURITY.md](SECURITY.md).

## Versioning

| Surface | Stability |
|---------|-----------|
| CLI commands (`setup`, `list`, `routing`, `ctx`, profile import/export, ...) | Intended stable (routing + context) |
| Public PowerShell commands (the 17 above) | Intended stable; prefer extending an existing command over adding exports |
| Compatibility functions and former `*-Meta*` aliases | One release; do not use in new scripts |
| Communication model (`.cursor/rules/metra-persona.mdc`, `AGENTS.md` voice) | Product surface; expected to evolve carefully |
| Sample overlays / `profiles/sample/` / `profiles/addons/` | Examples / tone dials, not routing contracts |

## Commands

| Command | Purpose |
|---------|---------|
| `setup` | One-shot onboarding: seed config if missing, optional `-Profile`, roots, workspace, routing, ctx |
| `list` | Show project folders (optional `-GitOnly`, `-Filter`, `-Root`) |
| `roots` | Show configured project roots and whether each exists |
| `routing` | Show merged registry entries vs disk (`-SharedOnly`, `-MissingOnly`); `-Name` / `-Query` attach ledger-backed Why Here (and Why not when query scores are close) |
| `ctx` | Bounded agent context pack (markdown/json; optional `-Query`) |
| `status` | `git status -sb` in each git project |
| `pull` / `fetch` | Fast-forward pull or fetch across git projects |
| `run <cmd>` | Run operator-provided shell text in each matching project (trusted input only; see [SECURITY.md](SECURITY.md)) |
| `new <Name>` | Create a new project under the primary root (or `-Root`) |
| `apply <file>` | Copy a shared file into matching projects |
| `workspace` | Rebuild multi-root workspace from recent activity (optional IDE helper) |
| `audit` | Context/token audit + optional `-DriftOnly` vs registries |
| `snapshot` | Write `docs/canvas-snapshot.json` and refresh / install Metra Ops canvas embed (`-Quick` skips deep audit/git) |
| `chats` | Search local Cursor agent transcripts (bounded) - prior session evidence |
| `export-profile` | Pack local config / local registry / Metra overlay (+ Persona Add-ons / learned contract if present) |
| `import-profile` | Restore a pack (`-Preview` or `-Force`) - ops bindings and persona overlay |
| `profile` | Operator Communication Contract: `show` / `note` / `promote` / `forget` / `render` / `gc` |
| `decisions` | Decision Registry (Operational Why Memory): `show` / `note` / `promote` / `forget` / `search` / `get` / `supersede` / `gc` / `harvest` / `seed` |
| `verify` | Routing-Scenarios fixture smoke (`PASS`/`WARN`/`FAIL`; exit 1 on FAIL) |

Why Here examples (Decision Registry must have confirmed entries for that project):

```powershell
.\metra.ps1 routing                          # full table; no Why Here dump
.\metra.ps1 routing -Name TicketTracker      # named stop + Why here?
.\metra.ps1 routing -Query "gateway msal"    # primary + Why here?; Why not? when scores are close
.\metra.ps1 ctx -Query "ticket disk"         # pack includes ## Why here?
```

Focused Pester (optional; Pester 5+, PowerShell 7):

```powershell
pwsh -NoProfile -File .\tests\Invoke-MetraTests.ps1
```

### Filters

- `-Filter 'Acme*'` - wildcard on folder name
- `-Name A,B` - exact project names
- `-Root work,personal` - limit to configured roots
- `-GitOnly` - only folders that already have `.git`
- `-ContinueOnError` - keep going if one project fails (`run`)

## Layout

```
_metra/
  metra.ps1                   Metra CLI entrypoint (routing + context)
  metra.config.example.json   starter config (live metra.config.json is gitignored)
  projects.json              shared agent routing registry (example stubs OK)
  projects.local.example.json
  profiles/sample/           anonymized operator pack (ops bindings + persona overlay)
  profiles/addons/           optional Persona Add-ons (tone dials; e.g. humor-desk)
  AGENTS.md                  communication model entry + Metra examples (any agent harness)
  LICENSE                    MIT
  SECURITY.md
  scripts/Metra.psd1          PowerShell module manifest and explicit exports
  scripts/Metra.psm1          Thin module loader and compatibility boundary
  scripts/public/             Supported commands with full Get-Help documentation
  scripts/private/            Domain implementation helpers
  docs/                      Brand, Decisions, routing, Integrations, Demo, ...
  integrations/cursor/       Metra Ops canvas template
  templates/basic/           default new-project template
  shared/                    files to push into other projects via apply
  .cursor/rules/             Cursor adapter: routing + Metra base (+ local overlay / add-ons gitignored)
  .cursor/hooks/             sessionStart stale-gated snapshot -Quick (no workspace rewrite)
```

## First-time layout

```text
C:\Projects\                 (work root)
  _metra\                    <- clone of Metra (also accepted: _meta, Metra, metra)
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
| `metra-persona.mdc` | Full base Metra communication model (tracked; Cursor auto-loads) |
| `metra-persona.local.mdc` | Operator name / greeting / team redistribution notes (gitignored) |
| Persona Add-ons | Optional tone dials only - never change routing or the professional sink |

## Creating projects

```powershell
.\metra.ps1 new ReportingOps -Description "Ops scripts for reporting"
.\metra.ps1 new ScratchPad -Template basic -NoGit
.\metra.ps1 new SermonNotes -Root personal
```

## Cross-project adjustments

```powershell
.\metra.ps1 run "git status -sb" -Root work -GitOnly
.\metra.ps1 apply .\shared\.editorconfig -RelativePath .editorconfig
```

## Agent routing

Classify the ask, consult `.\metra.ps1 routing` or `.\metra.ps1 ctx`, load **one** project `AGENTS.md` before scanning siblings. Personality never picks the folder - the registry does. After that, Metra's voice applies in chat (route banner, answer-first, Teaching Mode when exploring); anything that leaves chat uses the professional sink. Ticket work starts in TicketTracker when present. Keep work and personal roots isolated unless the user names a cross-root project. Prefer [docs/Decisions.md](docs/Decisions.md) for durable Metra policy before digging chats. Smoke fixtures: `.\metra.ps1 verify`. Details: [docs/Context-Routing.md](docs/Context-Routing.md), [docs/Integrations.md](docs/Integrations.md).

```powershell
.\metra.ps1 audit
.\metra.ps1 audit -DriftOnly
.\metra.ps1 verify
.\metra.ps1 ctx -Query "disk alert"
.\metra.ps1 chats -Name Solarwinds -Query "disk alert"
```

`chats` searches local Cursor transcripts when you need prior session clues; `ctx` is the portable context handoff for any agent.

## Contributing

Issues and PRs welcome. Keep machine-local files out of commits (see [SECURITY.md](SECURITY.md)). Prefer small, focused changes to routing, CLI, docs, or the communication model. New public module exports need a clear user-facing reason (each is an API commitment) - prefer private helpers or extending an existing command. Persona growth for one operator belongs in the local overlay; promote to the base rule only when the change is meant for everyone using a fork. Durable policy choices: [docs/Decisions.md](docs/Decisions.md).

## Notes

- Nested git repos stay independent; this repo only tracks its own scripts/config.
- The orchestration folder (`_metra` / `_meta` / `Metra` / `metra`) is excluded from project discovery.
- Pin folders you always want in the workspace with `workspace.alwaysInclude` in your local config.
- Chat may sound like Metra; tickets, commits, and coworker handoffs stay in the professional sink.
