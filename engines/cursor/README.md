# Metra Ask Cursor engine (premium path)

Loopback sidecar implementing the Metra Ask contract:

- `GET /health`
- `POST /v1/complete`

Uses `@cursor/sdk` with the **local** runtime. Answer-only posture is enforced in the prompt wrapper.

**Model default:** Cursor Router **Auto Cost** (`auto-smart` + `optimize_for=cost`) when the API key supports it. Keys that cannot use `auto-smart` are adapted at runtime to `default` / another catalog id. Concrete pins such as Inspect `gemini-3.7-flash` are valid on personal and team keys when listed in `Cursor.models.list()`; only true "cannot use this model" responses trigger one create/run fallback. Auth/session errors are surfaced as key problems (not as model unavailability). Pin overrides: `ask.cursor.model` / `inspect.cursor.model` / `.\metra.ps1 ask engine set cursor -Model <id>` (aliases: `auto-cost`, `auto-balance`, `auto-intelligence`; concrete ids: `default`, `gemini-3.7-flash`, `composer-2.5`, …). Ask sidecar spawn prefers the User-scope `CURSOR_API_KEY` when set so `.\metra.ps1 ask key set` wins over a stale team key in the IDE process.

Secrets scrub (defense in depth): the sidecar mirrors Metra's high-signal secret patterns on inbound prompt/context and outbound message. PowerShell (`AskSecrets.ps1` + journal write) remains authoritative - do not treat the Node mirror as the only gate.

## Consumer packaging (ladder 1)

Cursor Ask must be **turnkey** when selected - do **not** document "install Node yourself."

| Component | Location |
|-----------|----------|
| Private Node | `runtimes/node/node.exe` (preferred over PATH) |
| Sidecar + deps | `engines/cursor` with `node_modules` prebundled |
| API key | User-scope `CURSOR_API_KEY` via `.\metra.ps1 ask key set` |

Installer staging allows `engines/cursor/node_modules` and `runtimes/node`. Local Ollama Ask does **not** need this stack. If `runtimes/node` is missing in a checkout, `Get-MetraAskNodePath` falls back to PATH Node (operator desks); treat missing private Node in installer builds as a **bug**, not an open ladder-1 product bite.

```powershell
# Operator/dev only when private Node is absent:
cd engines\cursor
npm install
$env:CURSOR_API_KEY = '...'   # or ask key set
# Prefer: Start-MetraAskEngine (uses Get-MetraAskNodePath)
```

Ops auto-starts the sidecar when `ask.engine=cursor` and Node + deps + key are ready.

**SDK pin:** `@cursor/sdk` is pinned to **1.0.26** (exact; see `package-lock.json`). Versions **1.0.27+** (including 1.0.30) access-violated during local Agent runs on Windows operator desks - do not bump without a live `POST /v1/complete` smoke. After pull, refresh local deps with `npm ci` under `engines/cursor`. Installer packaging uses `packaging/Stage-MetraCursorAsk.ps1` (`npm ci` when lockfile present). Do not commit `node_modules`.

**Health:** `GET /health` `ok` means operationally usable (consecutive SDK run errors under threshold 2), not merely that the process is listening.

## Evidence context contract (ladder 2)

`POST /v1/complete` accepts a `context` object. PowerShell builds it via `New-MetraAskEvidencePack` before the call. Prefer structured fields; flat aliases remain for cutover.

| Field | Role |
|-------|------|
| `route` | Classify handoff (`where`, `what`, `why`, `forWhom`, `next`, `score`) |
| `evidence.quality` | `adequate` \| `thin` \| `none` (code-computed; not model vibes) |
| `evidence.items[]` | Bounded excerpts (`kind`, `label`, `source`, `excerpt`, `confidence`, `factualSupport`) |
| `evidence.limits` | Locked ceilings: `maxItems=6`, `maxCharsPerItem=400`, `maxTotalChars=2400` |
| `continuity` | Journal summary / recent turns / recall - continuity only unless an item is factual |
| `capability` | `status` (`normal` \| `degraded` \| `unsupported`) + optional `reason` |
| Flat aliases | `where`, `what`, `why`, `forWhom`, `next`, `score`, `sessionSummary`, `recentTurns`, `forceContinuity` |

`buildPrompt` honors `evidence.quality`:

- `thin` / `none` - provisional posture; forbid inventing live Orion/iSupport/host status; prefer one concrete next check
- `adequate` - ground claims in evidence items; journal still not factual unless marked

Honesty short-circuits (`greeting` / `observation` / `park`) never reach this sidecar. Engine-path desk semantics: `answered=true` only when `answerType=grounded`; thin/none cannot ground.

Stable endpoints stay `GET /health` and `POST /v1/complete` - no new routes for the evidence bag.
