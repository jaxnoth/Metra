# Plan: Tailscale identity auth (Ask + Profile Sync)

**Status:** Shipped (CLI + Ops host; Bing minors folded 2026-08-29)  
**Date:** 2026-08-29  
**Product:** Metra Ops host + Satellite / remote clients (CLI now; iOS companion later)  
**Replaces (target):** Paste-first Profile sync token as the primary pairing model  
**Does not replace:** Local authority gates, Host apply confirmation, Serve≠loopback scar

---

## 1. Problem

Today, Satellite / profile sync expects a **host-issued bearer** copied to the client (`profile issue-sync-token` → `X-Metra-Profile-Sync` / `docs/profile-sync.local.json`). That string can be lost, mistyped, or left stale on an old machine. Operators reasonably ask: if both sides are already on the same Tailscale tailnet, why paste a key?

Ask over Tailscale is already **Ask-class** (reach without local-authority). Profile sync and device pairing still lean on the pasteable token.

---

## 2. Direction (locked)

| Layer | Owner |
|-------|--------|
| **Reach** | Tailscale (MagicDNS / Serve / tailnet IP) |
| **Identity** | Tailscale WhoIs on the caller (login, node name, tags) |
| **Authorization** | Ops host allowlist of identities (config, not a shared password) |
| **Optional revoke granularity** | Host-minted **device token** after first Tailscale-proven pair; client stores in Keychain / local secret store |
| **Local authority** | Unchanged - same machine or `X-Metra-Local-Session` only; transport is never authority |

**Anti-pattern:** scanning Tailscale to invent a “common key” both CLIs derive. That is still a shared secret with worse operational properties.

**Centering:** phone / satellite is a **client** of Ops. Not a second Metra.

---

## 3. Target flows

### 3.1 Discover Ops

Client resolves Ops via configured MagicDNS name, Tailscale IP, or Serve HTTPS URL. No token required for discovery.

### 3.2 First pair (Satellite or iOS)

1. Client calls a pairing endpoint over Tailscale.
2. Host runs WhoIs on source IP (or Serve identity headers where trustworthy).
3. If identity matches allowlist (or operator clicks Approve on Ops desk for first-seen node): host accepts.
4. Host mints device capability token; client stores it.
5. Later requests: Tailscale identity **and/or** device token per route policy (start strict: both for sync writes; Ask may allow allowlisted identity alone).

### 3.3 Ask

- Prefer: allowlisted Tailscale identity (existing Ask-class path + allowlist tightening).
- Optional: require device token for non-desk clients once iOS ships.
- Still fail closed offline (no fake answers) - see iOS umbrella offline contract.

### 3.4 Profile sync

- Replace paste-first bootstrap with Tailscale-proven pair (above).
- Keep bearer header only as the **minted device/sync capability**, not as something the operator re-types from Settings forever.
- `issue-sync-token` becomes break-glass / rotation, not the happy path.
- Export/status rules stay: no secrets in export; roster visibility stays local-authority scoped where already required.

### 3.5 Revoke

- Remove identity from allowlist, **or** revoke device token on host, **or** remove node from tailnet ACL.
- Do not require rediscovering a lost paste string.

---

## 4. Implementation bites (for a dedicated chat)

1. **WhoIs helper** on Ops host (Tailscale CLI or local API) → stable identity record for a request.
2. **Allowlist config** (example + local gitignored) - login / node / tag entries.
3. **Pairing API** - first-seen policy: auto-allow if login matches operator, else pending approve on Ops Settings.
4. **Device token mint/store/validate** - rotate, revoke, list devices (local authority to manage).
5. **Satellite `profile sync` / setup** - prefer Tailscale pair; deprecate paste as primary UX; keep `-SyncToken` as override.
6. **Ask path** - optional allowlist enforcement without breaking loopback desk.
7. **Docs** - Brand vocabulary, Cross-Device, SECURITY reach vs authority, Satellite install playbook.
8. **Tests** - WhoIs mock; allowlist hit/miss; Serve must not grant local authority; revoke stops sync.

---

## 5. Non-goals

- Public internet / Funnel auth.
- Replacing Cursor API keys or engine credentials.
- Granting remote Host apply or project-tree writes via Tailscale identity alone.
- Deriving a PSK from node keys or MagicDNS names.

---

## 6. Done when

- New Satellite can sync **without** pasting a token, given Tailscale + allowlisted identity (or one Ops approve click).
- Operator can revoke one device without regenerating a global paste secret.
- SECURITY scars preserved: Serve ≠ local authority; Ask-class ≠ apply authority.
- iOS Phase 1 device-token plan plugs into the same mint/validate path.

---

## 7. Related

- Decision: `docs/Decisions.md` (2026-08-29 Tailscale identity)
- `SECURITY.md` - Reach vs authority
- `plans/ios-companion-app.plan.md` - section 2.3 Device auth
- `docs/Brand.md` - Profile sync token (transitional)
- `docs/Cross-Device.local.md` - current paste flow
