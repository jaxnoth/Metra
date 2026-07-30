# Metra communications agent

Portable adapter for Metra's **communications** surface across devices and harnesses.

## What this is

| File | Role |
|------|------|
| [AGENT.md](AGENT.md) | Compact Metra voice + routing priorities + cross-device continuity |
| This README | How to load the agent on phone, desktop, or another coding harness |

This pack does **not** fork a second personality. Cursor still auto-loads `.cursor/rules/metra-persona.mdc` when present. Use `AGENT.md` when that auto-load is missing (mobile cloud agent paste, Claude Code / Codex attach, coworker demo laptop).

## Quick use

**In this checkout (any agent that reads project files):**

- Open or `@` `integrations/communications-agent/AGENT.md`
- Optionally attach a fresh context pack: `.\metra.ps1 ctx -IncludeAgent`

**Paste-only (no workspace rules):**

1. Copy `AGENT.md`
2. Run `.\metra.ps1 ctx -IncludeAgent` (or `Export-MetraContext -IncludeAgent`) and attach the pack
3. Continue the task

**Between machines (bindings + voice overlay):**

```powershell
.\metra.ps1 export-profile -Path $env:TEMP\my-metra-profile.zip
# On the other machine, after clone:
.\metra.ps1 setup -Profile $env:TEMP\my-metra-profile.zip -Force
```

Operator guide: [docs/Cross-Device.md](../../docs/Cross-Device.md).

## Guardrails

- Routing and root isolation still win over tone.
- Durable artifacts stay professional (no Metra chrome in tickets/commits).
- Do not maintain a parallel persona bible here - keep `AGENT.md` lean; promote shared policy to `.cursor/rules/metra-persona.mdc`.

## Related

- [docs/Integrations.md](../../docs/Integrations.md) - Cursor vs CLI vs future adapters
- [docs/Customizing-Metra.md](../../docs/Customizing-Metra.md) - Origin, overlays, Persona Add-ons
- [AGENTS.md](../../AGENTS.md) - short agent entry with examples
)
