# Metra Agent Plugins (standards pilot)

Portable [Agent Plugins](https://agent-plugins.org) bundles for local Cursor testing. Metra routing, persona, inspect policy, and ticket writes stay in `_meta` - these plugins add skills and MCP only.

## Layout

| Path | Id | Status |
|------|----|--------|
| [api-readiness-postman/](api-readiness-postman/) | P1 | Readiness scan + doc-site to Postman setup (minimal MCP) |

## Install (local)

From the plugin folder:

```powershell
cd C:\Projects\_meta\plugins\api-readiness-postman
.\scripts\Install-LocalPlugin.ps1
```

Then **Developer: Reload Window** in Cursor. Verify under **Customize** (skills + Postman MCP).

## Hard offs (all plugins)

- No Metra routing or registry in a plugin
- No iSupport `post` / `recommend` / `resolve`
- No secrets in tracked files (operator sets `POSTMAN_API_KEY` locally)
- Team marketplace / Required install only after a local smoke pass

See [Future-Development.local.md](../docs/Future-Development.local.md) (**A15**, prospect **P1**).
