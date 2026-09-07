# Metra Agent Plugins

Portable plugins for local Cursor testing and Team Marketplace packs. Metra routing, persona, inspect policy, and ticket writes stay in `_meta` - plugins add skills (and MCP only when needed).

## Packs

| Path | Status |
|------|--------|
| [coworker-marketplace/](coworker-marketplace/) | **v1 scaffold** - desk + tickets + Codex; Team Marketplace manifest |
| [api-readiness-postman/](api-readiness-postman/) | P1 readiness scan + Postman MCP (Agent Plugins single plugin) |

## Coworker marketplace (preferred for dry-runs)

```powershell
cd C:\Projects\_meta\plugins\coworker-marketplace
.\scripts\Install-LocalMarketplace.ps1 -Force
.\scripts\Sync-TicketsSkill.ps1
```

Then **Developer: Reload Window**. Team import: publish **`coworker-marketplace/` as its own GitHub repo root** (see that folder's README + SECURITY.md), point **IWU SDT Market** (or similar) at that repo, Refresh. Run `.\scripts\Assert-PublishSafe.ps1` before push.

## Hard offs (all plugins)

- No Metra routing or registry as plugin authority
- No auto iSupport `post` / `recommend` / `resolve`
- No secrets in tracked files
- Team **Required** only after coworker dry-run 2
- One mega portfolio plugin is out of scope - use satellites (tickets, codex, later m365 / solarwinds / …)
