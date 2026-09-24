---
name: Metra Stage 2 purge
overview: Rewrite public jaxnoth/Metra git history to remove InternalTopology/RestrictedDataMap blobs, force-update all branch refs, replace pre-scrub GitHub Releases with one clean tip build, and verify with a fresh-clone security-audit — Metra only; TicketTracker history out of scope.
todos:
  - id: preflight-freeze-backup
    content: Freeze pushes; bare-mirror backup; validate backup clonable; secret scan pre-filter (archive); tip Decisions ADR polish (Bing-gated); full remote ref inventory into completion package
    status: pending
  - id: filter-repo-mirror
    content: Inventory deny classes on mirror; git filter-repo rewrite all inventoried refs; verify rewritten mirror consistency; disposition every remote ref (rewrite/delete/retain)
    status: pending
  - id: force-push-github
    content: Force-push main (+ tags); GitHub cache purge with case ID in package; verify old SHAs unreachable
    status: pending
  - id: releases-replace
    content: Delete v0.1.0-v0.1.21 Releases; choose and record new version; build and publish one clean tip release
    status: pending
  - id: verify-completion
    content: Fresh-clone security-audit Fail=0; desk overlays smoke; Stage 2 completion package (ref ledger, scans, backup proof, case ID, version)
    status: pending
isProject: false
approveForLoom: true
approveForLoomHash: 9494dd3fde7a911cbebd599bd998cda3fee10ee7f062991206a6d5fbc0748921
externalReviewed: true
externalReviewHash: 9494dd3fde7a911cbebd599bd998cda3fee10ee7f062991206a6d5fbc0748921
status: Approved
loomHandoffId: yh-2887c32eb0edb93e95930a58f76d18ba
loomAcceptedAt: "2026-09-24T15:56:46.6116217Z"
---

# Metra Stage 2 history purge

Bing disposition: **Approve with Minor Changes** (amendments below are locked into this revision). Stage 1 solved tip architecture; Stage 2 solves history only - do not drift into fresh product scrub unless verification finds genuinely new public tip exposure.

## Go criterion (locked)

Proceed: third-party / coworker review already demonstrated public reachability of pre-scrub blobs ([metra-public-disclosure.md](C:/Users/admin.sswan/Downloads/metra-public-disclosure.md) + tip re-check). Tip is clean at `b13f185`; history and installers are not.

## Scope locked

- **In:** Public [jaxnoth/Metra](https://github.com/jaxnoth/Metra) only (`C:\Projects\_meta`).
- **Out:** TicketTracker history (private; Stage 1 companion already untracked HR maps). No Azure DevOps remotes.
- **Visibility:** Stay **public** through the rewrite (no temporary privatize). Communicate freeze + re-clone.
- **Releases:** Delete GitHub Releases `v0.1.0`–`v0.1.21` (and matching tags as needed), then cut **one** new release from the purged tip with a rebuilt installer.

## Preconditions (before any force-push)

1. Freeze: no pushes to `main` / tags / releases during the window; tell anyone with a Metra clone (you + any installer consumers).
2. Tip hygiene (forward-only, tiny): refresh [docs/Decisions.md](C:/Projects/_meta/docs/Decisions.md) 2026-08-27 campus ADR so it says optional **local-enabled** pin (matches [SECURITY.md](C:/Projects/_meta/SECURITY.md) / playbook). Commit+push normally (Bing-gated) before rewrite so the tip statement of record is accurate. No other tip redesign.
3. Backup: bare mirror clone of `origin` to a dated offline path (e.g. `%LOCALAPPDATA%\Metra\security-surface\stage2\metra-mirror-YYYYMMDD.git`). Do not skip.
4. **Backup restoration validation (required):** from that mirror, `git clone` into a throwaway worktree and confirm `git log -1` / `git fsck` succeed. Record clone path + `fsck` summary in the completion package. Do not force-push until this passes.
5. **Secret scan (required):** run a full-history secret scan on the mirror **before** filter-repo; archive the report under `%LOCALAPPDATA%\Metra\security-surface\stage2\`. Rotate any live credential found. Re-run after filter and archive the post-filter report too.
6. Tooling: `git-filter-repo` available; operator GitHub admin on `jaxnoth/Metra`.
7. Working tree clean; note current tip SHA (`b13f185` or later tip-polish SHA).

### Remote ref inventory (required before filter)

Do not assume the known side branches are the only refs.

1. Enumerate **all** remote refs: branches, tags, and any other `refs/` GitHub exposes (`git ls-remote origin`, `gh api repos/jaxnoth/Metra/branches`, `gh api repos/jaxnoth/Metra/git/matching-refs/`).
2. Write `ref-inventory-pre.json` (or `.md`) into the completion package with every name + SHA.
3. For each ref, plan a disposition: **rewrite**, **delete**, or **intentionally retain** (with rationale). Expected default: rewrite `main` + any tag that still carries bad blobs; **delete** `cursor/communications-agent-284c` and `review/communications-agent-rewrite` if still 0 ahead of `main`; retain only PublicSafe-only refs if any exist.
4. Done-when for this step: every inventoried remote ref has an explicit disposition recorded before filter-repo runs.

## Rewrite strategy

Use **git filter-repo** on a **fresh mirror**, not the daily checkout.

### What to purge

Path / content classes already denied by tip `security-audit` (InternalTopology + RestrictedDataMap), including historical forms of:

- Org / AD / share / host needles (`ORGNET`, `example-org`, `etl-host`, UNC Scripts, `prd-*` as hostnames, lab MagicDNS, personal machine paths)
- HR/payroll maps (`VendorX`, `DM-Sample`, census fn patterns)
- Pre-scrub campus playbook bodies that named org VIP / OrgBrand framing (tip is generic; old blobs are not)

Prefer **path-aware + content** passes over deleting whole product features. Keep MIT / public product history where blobs are PublicSafe.

Practical approach:

1. Content inventory: from mirror, list commits/files matching deny high-signals (same classes as [scripts/private/SecuritySurface.ps1](C:/Projects/_meta/scripts/private/SecuritySurface.ps1)).
2. filter-repo: remove or replace sensitive paths/blobs (and rewrite messages if they embed org needles), applying to **all refs marked rewrite** in the inventory.
3. Apply delete dispositions for stale branch names with no unique tip value.
4. **Rewritten-mirror consistency (required before force-push):** on the filtered mirror, `git fsck`, sample `git log` / `git rev-list --all`, and confirm tip `security-audit` Fail=0 in a worktree cloned from the filtered mirror. Archive those outputs.

```mermaid
flowchart LR
  Freeze[Freeze_pushes]
  Backup[Bare_mirror_backup]
  BackupOk[Validate_backup_clone]
  Refs[Remote_ref_inventory]
  TipPolish[Tip_Decisions_ADR]
  SecretsPre[Secret_scan_pre]
  Filter[git_filter_repo_on_mirror]
  MirrorOk[Validate_rewritten_mirror]
  SecretsPost[Secret_scan_post]
  Force[Force_push_main_and_tags]
  GhPurge[Request_GitHub_cache_purge]
  RelDel[Delete_old_Releases]
  RelNew[Build_and_publish_new_Release]
  Verify[Fresh_clone_security_audit]
  Freeze --> Backup --> BackupOk --> Refs --> TipPolish --> SecretsPre --> Filter --> MirrorOk --> SecretsPost --> Force --> GhPurge --> RelDel --> RelNew --> Verify
```

## Force-update and GitHub cleanup

1. Force-push rewritten `main` (`--force-with-lease` only if lease still matches freeze; otherwise coordinated `--force` after confirming no competing pushes).
2. Force-update or delete tags per ref inventory dispositions (tags that only existed for scrubbed releases go with release deletion).
3. Delete remote branches per inventory (expected: `cursor/communications-agent-284c`, `review/communications-agent-rewrite`).
4. Open GitHub support / cache purge for dangling commits. **Record support case ID or URL** in the completion package (`github-cache-purge.txt`). Verification package is incomplete without it.
5. After purge window: confirm known pre-scrub SHAs (`32ecbc22`, `53d9be30`, …) are unreachable via GitHub UI/API; archive evidence.

## Releases and installer

1. Delete Releases `v0.1.0` … `v0.1.21` and associated assets (`MetraSetup.exe`, checksums).
2. From purged tip: build installer via existing Metra packaging path (same Ship It / Inno flow used for prior releases).
3. Publish **one** new semver (bump past `0.1.21`; exact version chosen at execute time from package version). **Record chosen version** in the completion package (`release-version.txt`) and in release notes that prior public installers were retired for structural-disclosure remediation.
4. Confirm Pages / marketplace pack source in-repo derives from purged tip (no separate republish if they track `main`).

## Verification (done-when)

| Check | Pass rule |
|-------|-----------|
| Ref ledger | Every pre-filter remote ref is rewrite / delete / retain with post-state SHA or deleted marker |
| Backup | Documented successful clone + `fsck` from pre-filter mirror |
| Rewritten mirror | `fsck` clean; tip audit Fail=0 before force-push |
| Secret scans | Pre- and post-filter reports archived in completion package |
| Fresh clone of `main` | `.\metra.ps1 security-audit` Fail=0 |
| History needles | Fresh clone history `git grep` for Inventory high-signals empty (or deny-assembler concatenations only) |
| Old SHA | Known pre-scrub SHAs unreachable on GitHub after purge window |
| Cache purge | Support case ID/URL recorded |
| Release | Chosen new version recorded; old `v0.1.0`–`v0.1.21` gone; new Release URL live |
| Local desk | AppData campus + routing overlays still present; `campus-hosts -Preview` Ok with local enabled |
| Completion package | All of the above under `%LOCALAPPDATA%\Metra\security-surface\stage2\` |

## Operator / consumer communication

Before force-push: one short message — freeze window, expect re-clone or hard reset, old SHAs invalid, reinstall from new Release if using `MetraSetup.exe`.

After: confirm fresh clone instructions; do not tell people to `pull` over rewritten history.

## Explicit non-goals

- Privatizing Metra
- TicketTracker `git filter-repo`
- Rewriting Azure DevOps remotes
- Claiming tip `security-audit` alone proved history clean (it never did)
- Fresh product/architecture scrub beyond the tiny Decisions ADR tip polish (unless verification finds new tip exposure)

## Execute gate

Do **not** start filter-repo / force-push until you explicitly say to execute this plan. Tip ADR polish may land as a normal Bing-gated commit immediately before the rewrite window.
