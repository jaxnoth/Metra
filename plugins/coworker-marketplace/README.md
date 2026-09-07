# IWU Coworker marketplace pack

Standalone Cursor Team Marketplace pack for IWU coworker dry-runs (desk + tickets + Codex).

**Does not replace** Metra `.\metra.ps1 routing`, persona, inspect, or ticket write gates.

Import this repository into the Cursor team marketplace (e.g. **IWU SDT Market**). The GitHub repo **root must be this folder** so `.cursor-plugin/marketplace.json` is at the repo root.

## Plugins (v1)

| Plugin | Purpose | Install mode |
|--------|---------|--------------|
| `coworker-desk` | Onboarding + companion honesty | Default Off |
| `tickets` | TicketTracker procedures | Default Off |
| `codex` | KB search / cite | Default Off |

Planned later (same pack, separate plugins): M365, Colleague, EllucianWebService, IWUDATA-SQL, Reporting, Solarwinds.

## Publish to IWU SDT Market

1. Create a GitHub repo (prefer **private**, team-readable).
2. Push **this folder as the repo root** (not the parent Metra tree).
3. Run security check:

```powershell
.\scripts\Assert-PublishSafe.ps1
```

4. In Cursor Dashboard → team marketplace (**IWU SDT Market**) → set **Plugin Repository** to that GitHub URL → **Refresh**.
5. Keep plugins **Default Off** until coworker dry-run 2. Do not Required yet.
6. Coworkers: Customize → install `coworker-desk`, `tickets`, `codex` as needed.

See [SECURITY.md](SECURITY.md).

### Push from Metra checkout (maintainer)

While this pack still lives under Metra `plugins/coworker-marketplace/`, publish by pushing only this subtree as its own remote, for example:

```powershell
cd <path-to-this-folder>
git init
git add .
.\scripts\Assert-PublishSafe.ps1
git commit -m "Initial IWU coworker marketplace pack"
git remote add origin <github-repo-url>
git push -u origin main
```

Or use a sparse/subtree publish workflow from Metra if you prefer one parent repo.

## Local install (dev smoke)

```powershell
.\scripts\Install-LocalMarketplace.ps1 -Force
```

Then **Developer: Reload Window**. Verify under Customize → Plugins / Skills.

Refresh `tickets` from TicketTracker source of truth (maintainer machine with a TT checkout):

```powershell
.\scripts\Sync-TicketsSkill.ps1 -TicketTrackerRoot <TicketTracker checkout>
# or: $env:TICKETTRACKER_ROOT = '<TicketTracker checkout>'
.\scripts\Assert-PublishSafe.ps1
```

## Naming

- Pack slug (`marketplace.json` `name`): `IWU-coworker`
- Pack display name: `IWU Coworker`
- Cursor **team marketplace** name (Dashboard): whatever you created (e.g. IWU SDT Market) - that is separate from the pack slug
- Plugin ids stay lowercase kebab-case; `displayName` carries the IWU prefix

Icons and title casing in the Cursor UI may not honor `logo` / `displayName` yet; skills still install.

## Hard offs

- No secrets in tracked files
- No auto iSupport writes from skills
- One mega portfolio plugin is out of scope - use satellites
