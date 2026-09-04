# Metra Ops (HTML desk)

Primary Metra home screen for all users. Route-first by default; Advanced tabs opt-in in Settings.

## End users

No Node required. Prebuilt assets live in `dist/`.

```powershell
cd <Metra home>
.\metra.ps1 ops
```

Or use **Metra Ops** from the Start Menu / `Metra-Ops.cmd`.

## Contributors

```powershell
cd ops
npm install
npm run build
```

Dev loop:

```powershell
# Terminal A
.\metra.ps1 ops -NoBrowser

# Terminal B
cd ops
npm run dev
```

Vite proxies `/api` to `http://127.0.0.1:7380`.

## Layout

One desk, three layers (see Decisions **Ops desk three-layer model**). Separate systems; shared awareness and handoffs - not one Observation Desk inbox.

| Layer | Job |
|-------|-----|
| **Awareness** | Metra presence + one truthful observation; updated time stays quiet, waiting / held counts live on expandable Attention |
| **Work surface** | One shared composer with explicit **Ask** and **Put somewhere** destinations; **Attention** remains a separate expandable reality-claim surface |
| **Motion** | Quiet bridges that move context without merging ledgers |

| Motion | Success condition | Ledger |
|--------|-------------------|--------|
| Discuss | Operator has enough context to decide next move | Ask / conversation only |
| Save for portfolio | Captured as durable project memory or artifact | Capture |
| Put somewhere | Routed to a deliberate destination | Place / Put |
| Keep in view | Remains visible for operator attention without becoming a task | Attention |

Motion handoffs do not merge ledgers. Attention, Ask, and Place remain separate surfaces with explicit operator intent between them.

| Mode | Surface |
|------|---------|
| General (default) | Presence-first shared composer + compact/expandable Attention + recommendation result |
| Advanced | + Projects, Recent conversations + Captures, Health |

The primary surface stays presence-first even on loud days. Composer copy stays collaborative without slogan reuse (**Where should we start?**; quiet: toss me an idea; busy: discuss or type what you're thinking; placeholder: idea / question / rough draft). On mobile, Ask / Put somewhere always precedes a collapsed Attention count; wider screens open Attention by default. The shared text box does not merge systems: **Ask** calls the Ask API and journals a conversation; **Put somewhere** calls Place and returns a recommendation. Attachments are Place-only until Ask image intake ships. Recommendation-only trust copy remains visible beside the composer.

Shared portfolio brain: `%LOCALAPPDATA%\Metra\desk\canvas-snapshot.json` via `Get-MetraDeskPayload` (same snapshot as the Cursor canvas).

## Ask + Capture HTTP contract (client-agnostic)

HTML Ops is the first client. Future native iOS (and phone browser over Tailscale) should use the same JSON APIs - no HTML-in-API, no browser-only protocol deps. Same-origin only - no wildcard CORS. **Local authority** (operator machine or `X-Metra-Local-Session`) gates mutations listed in [SECURITY.md](../SECURITY.md); **Ask-class** endpoints stay reachable over Tailscale for view/ask/capture intake.

| Method | Path | Class | Notes |
|--------|------|-------|-------|
| GET | `/api/settings` | Settings | Portfolio roots (labeled list) + Ask key presence (never the key value). |
| PUT | `/api/settings` | Settings | Body: `roots: [{ name?, label, path, primary, optional }]` (preferred); legacy `primaryPath` / `personalPath` / `clearPersonal`; `cursorApiKey` / `clearCursorApiKey`. Operator machine only (loopback or `X-Metra-Local-Session`). |
| GET | `/api/profile/status` | Settings | Profile Sync fingerprint. Same-machine, local-session, device token, or break-glass `X-Metra-Profile-Sync`. Local authority also gets `satellites`, `devices`, `pairPending`, `clientAuthConfigured`. |
| GET | `/api/profile/satellites` | Settings | Satellite roster (local authority only). |
| GET | `/api/profile/devices` | Settings | Paired devices (local authority). `?includeRevoked=1` optional. |
| POST | `/api/profile/devices/{id}/revoke` | Settings | Revoke one device (local authority). |
| POST | `/api/profile/pair` | Satellite | Tailscale WhoIs pair; returns device token or `{ pending, requestId }` (202). |
| GET | `/api/profile/pair/pending` | Settings | Pending pair requests (local authority). |
| POST | `/api/profile/pair/approve` | Settings | Body `{ requestId }`. Adds allowlist + mints device token (local authority). |
| GET | `/api/profile/export` | Settings | Profile zip via `Export-MetraProfile` (optional cache by hash). Same auth as status. |
| POST | `/api/profile/issue-sync-token` | Settings | Break-glass bearer (plaintext once). Body optional `{ rotate: true }`. Local authority only. Prefer Tailscale pair. |
| GET | `/api/updates` | Settings | Metra + Ollama update status (`?force=1` bypasses 24h cache). |
| POST | `/api/updates` | Settings | Body: `{ target: "metra" \| "ollama" }`. Operator-confirm apply only - never auto. Operator machine only. |
| POST | `/api/ask` | Ask | Body: `prompt`, optional `sessionId`, `recallSessionId`, `client`, `clientHint`. Header `X-Metra-Client`: `ops-web` \| `ops-ios` \| `cli`. When `client-auth.local.json` allowlist is configured, remote (non-local-authority) callers need allowlisted WhoIs. |
| GET | `/api/ask/journal` | Ask | Default: recent session summaries + turns. `?sessionId=` one session (Resume). `?q=` keyword search (episodic recall). |
| GET | `/api/capture` | Ask | List Capture Inbox (`?status=candidate\|all`). |
| POST | `/api/capture` | Ask | Create candidate. Ask: `{ turnId, sessionId? }`. Place: `{ source: place, text, homeId, placeId?, attachmentIds? }`. Manual: `{ summary }`. Sets `derivedFrom` once. |
| PATCH/POST | `/api/capture/{id}` | Ask | Update framing only - rejects `derivedFrom` mutation. |
| POST | `/api/capture/{id}/dismiss` | Ask | Status dismissed. |
| POST | `/api/capture/{id}/promote` | Ask (local homes) | Affirm into Future Development / Decision Registry candidate / OCC candidate. Never auto. |
| POST | `/api/watch/tickets` | Attention | Mine-scope TicketWatch scan into Attention (`Invoke-MetraTicketWatchScan`). Returns `{ ok, watch, desk }`. No iSupport writes. Optional body `{ draft: true }` for local TT notes only. |
| POST | `/api/watch/recommend` | Attention | M3 Affirm A: `{ id, preview?, confirm?, force?, minutes? }`. Preview writes local `recommend-draft`. Confirm calls TT recommend (store-as-review). Mine-eligible + E1 recommendable unless force. Never resolve. Returns `{ ok, store, desk }`. |

CLI mirrors: `.\metra.ps1 ask sessions|log|get|recall`, `.\metra.ps1 capture list|note|promote|from-ask`.

**Ask continuity (Ops):** Advanced Recent offers **Resume** (reload journal turns into the Ask panel and keep `sessionId`) and **Recall into Ask** (arm `recallSessionId` for the next Ask as labeled evidence). Long sessions get an extractive Journal summary in engine context when older turns exceed the keep-recent window - not Capture, not silent memory soup.

## Route something (landing zone)

Accepts text, clipboard **Paste**, path references, and file **Attach** / drag-drop into a local quarantine (`%LOCALAPPDATA%\Metra\ops-place-quarantine\`). Metra recommends a durable home with Why and **What happens there** - nothing is created until you choose (Copy draft, Keep in view, Save for portfolio, or affirm for learning).

**Keep in view** parks on Attention. **Save for portfolio** creates a Capture Inbox candidate (pointers + framing) - distinct from Attention. Promote later on affirm.

Place learning lives in `%LOCALAPPDATA%\Metra\ops\place.json` (gitignored). Corrections via **This belongs in…** (Ask Where chip or Route) become Decision Registry candidates - never auto-promoted.

When `bindTailscale` is on, Ops start orchestrates Tailscale Serve so the share URL is `https://` (secure context for phone clipboard). Loopback Ops stays available without Serve. Funnel is out of scope.

## Next attention (attention memory)

The panel is **continuity**, not a task list. Metra remembers observations across snapshot builds in `%LOCALAPPDATA%\Metra\ops\attention.json` (local, gitignored).

| Concept | Meaning |
|---------|---------|
| Active | Observation still in view |
| Confidence | Fresh / Likely stale / Needs revalidation (affects ranking) |
| Why next | Why this item is surfaced now |
| Dismiss | Operator looked away - sticky until the underlying evidence changes |
| Snooze | Hide temporarily |
| Keep in view | Operator intention - temporary parking (not TicketTracker); same as Hold under the hood |
| Full re-scan | Only path that auto-closes missing covered observations |

Settings: **Attention visible count** (1-10) controls how many waiting **summary rows** show before **Show all**. Overflow stays in a capped scroll region of compact rows; the desk always renders **exactly one** focused detail card. Preference values fail closed (default 1; clamp 1-10). Keeping in view stays the existing one-card picker and shows a quiet routing nudge toward a ticket or saved decision. On compact viewports the presence shell (mark + observation + Ask/Put composer) stays sticky above Attention so denser waiting lists do not bury Ask.

**Attention actions:** **Portfolio refresh** (non-ticket `coveredKinds` only - git/drift/verify/decision/contract) and **Scan tickets** (ticket only via `POST /api/watch/tickets`). **Ticket Watch** toggle gates Scan tickets. Portfolio never covers tickets. Optional M2: set `autoAnalyze: true` in `%LOCALAPPDATA%\Metra\ticket-watch.local.json` so Scan tickets / `watch tickets` runs TicketTracker `analyze` (local draft) for Added/Refreshed; `-Draft` forces analyze; Unchanged never re-analyzes. Optional assess: set `autoAssess: true` (and optional `assessMaxAgeHours`) so Added/Refreshed get TicketTracker `assess -DraftRecommend` (local only; skips fresh artifacts); assess prefers over analyze for the same ticket; Attention may show assess gate / needs-clarify. Desk shows **Draft available** - not a recommendation. Optional E1: set `evidenceRouter: true` to append **Next evidence** (or **Ready for recommendation** / Evidence appears sufficient) after analyze - never a likely solution, never auto iSupport recommend. **M3:** ticket Attention detail offers **Preview recommendation** (local `recommend-draft`) and **Write recommendation** (Affirm A TT recommend; supersedes). CLI: `.\metra.ps1 watch recommend <id> -Preview|-Confirm [-Force]`. Confirm-gated assess write: `.\TicketTracker.ps1 assess <id> -Recommend -Confirm -Minutes <n>` (or `-Preview`). `autoStoreRecommend` stays false. Affirm B (resolve/close) stays out of TicketWatch. Requires TicketTracker `meFilter` (empty filter fails closed). CLI `.\metra.ps1 watch tickets` is independent of the desk preference.

Default card copy is plain language (what / why / what to do). Advanced desk adds the technical detail strip, CLI command, and path.

## Open in editor

The browser cannot launch programs, so the desk process opens the project folder for you. Order: IDE bridge when the desk runs inside Cursor, then `POST /api/open` on the desk, then clipboard fallback.

Settings: **Editor** picks what gets launched.

| Value | Launches |
|-------|----------|
| `auto` (default) | Cursor if installed, else VS Code, else the Windows default handler |
| `cursor` | Cursor (falls back to the Windows default when not installed) |
| `code` | VS Code |
| `system` | Windows default handler for the folder |

`editorCommand` may also be a custom executable path (edit `%LOCALAPPDATA%\Metra\ops\preferences.json`). That is intentional - Open in editor can launch a non-Cursor/VS Code app the operator configured. A missing custom path falls back to the Windows default handler (Explorer) so Open still means "take me there."

Guardrails: only existing folders inside a configured root or the Metra home may be opened. Locality prefers loopback and a validated Host-issued `X-Metra-Local-Session` over raw IP ownership; Serve-proxied requests do not inherit loopback authority. Remote peers get a clear refusal and the path instead.
