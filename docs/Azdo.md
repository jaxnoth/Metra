# Azure DevOps remote evidence

Read-only Azure DevOps REST access from Metra (`.\metra.ps1 azdo ...`). No clones, no writes, no routing input from gap output.

## Setup

1. Copy `docs/examples/azdo.local.example.json` to `%LOCALAPPDATA%\Metra\azdo.local.json` (gitignored).
2. Set `organization` (required). Optional `project` limits repo inventory to one AzDO project.
3. Authenticate with a PAT (precedence: **Process** `METRA_AZDO_PAT`, then **User**, then **Machine**, then `"pat"` in local JSON):

REST uses `api-version=7.1`. Each repo's **default branch** is resolved from the Repos API (never hardcoded `main`).

## Commands

| Command | Purpose |
|---------|---------|
| `azdo status` | Config/auth readiness |
| `azdo repos` | Bounded repo inventory |
| `azdo get -Project X -Repo Y -ItemPath README.md` | Single file on default branch (size-capped). Use `-ItemPath` (aliases: `-File`, `-RepoPath`). Do not use metra.ps1 `-Path` (filesystem collision). |
| `azdo gaps` | Map AzDO repos vs Metra registry + disk |
| `azdo tree -Project X -Repo Y [-Path /folder]` | Bounded tree (caps enforced) |
| `azdo search "query" [-Project X] [-Repo Y]` | Code Search when available |
| `azdo ideas [-Topic "..."] [-OutFile path]` | Pasteable coworker draft from Experience/Ethos repos |

Examples:

```powershell
.\metra.ps1 azdo status
.\metra.ps1 azdo gaps
.\metra.ps1 azdo get -Project PowerShell -Repo Colleague -ItemPath AGENTS.md
.\metra.ps1 azdo ideas -Topic "Experience card ideas for financial aid"
```

## Registry overrides

Optional on `projects.local.json` entries:

```json
"azdoProject": "PowerShell",
"azdoRepo": "Colleague",
"remoteUrl": "https://dev.azure.com/org/project/_git/Colleague"
```

Heuristic name match is fallback only. Names normalize case-insensitively with spaces/hyphens/underscores collapsed.

## Gap buckets

| Bucket | Meaning |
|--------|---------|
| `InAzdoNotInRegistry` | Remote repo with no **Metra registry** match (not blocked from `get` / `search`) |
| `InRegistryMissingCheckout` | Registry entry without on-disk folder (may still exist in AzDO) |
| `MatchedPresent` | Registry + checkout present |
| `MatchedPossiblyStale` | Checkout present; local HEAD differs from remote default-branch tip (report only) |

`gaps` compares AzDO to the **portfolio registry** for visibility. It does not deny access. `azdo get`, `azdo tree`, and `azdo search` can reach any repo your PAT allows - by project+repo name (direct REST) or org-wide Code Search - even when a repo is "not in registry" or beyond the bounded `repos`/`gaps` inventory cap (`maxRepos`).

Last gap summary is cached under `%LOCALAPPDATA%\Metra\azdo\gaps-latest.json`. `.\metra.ps1 coverage` prints an advisory line from that cache (visibility only - not a score, not routing input).

## Bounded retrieval

Caps in `%LOCALAPPDATA%\Metra\azdo.local.json` (defaults in example file) are enforced on every command. Oversize `get` responses truncate; oversize `tree` fails closed with a clear cap message.

| Cap | Operator default | Ask evidence |
|-----|------------------|--------------|
| File read | `maxFileChars` (120000) | `maxAskFileChars` (16000), then Ask item cap |
| Code search hits | `maxSearchHits` (25) | `maxAskSearchHits` (3), repo-scoped only |
| Repo inventory | `maxRepos` (200) | Advisory for `repos`/`gaps` only; `get`/`tree` use exact project+repo direct REST |

`maxRepos` does **not** block direct repo access when project and repo names are known exactly.

## Ask integration (v1.1)

Ask may add `azdo` evidence items when:

- Routed project has no local checkout (or unreadable AGENTS.md), **or**
- Operator passes `-Remote` to Ask, **or**
- Prompt matches remote keywords (`production`, `devops`, `azure devops`, `experience`, `latest`, `remote repo`)

Local AGENTS/file evidence stays authoritative when checkout is present unless `-Remote` or a keyword gate fires. AzDO is additive, never silent replacement.

Ask AzDO flow: route project → ambiguity check → resolve exact repo → README/AGENTS → optional **repo-scoped** code search (never org-wide before repo resolution).

Ambiguous repo match (multiple plausible repos, no `azdoRepo` / `-Repo`) fails closed:

`Ambiguous Azure DevOps target. Use -Repo or refine routing.`

## Ideas (v1.2)

`azdo ideas` gathers paths from repos matching `ideaRepoNamePatterns` (default `*Experience*`, `*Ethos*`), uses Code Search or Items fallback, then Ask for a flat coworker-voice markdown draft. Optional `-OutFile` defaults to cache under `%LOCALAPPDATA%\Metra\azdo\`. No Capture, no M365 send.

## Hard offs

No clone/sparse-checkout, no PR/wiki/commit writes, no registry auto-edit from gaps, no TicketWatch changes.

See also: [Integrations.md](Integrations.md), [Decisions.md](Decisions.md).
