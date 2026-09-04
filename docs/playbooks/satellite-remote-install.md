---
metraMemory: procedural
defaultContext: false
loadWhen:
  - satellite connect
  - satellite onboarding
  - Mac Metra
  - remote install satellite
ceiling:
  - First clone + PowerShell 7 install stays in the installer / remote session
  - IWU campus hosts pin is Windows-only (see tailscale-campus.md)
---

# Satellite remote install

Minimal path: personal tailnet, **HTTPS** HQ Ops, one `satellite connect` command.

## Prerequisites (remote session / installer)

1. PowerShell 7 (`pwsh`)
2. Metra checkout (e.g. `~/Developer/Metra`)
3. On personal tailnet (`tailscale up` - same tailnet as jumpbox)
4. Optional break-glass sync token from HQ (prefer Tailscale pair)

## HQ once

```powershell
cd C:\Projects\_meta
# Optional allowlist (empty = transitional open Ask; Self-login still auto-pairs)
Copy-Item .\docs\examples\client-auth.example.json (Join-Path $env:LOCALAPPDATA 'Metra\client-auth.local.json')
# Edit login/node/tag entries, then run Ops with Tailscale Serve / bindTailscale
```

Break-glass only if needed: `pwsh -NoProfile -File .\metra.ps1 profile issue-sync-token -Force`

HQ `opsBaseUrl` should be the HTTPS Serve URL, e.g. `https://jumpbox.emerald-banana.ts.net`.

## Satellite (one command)

Always use `pwsh -NoProfile -File` when double-clicking `.ps1` opens VS Code.

```bash
cd ~/Developer/Metra
pwsh -NoProfile -File ./metra.ps1 satellite connect \
  -OpsBaseUrl https://jumpbox.emerald-banana.ts.net
```

Happy path pairs over Tailscale (no `-SyncToken`). If pair is pending, Approve on HQ Ops Settings, then re-run connect/sync.

Break-glass override:

```bash
pwsh -NoProfile -File ./metra.ps1 satellite connect \
  -OpsBaseUrl https://jumpbox.emerald-banana.ts.net \
  -SyncToken '<token>'
```

`connect` checks HQ HTTPS, sets Satellite role, pairs/syncs (keeps local roots), stores device token.

## Verify

```bash
curl -sI https://jumpbox.emerald-banana.ts.net/api/settings
pwsh -NoProfile -File ./metra.ps1 profile status
```

Browser: `https://jumpbox.emerald-banana.ts.net`

## Optional follow-ups

| Need | Command |
|------|---------|
| Re-sync after HQ changes | `pwsh -NoProfile -File ./metra.ps1 profile sync -Force` |
| IWU campus Windows | [tailscale-campus.md](tailscale-campus.md) |
| Nonstandard checkout layout | Edit `metra.config.json` roots, then `profile sync -Force` |

## Done when

- `profile status` = **Current**
- Ops opens in browser over HTTPS

## Hard stops

- **HTTP** on MagicDNS fails - use **HTTPS** Serve URL
- Old work tailnet URL - pass `-OpsBaseUrl` explicitly
- Campus Serve cert error - [tailscale-campus.md](tailscale-campus.md)
