# Security

## Do not commit

Keep these local (gitignored). They often contain machine paths, private routing, or operator identity:

- `meta.config.json` (use `meta.config.example.json` or `profiles/sample/`)
- `projects.local.json` (use `projects.local.example.json`)
- `.cursor/rules/metra-persona.local.mdc` (use the example or sample pack)
- `docs/canvas-snapshot.json` (regenerate with `.\meta.ps1 snapshot`)

The tracked pack under `profiles/sample/` is intentional and anonymized. Do not replace it with a live export that contains real usernames, hostnames, or org-private paths.

Do not put secrets in `shared/` and then `apply` them across projects. Do not commit TicketTracker caches, Orion inventory dumps, or credential stores into this repo.

## Reporting issues

Report security concerns via GitHub Issues on this repository (or your org's private fork process). Do not attach live config, overlays, or snapshots that include private paths unless you have scrubbed them first.
