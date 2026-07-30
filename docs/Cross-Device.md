# Cross-device Metra

How to keep Metra's **communications** voice and ops map consistent when work moves between phone, laptop, and desktop.

## What travels

| Asset | Travels how | Holds |
|-------|-------------|--------|
| Base Metra voice | Git (`AGENTS.md`, `.cursor/rules/metra-persona.mdc`, `integrations/communications-agent/AGENT.md`) | Shared product voice |
| Operator overlay / add-ons | `export-profile` / `import-profile` | Display name, greeting, optional tone dials |
| Roots + local registry | Same profile pack | Machine bindings |
| Bounded project map | `.\metra.ps1 ctx` (optionally `-IncludeAgent`) | Present projects + reminders |
| In-flight work | Same git branch / PR, TicketTracker notes | Durable progress - not invented chat memory |

Chat transcripts are device-local unless you promote clues into notes, commits, or the PR.

## Phone (Cursor Cloud / mobile) -> desktop

Typical path when a Cloud Agent starts on a phone:

1. Agent works in the Metra checkout (or a routed sibling) and opens a PR on a feature branch.
2. On the desktop, pull that branch / open the PR and continue in Cursor.
3. If the desktop session does not auto-load `.cursor/rules`, attach `integrations/communications-agent/AGENT.md` once.
4. Refresh the ops map when the portfolio changed: `.\metra.ps1 ctx -IncludeAgent`.

Do not expect the desktop agent to "remember" the phone chat. Prefer the PR description, commits, and any TicketTracker notes.

## Desktop -> another machine

```powershell
.\metra.ps1 export-profile -Path $env:TEMP\my-metra-profile.zip
# On the other machine:
cd C:\Projects\_metra   # or your checkout
.\metra.ps1 setup -Profile $env:TEMP\my-metra-profile.zip -Force
```

Then open `docs/context-pack.md` or run `.\metra.ps1 ctx -IncludeAgent` for the current map.

## Any harness (Claude Code, Codex, paste)

1. Keep CLI + registries + `ctx` + `AGENTS.md` as routing truth.
2. Attach `integrations/communications-agent/AGENT.md` for Metra voice when the harness does not load `.cursor/rules`.
3. Attach or paste the context pack from `.\metra.ps1 ctx -IncludeAgent`.
4. Do not invent a second Metra personality per tool.

## Commands

```powershell
.\metra.ps1 ctx
.\metra.ps1 ctx -IncludeAgent
.\metra.ps1 ctx -Query "ticket disk" -IncludeAgent
.\metra.ps1 export-profile -Path $env:TEMP\my-metra-profile.zip
.\metra.ps1 import-profile -Path $env:TEMP\my-metra-profile.zip -Preview
```

PowerShell module equivalent: `Export-MetraContext -IncludeAgent`.

## Related

- [integrations/communications-agent/README.md](../integrations/communications-agent/README.md) - portable agent pack
- [Integrations.md](Integrations.md) - Cursor adapter vs CLI
- [Customizing-Metra.md](Customizing-Metra.md) - profiles and overlays
- [Decisions.md](Decisions.md) - portfolio policy record
)
