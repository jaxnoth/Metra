---
metraMemory: procedural
defaultContext: false
loadWhen:
  - tailscale
  - campus hosts
  - DNSFilter
  - login.tailscale.com
  - bindTailscale
  - Serve
ceiling:
  - Do not disable campus security tooling; pin Tailscale coordination hosts only when local config enables it
  - Hosts write requires elevation
  - Do not commit docs/tailscale-campus.local.json or AppData campus config
---

# Tailscale behind DNS-filter MITM (campus hosts)

## Symptom

Edge/Chrome opens `https://login.tailscale.com/...` (Serve enable, admin) and shows:

- `NET::ERR_CERT_AUTHORITY_INVALID`
- Issuer from a network TLS inspection / DNS-filter Root CA
- HSTS blocks "proceed anyway"

Ops on jumpbox may still run on loopback. Mac/phone cannot use MagicDNS/Serve until Serve is enabled and/or Tailscale URL ACLs exist for the personal tailnet IP.

## Cause

Some networks rewrite or intercept Tailscale admin hostnames, terminating TLS with a local root CA instead of Tailscale's public cert. Real Tailscale coordination anycast uses publicly documented ranges (see Tailscale docs) with Let's Encrypt certificates.

## Fix (Metra) - local config required

Tracked Metra does **not** auto-enable a hosts pin. Station enablement is local-only:

1. Copy `docs/examples/tailscale-campus.local.example.json` to either:
   - `%LOCALAPPDATA%\Metra\tailscale-campus.local.json` (preferred), or
   - `docs/tailscale-campus.local.json` (gitignored)
2. Set `"enabled": true` and adjust hostNames / preferredCidr / dnsServers if needed.
3. Preview, then apply elevated:

```powershell
cd C:\Projects\_meta
.\metra.ps1 tailscale campus-hosts -Preview
# Elevated PowerShell:
.\metra.ps1 tailscale campus-hosts -Force
```

Then refresh the Serve enable URL (from `tailscale serve` output or Ops warning). Configure Serve:

```powershell
tailscale serve --bg http://127.0.0.1:80
tailscale serve status
```

Re-enable Ops Tailscale bind when URL ACLs for the **current** Tailscale IPv4 / MagicDNS exist:

```powershell
netsh http add urlacl url=http://<tailscale-ip>:80/ user=Everyone
netsh http add urlacl url=http://<magicdns>:80/ user=Everyone
```

Or keep Ops on loopback and front it with Serve only (HTTPS share URL).

## Done when

- `https://login.tailscale.com/` shows a Let's Encrypt (or Tailscale) cert, not the network inspection CA
- `tailscale serve status` shows a configured handler
- Mac can `curl` the jumpbox Ops share URL on the personal tailnet

## On hard stop

- Missing local config / `enabled=false` - campus-hosts refuses; copy the example and enable
- Elevation denied for hosts write - operator must run campus-hosts in Admin PowerShell
- Public DNS blocked - resolve offline and set known anycast lines via local config + hosts edit
- Org Tailscale Entra app deactivated - use personal tailnet; campus-hosts does not restore work IdP enrollment
