# Customizing Metra

Metra is the chat persona for `_meta` portfolio ops. Routing and root isolation always win; durable artifacts (code, tickets, commits) stay professional.

## Base vs overlay

| Layer | Path | Tracked? |
|-------|------|----------|
| Base personality | `.cursor/rules/metra-persona.mdc` | Yes |
| Operator overlay | `.cursor/rules/metra-persona.local.mdc` | No (gitignored) |
| Example overlay | `.cursor/rules/metra-persona.local.example.mdc` | Yes |
| Sample pack overlay | `profiles/sample/.cursor/rules/metra-persona.local.mdc` | Yes (anonymized) |

The base ships Humor Policy, Big Five-style temperament, decision tree, output channels, edge cases, and **time-aware personable openings** (first reply of a chat / after a clear break; never on incident; not every turn). Primary audience language is **the operator**; the overlay sets the display name.

Cursor loads both base and local overlay when the local file is present. Grow name, greeting style, and team redistribution reminders in the overlay. Promote portfolio-wide behavior into the base only when forking for a team.

## Sample pack vs your own export

**Newcomers:** import the tracked sample pack:

```powershell
.\meta.ps1 import-profile -Path .\profiles\sample -Force
# Replace Alex in .cursor\rules\metra-persona.local.mdc
# Fix roots in meta.config.json
```

**Moving yourself between machines:** export your live customizations, then import on the other clone:

```powershell
.\meta.ps1 export-profile -Path $env:TEMP\my-meta-profile.zip
.\meta.ps1 import-profile -Path $env:TEMP\my-meta-profile.zip -Force
```

Pack layout (same as `profiles/sample/`):

- `meta-profile.json` - manifest
- `meta.config.json` - if present
- `projects.local.json` - if present
- `.cursor/rules/metra-persona.local.mdc` - if present

`-Preview` lists what would copy. Without `-Force`, import refuses to overwrite existing local files.

## What belongs where

| Put in overlay | Promote to base (fork) |
|----------------|------------------------|
| Operator display name | Shared Humor / opening policy changes for all users |
| Preferred greeting style | Decision-tree / routing voice that every clone should share |
| Team redistribution reminders | Channel table changes for the fork audience |
| Personal-root warmth notes | Anything that must work with no local overlay |

Single-file reference without a full pack: copy `metra-persona.local.example.mdc` to `metra-persona.local.mdc`.

## Personal-root registryFile

Profile packs do **not** include a personal root's `registryFile` (for example `projects.personal.json` beside iCloud projects). That file lives with the personal root. After import:

1. Point the personal root in `meta.config.json` at the synced folder.
2. Ensure `registryFile` exists beside those projects (or copy it from the other machine with that folder).

## Related docs

- [AGENTS.md](../AGENTS.md) - Metra examples and maintainer notes
- [Routing-Scenarios.md](Routing-Scenarios.md) - persona smoke table
- [SECURITY.md](../SECURITY.md) - what not to commit
- [Context-Routing.md](Context-Routing.md) - registry and audit cadence
