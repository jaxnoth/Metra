# Proposal: branch-based dev cycle with small auto-commits (all Metra projects)

Status: SUPERSEDED by `plans/branch-dev-cycle.plan.md` (kept for provenance; owner direction 2026-11-18). Author: Claude.
Applies to: every project driven through the Metra inspect loop (Metra itself, ColleagueDataMover, Wayside, others).

## Why change

| Today | Problem it causes |
|---|---|
| The pre-commit hook requires a Bing affirm for **every** commit | Work can't be committed until the whole bite is reviewed, so each bite becomes one large commit on the main branch |
| Bing reviews the **working tree** (staged + unstaged + untracked) | Anything that changes during review makes the pack stale ("appendix rebuilt from current disk", hash mismatches, wasted rounds) |
| Work sits uncommitted for hours | Nothing is backed up until ship; one machine holds everything |
| Bing sometimes writes "affirm" in its prose and Metra acts on it | The gate depends on reviewer wording, not on a defined rule |

## The new cycle (one bite)

```text
bite start      → branch bite/<project>/<bite-id> from the protected branch (every repo the bite touches)
implement       → small auto-commits on the bite branch, each after a green quick check; pushed as backup
bite pack       → inspect + pack the RANGE merge-base..HEAD (a fixed commit, not the working tree)
Bing review     → verdict on that exact head SHA
bite ship       → if verdict=approve AND reviewed SHA == branch head: auto-affirm, merge --no-ff, push, delete branch
changes needed  → new commits on the same branch → bite pack again (no history rewrite, no force-push)
```

### 1. Branches
- Name: `bite/<project>/<bite-id>` (e.g. `bite/cdm/e3c-oidc`). Loom keeps `loom/...`; both are "work branches" to the hooks.
- **Protected branches** per project, from the registry (`protectedBranches`): e.g. Metra `main`; CDM root `workspace/main` (local `main`), chef `master`, cookbook `master`; Wayside `main`.
- **Multi-repo bites** (CDM root + `chef/` + `cookbook/` worktrees): `bite start` creates the same branch name in every repo the bite declares. Ship merges in dependency order (cookbook → chef → root) and records each repo's merge SHA in the root merge commit message.

### 2. Small auto-commits
- The implementer commits after each coherent step **when the quick check passes** (the project's fast test set; for CDM the touched suites, not the full suite).
- Message: `wip(<bite-id>): <what changed>` in ordinary professional prose. Size guideline: one concern per commit, about 300 changed lines or fewer.
- The hook on work branches runs **fast safety checks only**: secret scan, blocked paths (`generated/restricted/`, `.authoring/`, `*.runtime.properties`, etc. per project), no files over a size limit. No Bing gate on work branches.
- Each auto-commit is pushed to the remote as a backup (`git push -u origin bite/...`). Work branches are never force-pushed.

### 3. Review a commit range, not the working tree
- `bite pack` = `inspect prepare-bing -Base <merge-base>` (three-dot `Base...HEAD`, which inspect already supports). Refuses if the working tree is dirty.
- `contentHash` binds to the **head SHA** (plus the merge-base). The pack header shows both SHAs.
- Fixes during review are new commits. The next pack covers the whole range again with the new head.

### 4. Gate: Bing may affirm (owner direction 2026-11-18)
- `bite ship` affirms automatically when **all** of these hold:
  1. the imported review's machine `verdict` field is `approve`;
  2. its echoed `contentHash` matches the pack, and the pack's head SHA equals the branch head now;
  3. the review passes the existing contract shape (`reviewDepth`, non-empty `evidenceInspected`, a substantive Verified item);
  4. the full test gate for the project passes on the branch head.
- The reviewer's **prose is never an instruction.** "Affirm" in a reply means nothing; only the verdict field counts.
- **Optional owner-affirm list per project** (`ownerAffirmPaths` in the registry): if the range touches a listed path, ship waits for the owner. Empty by default. Suggested for CDM: Kitchen auth (`chef/src/ColleagueDataMover.Kitchen/Program.cs`, `Services/*Auth*`, `Services/KitchenGates.cs`), `module/Cdm.Approval.ps1`, `module/Cdm.Result.ps1` (redaction), `config/authority-grants.yaml`, `config/identity-aliases.yaml`, `cookbook/policy/`.
- Anything other than a clean approve (changes-requested, blocked, hash or SHA mismatch, bad shape) stops and reports.

### 5. Merge into the protected branch
- `git merge --no-ff bite/...` with message `<bite-id>: <summary> (reviewed <short SHA>, Bing approve <hash8>)` plus the project's work-item tag (e.g. `AB#919`).
- Why `--no-ff`, not squash: the protected branch gets **one commit per bite** (one thing to revert, one line in `--first-parent` history), and the small commits stay reachable for blame and bisect.
- Then push the protected branch and delete the bite branch locally and remotely.
- **Protected-branch rule (hooks):** a direct commit on a protected branch is refused; only `bite ship` (or Loom's verified `-Merge`) merges into it. The emergency skip env var stays, and is logged.

### 6. Checkpoints and audits
- Claude checkpoint audits review `--first-parent` ranges on the protected branch between tags: `bite ship` can tag `cp/<n>` when a bite is marked as a checkpoint bite.

## Hook changes (scripts/githooks)

| Hook | Work branch (`bite/*`, `loom/*`) | Protected branch |
|---|---|---|
| pre-commit | Fast safety checks only | Refuse, unless the commit is the ship merge (marker set by `bite ship`) |
| pre-push | Security audit as today (public remotes) | Security audit + refuse unless pushed by `bite ship` (or Loom merge) |

## New commands (Metra CLI)

| Command | Does |
|---|---|
| `metra bite start -Name <P> -Bite <id> [-Repos root,chef,cookbook]` | Clean-tree check; create and push the branch in each repo |
| `metra bite commit -Name <P> -m "<msg>"` | Quick check → commit → push (what agents call; no `git commit` directly) |
| `metra bite pack -Name <P>` | Clean-tree check; prepare-bing over merge-base..HEAD in each repo; pack bound to head SHAs |
| `metra bite ship -Name <P>` | Verify review + SHAs + full tests → affirm → merge --no-ff in dependency order → push → delete branches → log |
| `metra bite status -Name <P>` | Branch, commits since base, last pack hash, review verdict, ship readiness |

## Rollout

1. **Metra repo first:** implement the commands and hook changes in `_meta`; use them for their own bite (dogfood).
2. **ColleagueDataMover next:** registry `protectedBranches` for root, chef and cookbook; `ownerAffirmPaths` per the list above. Start with E3c as the first branch bite.
3. **Wayside and the rest** after one clean CDM bite.
4. Update `docs/playbooks/inspect-loop.md` (coding-loop table, gate row), `metra-inspect-loop.mdc`, project-lane and Loom playbooks, and record the decision in `docs/Decisions.md` (supersedes "Bing affirm is the operator manual gate before commit" and "Never auto-affirm").

## Done when
- A bite produces several small pushed commits on its branch, one Bing review of a fixed range, and one `--no-ff` merge on the protected branch, with no owner step unless an owner-affirm path was touched.
- A change made during review can't be shipped under the old review (SHA check).
- Direct commits to protected branches are refused.
- Tests cover: SHA mismatch blocks ship; prose "affirm" with verdict `changes-requested` does not ship; owner-affirm path blocks auto-ship; protected-branch commit refused; multi-repo ship order.
