---
metraMemory: procedural
defaultContext: false
loadWhen:
  - ops ask
  - sidecar
  - MetraOpsDesk
  - host task
  - Serve HTTPS
  - phone Ask offline
ceiling:
  - Host UX stays tray; reach layer may use MetraOpsDesk Task
  - Do not store HQ Task password in Metra files or User env
---

# Ops Ask reach (sidecar stability)

Phone Ask over Tailscale Serve needs Ops + Cursor sidecar healthy, HTTPS Serve up, and an iOS timeout above the engine budget.

## Symptoms

- Chat shows "unavailable offline" for slow replies (45-180s)
- Auth/billing/model failures look like offline
- Sidecar dies after Ops hard-kill until the next Ask
- Serve fails quietly; phone cannot use HTTP MagicDNS

## Operator checks

```powershell
.\metra.ps1 host task status
# Unattended reach (password to Task Scheduler/LSA only - never Metra files / User env):
.\metra.ps1 host task install -Confirm
.\metra.ps1 host task uninstall -Confirm
```

Prerequisite: Tailscale in machine-service mode so Serve works without an interactive desktop.

Serve / campus hosts: [tailscale-campus.md](tailscale-campus.md).

## Design anchors (do not regress)

| Layer | Budget / rule |
|-------|----------------|
| Engine `Invoke-MetraAskEngine` | 180s |
| iOS `OpsAskClient` | 195s; `timedOut` ≠ offline; one early-reachability retry only |
| Ops accept-loop Ask poll | 45s from prior poll **completion** + Ensure |
| `/health` `degradedCode` | Set on auth/usage/model; **clears after one successful finish** (asymmetric vs 2-strike `ok` gate) |
| Task password | Task Scheduler / LSA only |

Tray Host remains optional UX and adopts a running desk; it does not start Ask directly.
