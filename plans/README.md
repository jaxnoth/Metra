# Formal plans (Loom handoff)

Yarn `synthesize` writes drafts to `%USERPROFILE%\.cursor\plans\` (Cursor Build/preview UX).

On successful Loom ingest (`yarn plan approve` handoff, including reconcile retry), Metra **copies** the draft here as `<project>\plans\<leaf>.plan.md` and rewrites `formalPlanPath` to that copy.

Human docs stay under `docs\`. Do not hand-author new Yarn plans into `docs\`.

Legacy `docs\*.plan.md` files remain readable for inventory and allowlists until migrated or archived.
