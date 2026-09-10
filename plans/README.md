# Formal plans (Loom handoff) and plan index

Yarn `synthesize` writes drafts to `%USERPROFILE%\.cursor\plans\` (Cursor Build/preview UX).

## Affiliation index (`plans/index.yaml`)

Git-tracks **affiliation metadata** only (schemaVersion 1):

- `stem` - normalized identity within the project
- `cursorLeaf` - optional Cursor filename under `~/.cursor/plans`
- `authority` - `cursor` (working body) or `repo` (scar under this folder)
- `repoPath` - relative scar path when `authority: repo`

Yarn `plan approve` upserts the index. It does **not** copy plan bodies into this folder.

Helpers: `Read-MetraPlanIndex`, `Set-MetraPlanIndexEntry`, `Resolve-MetraPlanPath`, `Resolve-MetraPlanWorkingPath`, `Initialize-MetraPlanIndexSeed`.

Existing `*.plan.md` files here remain **repository scars** (`authority: repo`). Do not delete them in this slice.

Human docs stay under `docs\`. Do not hand-author new Yarn plans into `docs\`.

Legacy `docs\*.plan.md` files remain readable for inventory and allowlists until migrated or archived.
