# P1: API Readiness (Agent Plugin)

Metra **A15** standards pilot - prospect **P1**. Portable [Agent Plugins](https://agent-plugins.org) bundle: agent-readiness knowledge + scan workflow + optional Postman MCP.

Thin IWU-local wrapper focused on **API documentation and testing**, not headless pass-through automation. Optional marketplace **postman** plugin adds `/postman:test`, `/postman:docs`, and more commands.

## Team intent (IWU)

| Use | Supported here |
|-----|----------------|
| Scan API doc sites and bootstrap Postman (spec + collection + environment) | `postman-setup-from-docs` skill + minimal MCP |
| Score OpenAPI for agent/human doc quality | `api-readiness-scan` |
| Run collection tests after setup | Postman MCP `runCollection` or marketplace `/postman:test` |
| Full lifecycle (mocks, monitors, flows, 100+ tools) | Not default - use marketplace postman + `/mcp` only if needed |

## Contains

| Component | Path |
|-----------|------|
| Manifest | `plugin.json` |
| Postman MCP | `mcp.json` (minimal toolset, remote hosted server) |
| Doc site to Postman setup | `skills/postman-setup-from-docs/` |
| Knowledge skill | `skills/agent-ready-apis/` |
| Scan workflow | `skills/api-readiness-scan/` |
| Smoke fixture | `examples/sample-openapi.yaml` |

## Prerequisites

- Cursor 2.5+ with Agent Plugins support
- [Postman API key](https://postman.postman.co/settings/me/api-keys) in **User** environment as `POSTMAN_API_KEY` (for MCP; local-file scan works without it)

PowerShell (User scope):

```powershell
[Environment]::SetEnvironmentVariable('POSTMAN_API_KEY', 'PMAK-...', 'User')
```

Restart Cursor after setting the key.

## Install locally

```powershell
cd C:\Projects\_meta\plugins\api-readiness-postman
.\scripts\Install-LocalPlugin.ps1
```

Reload the window (**Developer: Reload Window**). Open **Customize** and confirm:

- Skills: `agent-ready-apis`, `api-readiness-scan`, `postman-setup-from-docs`
- MCP: `postman` server (enable if off)

## Smoke tests

**Readiness (no MCP):**

`Scan examples/sample-openapi.yaml for agent readiness using the api-readiness-scan skill.`

Pass: scored report with critical gaps called out.

**Postman bootstrap (MCP + key):**

`Set up Postman from this API docs: <public OpenAPI or Swagger UI URL>. Use workspace <name>. Confirm before writes.`

Pass: spec/collection/environment created or a clear fail-closed reason (no spec found, auth wall, etc.).

## MCP notes

- Default URL: `https://mcp.postman.com/minimal` (keeps tool count low for Cursor).
- Auth: `Authorization: Bearer ${POSTMAN_API_KEY}` - Cursor expands from your environment.
- EU accounts: change host to `https://mcp.eu.postman.com/minimal` in `mcp.json`.
- For full Postman tools, switch URL path to `/mcp` or install the marketplace postman plugin.

Do **not** commit API keys. Tracked `mcp.json` uses env placeholder only.

## Hard offs

- No Metra routing, registry, persona, or inspect policy
- No iSupport ticket writes
- No team Required install until this local gate passes

## License / attribution

- Plugin scaffold: IWU Metra pilot (tracked in `_meta`)
- Pillar reference text: adapted from Postman Cursor plugin `agent-ready-apis` (Apache-2.0)
