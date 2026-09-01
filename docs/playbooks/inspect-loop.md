---
metraMemory: procedural
defaultContext: false
loadWhen:
  - inspect
  - inspect loop
  - inspect pack
  - Bing comparison
  - ship calibration
ceiling:
  - Fail closed when Ask engine unavailable
  - Bing affirm is the operator manual gate before commit; agent auto-fixes during prepare-bing
---

> Moved from `AGENTS.md` during A2 desk split. Preserve A1 done-when / On hard stop content unless intentionally revised.

# Inspect coding loop

Inspect is the default **coding loop** for meaningful implementation work: observe with CLI, recommend in chat, operator affirms fixes, re-inspect until ship-ready. It is advisory only - never modifies source, plans, Decisions, or registry data.

Always-on rule: [`.cursor/rules/metra-inspect-loop.mdc`](../../.cursor/rules/metra-inspect-loop.mdc).

## Coding loop (default for agents)

| Phase | Command | Gate |
|-------|---------|------|
| After every plan revision | `.\metra.ps1 inspect pack-only plan <fragment-or-Path> -Name <Project>` | Agent runs automatically; report pack path + clipboard. Skip only on explicit operator opt-out |
| Before implement (plan-driven work) | `.\metra.ps1 inspect plan -Latest -Name <Project>` (or fragment / `-Path`) | Optional Ask assess; summarize findings in chat; operator picks fix / defer / reject before coding |
| After each coherent code batch | `.\metra.ps1 inspect prepare-bing -Name <Project> -Reset` then fix and re-run until `readyForBing=true` | Agent auto-fixes Critical/High/Medium; pack built when loop completes |
| Before `git commit` | Operator Bing review + `inspect gate affirm` | **Only manual gate**; hook blocks without affirm |
| After affirmed fixes | `inspect loop` again (same session) | Stop when goal met (Critical=0, High=0, Medium<=2), convergence detected, or MaxLoops=5 fence |
| Metra executable ship (calibration) | `prepare-bing` auto-builds pack; Bing comparison lane | Re-run prepare-bing after fixes; pack is never manual |
| A2 desk split external review | `.\metra.ps1 inspect pack-only agents -Name <Project>` | Bing-only stub + playbooks scope; no unrelated working-tree noise |

Skip the loop for ticket-ops-only turns, brainstorm/plan-without-implement, or when the Ask engine is unavailable (fail closed; do not invent findings). Low/Info are optional unless the operator wants them addressed.

**Goal-based review loop** (`inspect loop`): success is severity reduction to done-when (Critical=0, High=0, Medium<=2), not a fixed turn count. MaxLoops=5 is runaway protection only. Grade (A-D) is informational. Session state: `%LOCALAPPDATA%\Metra\inspect\<Project>\review-loop.json`; completed metrics append to `review-loop-history.jsonl`.

Verify regression is fingerprint- and touch-set-based: revert when Critical rises globally, High rises among files touched by the affirmed package (or changed since baseline), Medium population rises in the touch set after ignoring brand-new Medium findings (LLM churn), or an affirmed High/Critical issue remains. Whole-tree High/Medium count increases alone do not revert. Manifest-only restore is unchanged. Incompatible legacy baselines (missing/unsupported fingerprint version) invalidate the cycle without restore - re-assess to continue.

Stop conditions: goal achieved; convergence (unchanged counts two rounds); MaxLoops reached (not success); operator ship / good enough. The CLI assesses; the **agent auto-fixes** during `prepare-bing`; **`inspect pack`** runs when the loop session completes.

## Engine independence

Inspect findings are strongest when implementation and review use different model families or providers (`.\metra.ps1 ask engine show` for Metra Inspect vs the Cursor Agent model).

| Setup | Use |
|-------|-----|
| **Preferred** | Cursor Agent on a Cursor-hosted model; Metra Inspect on Ollama (`ask.engine`) |
| **Quota constraints** | Cursor Agent on Ollama model A; Metra Inspect on Ollama model B |
| **Same engine family** | Inspect is first-pass only; ship needs chat affirmation, tests/verify, pack, Bing, or other external evidence |

Independence of review matters more than the specific model. The safety net is inspect + verify + operator judgment, not any single LLM.

## Commands

```powershell
.\metra.ps1 inspect
.\metra.ps1 inspect -Name Metra
.\metra.ps1 inspect prepare-bing -Name Metra
.\metra.ps1 inspect prepare-bing -Name Metra -Reset
.\metra.ps1 inspect gate affirm -Name Metra
.\metra.ps1 inspect -Name Metra -WhatIf
.\metra.ps1 inspect -Name Metra -Base HEAD~1
.\metra.ps1 inspect plan
.\metra.ps1 inspect plan -Latest -Name Metra
.\metra.ps1 inspect plan <filename-fragment> -Name Metra
.\metra.ps1 inspect pack
.\metra.ps1 inspect pack plan
.\metra.ps1 inspect pack-only -Name Metra
.\metra.ps1 inspect pack-only agents -Name <Project>
.\metra.ps1 inspect pack-only plan -Latest -Name Metra
```

- Default diff (no `-Base`) includes unstaged + staged + untracked text files (scope-reducer still skips secrets/binaries/lockfiles).
- `-Base <rev>` is three-dot `Base...HEAD` only; local working-tree edits are not included (yellow warning when dirty).
- `-WhatIf` skips the Ask engine after scope reduce.
- Pack rebuilds scrubbed appendix bodies from current disk; findings stay from the assessed report (stale warning when inputHash differs).
- During calibration, Bing remains the required comparison lane for **Metra executable** changes.
- A2 `pack-only agents` packs `AGENTS.md` + `docs/playbooks/*.md` only for external desk-split review.

## Token economy (Agent vs Bing)

| Artifact | Consumer | Path |
|----------|----------|------|
| Fix queue + latest report | Cursor Agent (implement/verify) | `%LOCALAPPDATA%\Metra\inspect\<Project>\fix-queue.json`, `latest.json` |
| Diff pack | Bing / operator review only | `%LOCALAPPDATA%\Metra\inspect\<Project>\pack-diff.md` (Track I; legacy root `pack-diff.md` until migrated) |
| Plan pack | Bing / operator review only | `%LOCALAPPDATA%\Metra\inspect\<Project>\pack-plan.md` (Track I; legacy root `pack-plan.md` until migrated) |

Parallel products: each `-Name <Project>` owns its slot — serial or concurrent work does not overwrite another product's pack.

- `.\metra.ps1 inspect budget -Name <Project>` — no engine call; estimates prompt payload chars and band before inspect.
- Round 1 assess: full collapsed reduced diff. Verify rounds: touch-set bodies only; outside paths are names-only indicators.
- Rename collapse (`git-rename`, `suffix-pair`) runs before the file cap; ambiguous pairs stay uncollapsed.
