---
metraMemory: procedural
defaultContext: false
loadWhen:
  - projects.json
  - registry
  - import-profile
  - personal root
  - profiles
ceiling:
  - projects.json only for shared entries; local overlays gitignored
---

> Moved from `AGENTS.md` during A2 desk split. Preserve A1 done-when / On hard stop content unless intentionally revised.

# Shared vs local registry

See also [docs/Context-Routing.md](../Context-Routing.md) for desk model and ctx behavior.

| File | Role |
|------|------|
| `projects.json` | Shared / public stubs (TicketTracker, Solarwinds examples, etc.) |
| `projects.local.json` | Machine-private work entries (gitignored) |
| Root `registryFile` (e.g. `projects.personal.json`) | Travels with that root |
| `profiles/sample/` | Anonymized pack for `import-profile` |
| `profiles/addons/` | Opt-in Persona Add-ons (e.g. humor-desk; tone only) |

Optional entries may be absent: follow `whenMissing` advice instead of inventing paths.
