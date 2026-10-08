# MetraHost - C# tray supervisor for Metra Ops

WinForms `NotifyIcon` host with a distinct process identity (`MetraHost.exe`), not a hidden PowerShell window.

## Ownership

**Host -> Ops -> Ask.** This process never starts the Ask sidecar. Desk start/stop/open go through `scripts/bootstrap/Invoke-MetraOpsHostBridge.ps1`.

Cold start uses one `host-bootstrap` bridge call (single `Import-Module`) for assert, port, session, and desk adopt/start. Start Menu shortcut refresh runs on the first tray timer tick.

## Yarn cadence

When `%LOCALAPPDATA%\Metra\host-cadence.json` has `enabled=true`, the tray also owns Yarn/Loom Pulse and Daily timing. Every ~30s the Host may call bridge `cadence-tick` on a background thread (`CreateNoWindow`; `timeoutMs: 7_200_000` = 2 hours, matching the cadence lease). If the bridge times out, OpsBridge kills the child process tree and Host logs `bridge_timeout`; `activeRunKind` stays until lease repair (no invented completion). Stage execution stays in `Invoke-MetraYarnLoomSchedule`. Desk supervision is not blocked by a long Pulse/Daily. Enable via `.\metra.ps1 yarn schedule host enable -Confirm` (see `docs/playbooks/yarn.md`).

## Build

```powershell
pwsh -File .\host\MetraHost\Build-MetraHost.ps1
```

Output: `host\MetraHost\publish\MetraHost.exe`

## Launch

- Start Menu / `Metra-Ops.cmd` prefers the published exe, then falls back to the PowerShell tray.
- Direct: `.\host\MetraHost\publish\MetraHost.exe --root C:\Projects\_meta --no-browser`

## Args

| Arg | Meaning |
|-----|---------|
| `--root <path>` | Metra checkout root |
| `--port <n>` | Ops port (default: resolve from binding) |
| `--no-browser` | Do not open the desk on start |
| `--force-local` | Sets `METRA_OPS_FORCE_LOCAL=1` for Mode B stations |
