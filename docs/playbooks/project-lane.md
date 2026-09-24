# Project lane (Metra Cursor Project continuity)

Metra-product continuous implement lane via the long-lived Cursor **Project**, with Porter transport and Handoff state. Does not replace Yarn Approve, Loom queue (when claimed), Inspect evidence, or operator Bing affirm.

## Triggers

- Metra Cursor Project implement / continuity
- Porter pack / OPEN-PLANS / Context sync
- `porter handoff` / DESK-HANDOFF / Pulse prepare-bing
- Dual-path Loom vs Project

## Authority (do not blur)

| Concern | Owner |
|---------|-------|
| Enrollment (Approve) | Surveyor / Yarn on Cursor `.plan.md` leaf |
| Queue when claimed | Loom |
| Continuity transport + handoff **file storage** | Porter |
| Handoff status semantics | Handoff concept (`awaiting-prepare-bing` / `ready-for-bing` / `cleared` / `stale`) |
| Evidence generation | Inspect (Pulse may invoke prepare-bing) |
| Ship judgment | Operator Bing affirm (or declared emergency skip) |

Porter coordinates state files; it does **not** authorize lifecycle, ship, or Bing.

## Dual-path

For an in-scope Metra stem:

- If Loom has an active item in `implementing` / `reviewing` / `completed` (not yet accepted): **Loom owns** - Project must not parallel-implement.
- If Loom has no active claim: **Project may implement**.

## Plan surfaces

| Surface | Role |
|---------|------|
| Cursor leaf | Enrollment + Approve |
| `porter/plans/<leaf>` | Byte-identical mirror (tracked after publish/commit; never hand-edit) |
| Context `/cursor/stores/self/docs/` | Continuity copy only |

## Implement prelude (Context sync mandate)

On Project implement start for a stem:

1. Read `porter/OPEN-PLANS.md` for that stem / leaf.
2. If a Porter mirror exists under `porter/plans/`, **overwrite** any Context docs plan body from that mirror (Porter wins on drift).
3. Do not treat Context-only docs as enrollment.
4. Do not archive or unpin Context docs as a chore - sync is enough.

## Formalize from Project chat

Project chat is not Approve. To enroll:

1. Save / synthesize a Cursor `.plan.md` leaf on the desk.
2. Surveyor Approve (content-bound marks).
3. Next Pulse/Daily scan enrolls; Porter transports Approved mirrors.

## Handoff freeze (code-complete)

After implement is code-complete:

```powershell
.\metra.ps1 porter handoff set -Stem <stem> [-Path <cursorLeaf.plan.md>]
```

Project **stops coding that stem** until `cleared` or `stale`. Complete ≠ shipped. `awaiting-prepare-bing` and `ready-for-bing` are not shipped.

## Automation to evidence-ready (human Bing only)

1. Pulse (after Porter) observes `awaiting-prepare-bing`.
2. Pulse invokes `inspect prepare-bing -Name Metra` via `porter prep` (soft-fail; never affirm).
3. On `readyForBing=true`, handoff advances to `ready-for-bing`.
4. Optional: Project cloud may also prepare-bing when engines work - still never affirm.
5. Operator reviews Bing pack and runs `inspect gate affirm` (or reject / emergency skip).
6. After ship / clear: `.\metra.ps1 porter handoff clear -Stem <stem>`.

Operator is **not** the prepare-bing button-pusher on the happy path.

## Desk hop (summary)

```text
Approve leaf -> Porter refresh/publish -> Project implement (Context sync)
  -> handoff set -> Pulse Inspect prep -> ready-for-bing
  -> operator Bing affirm -> git ship -> handoff clear
```

## Commands

```powershell
.\metra.ps1 porter refresh
.\metra.ps1 porter publish
.\metra.ps1 porter handoff show
.\metra.ps1 porter handoff set -Stem <stem>
.\metra.ps1 porter prep
.\metra.ps1 inspect prepare-bing -Name Metra
.\metra.ps1 inspect gate affirm -Name Metra -Confirm
```

## Related

- `docs/Cursor-Project-Metra-Charter.md`
- `porter/README.md`
- `docs/playbooks/yarn.md`, `loom.md`, `inspect-loop.md`
- `docs/Decisions.md` (2026-09-24 Porter / Project lane entries)
- Pattern (Loom concurrency only): `docs/patterns/loom/project-lane.md`
