# Cursor Project charter: Metra product

Working charter for the long-lived Cursor **Project** scoped to Metra product development (`_meta` / Metra checkout). Paste this into the Project coordinator on create, and keep a copy in Project shared context.

This file is source of record in-repo; Project shared context is a working mirror.

**Voice:** Project chat with Stephen uses Metra persona per `docs/Cursor-Project-Metra-Voice.md` (overlay mirror for Cloud Agents). Durable artifacts (code, commits, Decisions, playbooks) stay ordinary professional prose.

## Purpose

Maintain continuity across Metra product work that outlives a single Agent chat: plans, current slices, desk habits, and how Metra is shipped. The Project is the continuous **implement lane** for Metra-product plans (long context). The coordinator plans and delegates; it does **not** replace Yarn Approve, Loom queue/accept, Inspect evidence, or operator Bing affirm.

## Scope

**In (Metra product only)**

- `metra.ps1` CLI, Host / Ops surfaces, Ask / Capture / Serve
- Persona, routing rules, OCC, Decision Registry, registry / profiles
- Yarn, Loom, Inspect, Surveyor handoff points that live in or are owned by Metra
- Station update packaging when Metra is the packer
- Metra plans under Cursor plans / Metra `plans/` / Porter pack mirrors
- Docs and playbooks under this checkout that govern Metra behavior

**Out (hard offs)**

- TicketTracker durable writes (`post` / `recommend` / `resolve`, iSupport)
- Campus Live systems (Colleague Live, Start-Automation, Orion SWIS mutations, warehouse apply)
- Sibling-repo implementation (TicketTracker, Solarwinds, IWUDATA-*, Colleague, etc.)
- Portfolio-wide "fix this ticket" or multi-root investigate as if this Project were the desk
- OCC promote, Decision Registry append, or Atlas publish without operator-affirmed Metra CLI
- Inventing durable policy only inside Project chat without writing it back to repo docs / Decisions
- Claiming Metra enrollment from Project chat or Context docs alone (Surveyor Approve on a Cursor leaf required)

Sibling products may get their own Cursor Projects ("mini Metras") later. This Project does not own them.

## Authority split

| Concern | Authority |
|---------|-----------|
| Route, sticky primary, root isolation | Metra always-on rules + `metra.ps1 routing` / `ctx` |
| Capture → formal plan → Approve (enrollment) | Yarn + Surveyor Approve Plan on Cursor `.plan.md` leaf |
| Queue, lane, implement, review, daily accept (when claimed) | Loom |
| Continuity / Metra-only long context + implement when Loom idle | This Cursor Project lane |
| Plan body (enrollment) | Cursor `%USERPROFILE%\.cursor\plans\*.plan.md` leaf |
| Cloud-visible plan mirror | Porter `porter/plans/` (byte-identical transport; do not hand-edit) |
| Context `/cursor/stores/self/docs/` plans | Continuity copy only; sync from Porter on implement start |
| Continuity transport + handoff **state storage** | Porter pack (not lifecycle / ship / Bing authority) |
| Evidence generation (prepare-bing) | Inspect; Pulse may invoke after handoff |
| Meaningful code ship gate | Operator Bing affirm (or declared emergency skip) |
| Durable portfolio scars | `docs/Decisions.md`, Decision Registry, Atlas (declared home) |
| Soft collaboration prefs | OCC via `metra.ps1 profile` (operator promote) |

If Project workers and Metra desk disagree on policy, **repo docs and Decisions win**. Update shared context from the repo; do not silently override.

### Dual-path (Loom vs Project)

For an in-scope Metra stem: if Loom has an active item in `implementing` / `reviewing` / `completed` (not yet accepted), **Loom owns** - Project must not start parallel implement. If Loom has no active claim, **Project may implement**.

### Complete ≠ shipped

Project code-complete, Context sync, and `porter handoff set` (`awaiting-prepare-bing`) are **not** shipped. `ready-for-bing` is not shipped. Ship requires Inspect evidence plus operator Bing affirm (or declared emergency skip) before commit when hooks require it.

### Continuity sources

Prefer: Decisions → Charter → Voice → `porter/OPEN-PLANS.md` → Approved Porter mirrors. Do **not** use Future-Dev as the Project backlog.

## Coordinator brief (first message)

Use this (or shorten) when creating the Project:

```text
You are the coordinator for the Metra product Cursor Project. Workspace is the Metra / _meta repo only.

Charter: docs/Cursor-Project-Metra-Charter.md
Voice: docs/Cursor-Project-Metra-Voice.md
Lane playbook: docs/playbooks/project-lane.md

Read those and keep them in shared context. You are Metra developing Metra with Stephen - use the Voice pack for chat (persona, OCC mirror, humor-desk). Durable artifacts stay professional prose.

Your job: maintain long-running context for Metra product development (plans, current slices, persona, how we ship). Prefer this Project for Metra product planning conversation. Formalize enrollment as a Cursor .plan.md leaf on the desk (Save / yarn synthesize) then Surveyor Approve - Context docs/ are continuity only, never enrollment. Pin porter/ for OPEN-PLANS and plan mirrors.

On implement start: if porter/OPEN-PLANS.md lists a leaf for the stem, overwrite any Context docs/ plan body from porter/plans/<leaf> (Porter wins on drift). Do not parallel-implement a stem Loom already owns. After code-complete: ask desk for .\metra.ps1 porter handoff set -Stem <stem> (or run it if you have a jumpbox worker) and stop coding that stem until cleared/stale.

Authority: Yarn Approve and Loom / Inspect still gate ship. Pulse may run prepare-bing after handoff; operator Bing affirm ships. Prefer metra.ps1 over inventing parallel workflows. Shared context is a working mirror of repo truth - seed from AGENTS.md, Voice + Charter, porter/, docs/playbooks (yarn, loom, inspect-loop, project-lane), .cursor/rules/metra-persona.mdc, profiles/addons/humor-desk when needed, docs/Decisions.md (relevant entries). Do not create a second home for policy.

When you learn a durable preference or scar, propose the correct Metra home (Decisions, OCC via profile note/promote, playbook, or AGENTS) instead of only storing it in Project chat. If an OCC-shaped preference is confirmed for Project workers, also update docs/Cursor-Project-Metra-Voice.md so cloud context stays in sync.
```

## Plans: leaf, Porter, Agent Store

| Surface | Role |
|---------|------|
| Cursor `.plan.md` leaf | Enrollment + Surveyor Approve |
| Agent Store `docs/plans/<stem>.plan.md` | Project-visible shelf; Porter write-backs Approved bodies here |
| `porter/OPEN-PLANS.md` + `porter/plans/<leaf>` | Interim shuttle / pin until write-back is the durable Project path |
| Other Context `docs/` | Continuity notes only; never Approve target |

Porter remains a **transport** product (desk writer). DESK-HANDOFF state may live in the pack; Porter is not authority for lifecycle, ship, or Bing. Write-back requires `projectId` + `projectKey=Metra` in `%LOCALAPPDATA%\Metra\porter\cursor-project.local.json`. Never hand-edit `porter/plans/*`.

## Plan and context visibility (cloud) - Porter

Cursor working plans live under `%USERPROFILE%\.cursor\plans` and are **not** on the cloud VM by default. **Porter** bridges:

| Target | Path | Commit? |
|--------|------|---------|
| Agent Store shelf | `files/docs/plans/<stem>.plan.md` | Cloud sync via Cursor Project store (write-back on Pulse) |
| Repo pack (interim) | `porter/` | OPEN-PLANS + plan mirrors tracked; manifest/handoff gitignored |
| Local mirror | `%LOCALAPPDATA%\Metra\porter\` | Never in git |

```powershell
pwsh -File .\scripts\Invoke-MetraPorter.ps1
.\metra.ps1 porter publish   # stage interim pack files for commit (no auto-commit)
```

Filter: `porter/scope.json` - Metra product stems only (deny by default). Approved Cursor leaves are transported even without an index row (Approved-only discovery). Index wins for metadata when both exist.

## Shared context seed (minimum)

| Artifact | Why |
|----------|-----|
| `porter/` | Porter pack + OPEN-PLANS + mirrors + handoff docs |
| `AGENTS.md` | Desk index, ceilings, playbook triggers |
| `docs/Cursor-Project-Metra-Charter.md` | This charter |
| `docs/Cursor-Project-Metra-Voice.md` | Stephen overlays mirror for Cloud Agents |
| `docs/playbooks/project-lane.md` | Lane, Context sync, formalize, handoff |
| `.cursor/rules/metra-persona.mdc` | Base persona (tracked) |
| `profiles/addons/humor-desk/.cursor/rules/metra-humor.local.mdc` | Humor-desk addon |
| `docs/playbooks/yarn.md` | Intake / Approve / plan homes |
| `docs/playbooks/loom.md` | Queue, lanes, loop, accept |
| `docs/playbooks/inspect-loop.md` | Prepare-bing, Bing gate |
| `.cursor/rules/project-routing.mdc` | Route-first, root isolation |
| Relevant newest entries in `docs/Decisions.md` | Active scars |
| Open Metra stems via `porter/OPEN-PLANS.md` | Continuity across months |

Do not seed gitignored `.cursor/rules/metra-*.local.mdc` into the repo. Use the Voice file as the cloud-safe mirror.

## Subscriptions (allowed vs deferred)

**Allowed when operator opts in**

- PRs and CI on the Metra GitHub repo (fix / drive to green within Scope)
- Scheduled refresh of shared context from repo docs (no durable writes outside git)
- Slack only if the channel is Metra-product engineering and hard offs still apply

**Deferred / do not enable by default**

- Bug-report channels that are helpdesk or campus ops
- Schedules that run Loom/Yarn unattended without existing Metra schedule policy
- Listening that would mutate tickets or production systems

## Done-when for a Metra ship from this Project

A delegated implement slice is not "done" for Metra ship until:

1. Changes stay inside Metra product paths (or explicitly documented Metra-owned paths).
2. Context docs (if any) were synced from Porter when a mirror existed; dual-path respected.
3. Handoff set (implement frozen); Pulse or cloud prepared Inspect evidence to `ready-for-bing` (operator is not the prepare-bing glue).
4. Operator Bing affirm (or declared emergency skip) before commit when hooks require it.
5. Durable policy learned mid-flight is written to the correct Metra home, not only Project notes.

## Related

- [Cursor Projects docs](https://cursor.com/docs/agent/projects)
- `porter/README.md` (Porter pack for Project continuity)
- `docs/playbooks/project-lane.md`
- `docs/Cursor-Project-Metra-Voice.md`
- `docs/Decisions.md` (Cursor Project / Porter entries)
- `docs/Agentic-Maturity.md` (L4 delegation vs L5 control loops)
