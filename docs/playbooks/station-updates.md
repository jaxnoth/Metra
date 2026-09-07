# Station updates

Metra installs and updates **Stations** (capability destinations) under the work root. Metra is the conductor; a Station is where the conversation train stops (TicketTracker, Codex today).

## Operator path (coworker)

1. Install Metra (Ops).
2. Open **Settings → About → Station Updates**.
3. Click **Check for updates** (same button as Metra/Ollama).
4. **Install** *TicketTracker Station* / *Codex Station* when shown, or **Update** when a newer release exists.
5. Optional: enable **Auto-update installed Stations** (default Off). Never overwrites a folder that contains `.git`.

Cursor marketplace skills are optional procedure helpers. They are **not** the ship vehicle for TicketTracker or Codex.

## Identity agreement

Before publish / apply, these must agree (optional leading `v` on the tag):

| Piece | Example |
|-------|---------|
| `station.package.json` `id` + `version` | `tickettracker` / `0.1.0` |
| Zip (+ `.sha256`) | `TicketTracker-0.1.0.zip` |
| GitHub release tag | `v0.1.0` |

Metra discovery refuses zip names that do not end with `-{tagVersion}.zip`. Apply refuses when staged `station.package.json` id/version disagree with the manifest station id or release tag version.

Manifest file names (locked): `config/stations.example.json` / `config/stations.json` - not companions.

## Maintainer: publish a station release

Run this from the **station** repo after a ship coworkers should receive (also documented in that project's `AGENTS.md` / `README` / `docs/Station-Release.md`):

1. Bump `version` in the station's `station.package.json` (single version authority).
2. Pack:

```powershell
# TicketTracker
pwsh -File C:\Projects\TicketTracker\build\Pack-Release.ps1

# Codex
pwsh -File C:\Projects\Codex\build\Pack-Release.ps1
```

3. Publish zip + `.sha256` to the private GitHub repo latest release (asset names must match `config/stations.example.json` patterns, e.g. `TicketTracker-1.2.3.zip`).

```powershell
gh release create v0.1.0 `
  .\build\out\TicketTracker-0.1.0.zip `
  .\build\out\TicketTracker-0.1.0.zip.sha256 `
  --repo jaxnoth/TicketTracker `
  --title "TicketTracker 0.1.0" `
  --notes "Station release for Metra Ops Station Updates."
```

Shared packer: [`packaging/Pack-MetraStationRelease.ps1`](../../packaging/Pack-MetraStationRelease.ps1).

## Manifest

- Example: `config/stations.example.json`
- Override: `config/stations.json` (gitignored if machine-local; copy from example when needed)

## Preserve / machine state

Stations declare `preservePaths` in `station.package.json`. TicketTracker today preserves `config/settings.json` + `data` (matches current gitignore). Codex also preserves cache, edits, and `data/kb-sync/ledger.json`.

Preserve is **copy-forward only**. Metra never migrates preserved file schemas during Install/Update. If a station ledger or settings format evolves, that station owns migration at its own startup - not the updater.

**Roadmap (not this sprint):** migrate machine secrets to `config/settings.local.json` (shipped defaults stay in example/`settings.json`), then preserve `*.local.json` + `data` so updates never merge secrets into shipped defaults.

## Apply contract

| Step | Behavior |
|------|----------|
| Discovery | GitHub `releases/latest` + asset pattern + `.sha256` sidecar |
| Dev checkout | `.git` present => `dev_checkout` => installer refuses |
| Staging | `{Name}.__staging` under work root |
| Preserve | Paths from package `preservePaths` only (update path) |
| Swap | Active -> `{Name}.__previous`, staging -> active |
| Receipt | `station.version` + `station.install.json` |
| Rollback | On failure after swap, restore `__previous` when possible |

Locks: `%LOCALAPPDATA%\Metra\locks\station-<id>-update.lock` plus Ops single-flight apply job.

## Recovery

| Symptom | Action |
|---------|--------|
| Folder named `TicketTracker.__previous` left behind | Ops interrupted mid-swap. Prefer renaming `__previous` back to `TicketTracker` if the live folder is missing or corrupt. Delete `__staging` leftovers. |
| `dev_checkout` cannot Update | Expected for maintainer Git clones. Use `git pull` (or pack+release for coworkers). |
| `authentication_required` / `repository_unavailable` | Sign in with `gh auth login` (or set `GH_TOKEN` / `GITHUB_TOKEN`) so Ops can read private station repos. Do not put tokens in `stations.json`. |
| `checksum_failed` / `invalid_release` | Re-publish a matching zip + `.sha256`; ensure `station.package.json` id/version agree with the release tag and asset name. |
| `apply_in_progress` stuck | Delete stale `%LOCALAPPDATA%\Metra\locks\station-*-update.lock` only after confirming no Ops apply job is running. |

## Glossary

| Prefer | Avoid (Updates language) |
|--------|---------------------------|
| Station | companion, product, satellite, portfolio station |
| Station Updates | Companion Updates |
| Install TicketTracker Station | Install TicketTracker plugin |

Sprint "portfolio companion" and marketplace "satellite plugin" are legacy aliases for other docs - not Ops Updates copy.
