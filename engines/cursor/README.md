# Metra Ask Cursor engine (premium path)

Loopback sidecar implementing the Metra Ask contract:

- `GET /health`
- `POST /v1/complete`

Uses `@cursor/sdk` with the **local** runtime. Answer-only posture is enforced in the prompt wrapper.

**Model default:** Cursor Router **Auto Cost** (`auto-smart` + `optimize_for=cost`) - legacy Auto behavior on the Cursor Models pool. Prefer this over Auto Balance when Other Models quota is tight (Balance bills routed models and can exhaust Other Models). Pin overrides remain available via `ask.cursor.model` / `.\metra.ps1 ask engine set cursor -Model <id>` (aliases: `auto-cost`, `auto-balance`, `auto-intelligence`).

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
