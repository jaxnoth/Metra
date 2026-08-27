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
  - Do not disable campus security tooling; pin Tailscale coordination hosts only
  - Hosts write requires elevation
---

# Tailscale on IWU campus (DNSFilter)

## Symptom

Edge/Chrome opens `https://login.tailscale.com/...` (Serve enable, admin) and shows:

- `NET::ERR_CERT_AUTHORITY_INVALID`
- Issuer **DNSFilter Root CA** (campus MITM)
- HSTS blocks "proceed anyway"

Ops on jumpbox may still run on loopback. Mac/phone cannot use MagicDNS/Serve until Serve is enabled and/or Tailscale URL ACLs exist for the **personal** tailnet IP.

## Cause

Campus DNSFilter rewrites or intercepts `login.tailscale.com` (often to a VIP such as `45.54.28.11`). Real Tailscale coordination anycast is `192.200.0.0/24` with Let's Encrypt certificates.

`controlplane.tailscale.com` is often already pinned; **`login.tailscale.com` usually is not**.

## Fix (Metra)

```powershell
cd C:\Projects\_meta
.\metra.ps1 tailscale campus-hosts -Preview
# Elevated PowerShell:
.\metra.ps1 tailscale campus-hosts
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

- `https://login.tailscale.com/` shows a Let's Encrypt (or Tailscale) cert, not DNSFilter
- `tailscale serve status` shows a configured handler
- Mac can `curl` the jumpbox Ops share URL on the personal tailnet

## On hard stop

- Elevation denied for hosts write - operator must run campus-hosts in Admin PowerShell
- Public DNS to 1.1.1.1/8.8.8.8 blocked - resolve offline and pass known `192.200.0.x` lines manually into hosts
- Org Tailscale Entra app deactivated - use personal tailnet; campus-hosts does not restore work IdP enrollment
