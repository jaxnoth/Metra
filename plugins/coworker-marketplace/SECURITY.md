# Security notes (IWU Coworker marketplace pack)

This folder is meant to publish as a **standalone GitHub repo** whose root is the marketplace (`.cursor-plugin/marketplace.json` at repo root). Cursor Team Marketplace (e.g. **IWU SDT Market**) imports that repo.

## What is allowed to publish

- Plugin manifests (`plugin.json`, `marketplace.json`)
- Skills (`SKILL.md`) that describe CLI sequences and format rules only
- SVG logos under `assets/`
- Maintainer scripts under `scripts/` (local symlink / skill sync / publish assert)

## What must never be published

- Credentials, tokens, API keys, `.env`, `settings.json` with secrets
- Ticket dumps, assessment artifacts, KB page bodies, mail/Teams caches
- Operator-private overlays, personal skill copies, Cursor API keys
- Live host passwords, connection strings, or internal admin URLs that unlock write access

## Hard offs encoded in skills

- No auto iSupport `post` / `recommend` / `resolve`
- Codex skill does not write tickets
- Desk skill does not replace `metra.ps1` routing
- Skills point at local CLIs; they do not embed Live evidence

## Pre-publish check

From this folder:

```powershell
.\scripts\Assert-PublishSafe.ps1
```

Fix any finding before push. Prefer a **private** GitHub repo readable by the IWU Cursor team until dry-run 2.

## Path portability

Skills use checkout placeholders (`<Metra checkout>`, `<TicketTracker checkout>`, `<Codex checkout>`). Do not reintroduce machine-specific absolute paths or home-directory paths in tracked files.
