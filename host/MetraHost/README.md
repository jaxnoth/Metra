# MetraHost - C# tray supervisor for Metra Ops

WinForms `NotifyIcon` host with a distinct process identity (`MetraHost.exe`), not a hidden PowerShell window.

## Ownership

**Host -> Ops -> Ask.** This process never starts the Ask sidecar. Desk start/stop/open go through `scripts/bootstrap/Invoke-MetraOpsHostBridge.ps1`.

Cold start uses one `host-bootstrap` bridge call (single `Import-Module`) for assert, port, session, and desk adopt/start. Start Menu shortcut refresh runs on the first tray timer tick.

Pattern for sibling Host concerns:

```text
Host        supervises
Worker      executes
Ops         reports
Yarn        schedules
Project     consumes
```

## Cursor My Machines worker

When `%LOCALAPPDATA%\Metra\host\cursor-worker.local.json` has `enabled=true`, MetraHost also ensures a personal Cursor **My Machines** worker against the Metra checkout (`--root` / configured `workerDirs`). Bridge: `scripts/bootstrap/Invoke-MetraCursorWorkerBridge.ps1` (`status` | `ensure` | `stop` | `repair-sqlite`). Example config: `cursor-worker.local.example.json` (default `enabled: false`).

- **Identity:** `Running` requires daemon + configured `name` + expected workspace. Foreign/ambiguous workers are `Error` - Host never kills or takes them over in v1.
- **Shutdown:** Exit MetraHost / tray application stops the owned worker. Stop desk / Ops runtime does **not**.
- **ABI repair:** ensure detects `RepairRequired` only. Operator runs `repair-sqlite` (persisted attempt ledger under `%LOCALAPPDATA%\Metra\host\cursor-worker-repair.json`). Ensure never repairs.
- **Cadence:** separate Host feature and lease - worker health is not cadence health.

Ops may later surface lifecycle state; v1 UI is tray tooltip + bridge CLI.

## Yarn cadence

When `%LOCALAPPDATA%\Metra\host-cadence.json` has `enabled=true`, the tray also owns Yarn/Loom Pulse and Daily timing. Every ~30s Host evaluates an in-process due gate against `host-cadence.json`; it only spawns bridge `cadence-tick` when Pulse/Daily may be due (`CreateNoWindow`, no `-WindowStyle Hidden`; `timeoutMs: 7_200_000` = 2 hours, matching the cadence lease). If the bridge times out, OpsBridge kills the child process tree and Host logs `bridge_timeout`; `activeRunKind` stays until lease repair (no invented completion). Stage execution stays in `Invoke-MetraYarnLoomSchedule`. Desk supervision is not blocked by a long Pulse/Daily. Enable via Ops Settings → Desk → Yarn cadence or `.\metra.ps1 yarn schedule host enable -Confirm` (see `docs/playbooks/yarn.md`).

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
