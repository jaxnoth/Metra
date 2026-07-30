# Security

## Do not commit

Keep these local (gitignored). They often contain machine paths, private routing, or operator identity:

- `metra.config.json` (use `metra.config.example.json` or `profiles/sample/`)
- `projects.local.json` (use `projects.local.example.json`)
- `.cursor/rules/metra-persona.local.mdc` (use the example or sample pack)
- `.cursor/rules/metra-humor.local.mdc` (optional; use the example or `profiles/addons/humor-desk`)
- `.cursor/rules/metra-teaching-gentle.local.mdc` (optional; use the example or `profiles/addons/teaching-gentle`)
- `docs/canvas-snapshot.json` (regenerate with `.\metra.ps1 snapshot`)
- `docs/context-pack.md` / `docs/context-pack.json` (regenerate with `.\metra.ps1 ctx`)
- `docs/*.local.md` (operator-private notes)

The tracked pack under `profiles/sample/` is intentional and anonymized. Do not replace it with a live export that contains real usernames, hostnames, or org-private paths.

Tracked Cursor hooks under `.cursor/hooks/` are safe to commit (no secrets). Do not put secrets in `shared/` and then `apply` them across projects. Do not commit TicketTracker caches, Orion inventory dumps, or credential stores into this repo. Never commit API keys or tokens from environment variables.

## Operator commands

`.\metra.ps1 run <command>` executes operator-provided shell text inside selected project folders (via `Invoke-Expression`). That is intentional portfolio tooling - not a sandbox.

- Only pass commands you trust.
- Do not feed untrusted or remote-controlled input into `run`.
- Prefer narrow `-Name` / `-Filter` / `-Root` so a bad command cannot fan out across the whole portfolio by accident.

## Reporting issues

Report security concerns via GitHub Issues on this repository (or your org's private fork process). Do not attach live config, overlays, snapshots, or context packs that include private paths unless you have scrubbed them first.
