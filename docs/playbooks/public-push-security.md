# Public push security gate

Trigger: about to `git push` Metra (or any public GitHub/GitLab remote); shipping a bite that touched tracked docs/scripts with operator topology.

## Checklist

1. Run structural audit (blocks push when hooks installed):

```powershell
cd C:\Projects\_meta   # or the public repo root
.\metra.ps1 security-audit -Force
```

2. For a meaningful ship (multi-file feature, new client surfaces, gate scripts), run a **security review** that includes identifying info: secrets/auth plus names, UDIDs, hostnames, Tailscale addresses, absolute paths with usernames, full device tokens in UI. Cursor: security-review Task with Custom Instructions naming identifying info.

3. Scrub FAIL into placeholders / gitignored locals (`ios-gate.local.json`, `station.local.md`, `Config/Local.xcconfig`). Do not broaden allowlist without `rationale`, `approvedBy`, `sourceFile`, `expiresOn`.

4. Then push. Hooks: `.\metra.ps1 inspect hooks install` (pre-commit Bing + pre-push security-audit).

Emergency skip (operator-owned): `METRA_SKIP_SECURITY_PUSH=1 git push ...`

## Related

- [SECURITY.md](../../SECURITY.md) Public surface + Public push gate
- Decisions 2026-10-20 Public push requires security-audit
