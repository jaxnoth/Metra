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
- Do not expose `run` (or equivalent shell execution) from HTML Ops / Ask / proposal apply.

## Propose-Confirm-Apply (Ops desk vs Host hands)

Architectural covenant for web-originated edits. Product policy: [docs/Decisions.md](docs/Decisions.md) (2026-08-04 Secure Ops). Implementation plan: Cursor `attention_resolve_actions_bcb3e7aa`.

### Invariants

1. The browser never writes the workspace. Metra Ops proposes and previews. The tray Host is the only process that applies.
2. Web-originated change requests are untrusted proposal objects until the user-session Host validates, confirms, applies, and audits them.

Ops may become the desk. Host remains the hands. Desk: route, brief, preview, ask, handoff. Hands: confirm, apply, run, push, shell, privileged side effects.

### Validation ownership

- Slice 3 owns what is legal (shared jail library).
- Slice 4 owns preview (Ops eligibility checks; no project disk write).
- Slice 5 owns truth (Host revalidates, native confirm, apply, audit).

Never treat Ops preview success as apply authority.

### Proposal rules

- After `contentHash` is calculated, the canonical proposal body is immutable. Any change creates a new proposal id, hash, and nonce.
- Required `schemaVersion` (v1 = `1`). Host rejects missing or unknown versions; do not partial-apply future shapes.
- Status: only `draft` -> `pendingApply`; only `pendingApply` may be applied; `applied` / `rejected` / `expired` are terminal.
- Store under `%LOCALAPPDATA%\Metra\proposals\` (immutable body separate from mutable status). Audit denials and successes under `%LOCALAPPDATA%\Metra\apply-audit.log`.
- Replace requires `previousHash` matching the current file. Create must not overwrite an existing file. No replace-if-changed.

### Ops HTTP

Allowed shapes: `POST/GET /api/proposals`, `GET .../diff`, `POST .../request-apply`, `GET .../status`.

Do **not** add an endpoint named `/apply`. Naming matters: HTTP may only request apply; Host performs it after native **Apply once** confirmation (not `window.confirm`).

### Jail (v1 web-originated apply)

Allow (boring text): `.md` `.txt` `.json` `.csv` `.yml` `.yaml` (optional module manifests later; not default).

Deny explicitly: `.exe` `.dll` `.ps1` `.bat` `.cmd` `.msi` `.pfx` `.key` `.pem` `.env`

Deny path patterns including: `.git`, `node_modules`, `bin`, `obj`, `.vs`, `.vscode/settings.json`, `ops-preferences.local.json`, and name patterns for credential/secret/token/password.

Also: single registry project root; no `..` / absolute escape; reject symlink/reparse escape; UTF-8 text; small file count/size caps; no delete/rename/chmod; no git commit/push from apply.

### Reach vs authority (non-loopback)

Default Ops bind is loopback. Opt-in Tailscale (or other non-loopback) bind is for **reach** (view / share / ask), not anonymous write authority.

`POST /api/open` (Open in editor) launches the operator's editor on the desk machine. It never writes files, and it is constrained twice: the path must be an existing folder inside a configured root or the Metra home, and the caller must be that machine (loopback or one of its own addresses) or present `X-Metra-Local-Session`. Remote peers get a refusal plus the path.

When bound non-loopback: proposal create and `request-apply` require a local Host-issued session marker (`X-Metra-Local-Session`, file `%LOCALAPPDATA%\Metra\ops-local-session.token`, issued/rotated by Host / Ops start). Safe default: remote peers may view and ask; only the local operator session may request-apply unless a later product decision loosens that. `GET /api/local-session` is loopback-only so remote callers cannot fetch the marker. Host native confirmation still gates every disk write. Opt-in bind: prefs `bindTailscale` or `Initialize-MetraOpsDeskBinding -BindTailscale`. When Tailscale reach is on, Ops start orchestrates Tailscale Serve so the share URL is HTTPS (secure context); Serve is not required to run Metra on loopback. Funnel is out of scope. Place quarantine uploads (`POST /api/place/upload`) are Ask-class reach into `%LOCALAPPDATA%\Metra\ops-place-quarantine\` only - never project trees; durable homes are not auto-created from Route something. Confirming a recommendation records a pointer to the staged file (id, name, quarantine path) in local place memory so the note can be traced back; the bytes stay in quarantine and are never copied into a project. Unknown or path-shaped attachment ids are ignored.


### Explicitly rejected patterns

- Ops HTTP writing project files
- Auto-apply Ask output
- Browser-only confirm
- Mutating a hashed proposal body in place
- Replace without `previousHash` / replace-if-changed
- Partially applying unknown `schemaVersion`
- Anonymous non-loopback proposal create or request-apply
- Arbitrary shell / `metra.ps1 run` from the desk as apply
- Quietly building Invoke-Expression with buttons

Large-scale refactors stay editor-first; see operator Future-Development Secure Ops scar.

## Reporting issues

Report security concerns via GitHub Issues on this repository (or your org's private fork process). Do not attach live config, overlays, snapshots, context packs, proposal bodies, or apply-audit logs that include private paths unless you have scrubbed them first.
