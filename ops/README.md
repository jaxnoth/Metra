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
| **Motion** | Quiet bridges: Discuss, Capture (Save for portfolio), Put somewhere, Keep in view - move context without merging ledgers |

| Mode | Surface |
|------|---------|
| General (default) | Presence-first shared composer + compact/expandable Attention + recommendation result |
| Advanced | + Projects, Recent conversations + Captures, Health |

The primary surface stays presence-first even on loud days. Composer copy stays collaborative without slogan reuse (**Where should we start?**; quiet: toss me an idea; busy: discuss or type what you're thinking; placeholder: idea / question / rough draft). On mobile, Ask / Put somewhere always precedes a collapsed Attention count; wider screens open Attention by default. The shared text box does not merge systems: **Ask** calls the Ask API and journals a conversation; **Put somewhere** calls Place and returns a recommendation. Attachments are Place-only until Ask image intake ships. Recommendation-only trust copy remains visible beside the composer.

Shared portfolio brain: `docs/canvas-snapshot.json` via `Get-MetraDeskPayload` (same snapshot as the Cursor canvas).

## Ask + Capture HTTP contract (client-agnostic)

HTML Ops is the first client. Future native iOS (and phone browser over Tailscale) should use the same JSON APIs - no HTML-in-API, no browser-only protocol deps.

| Method | Path | Class | Notes |
|--------|------|-------|-------|
| GET | `/api/settings` | Settings | Portfolio roots (labeled list) + Ask key presence (never the key value). |
| PUT | `/api/settings` | Settings | Body: `roots: [{ name?, label, path, primary, optional }]` (preferred); legacy `primaryPath` / `personalPath` / `clearPersonal`; `cursorApiKey` / `clearCursorApiKey`. Operator machine only (loopback or `X-Metra-Local-Session`). |
| GET | `/api/updates` | Settings | Metra + Ollama update status (`?force=1` bypasses 24h cache). |
| POST | `/api/updates` | Settings | Body: `{ target: "metra" \| "ollama" }`. Operator-confirm apply only - never auto. Operator machine only. |
| POST | `/api/ask` | Ask | Body: `prompt`, optional `sessionId`, `recallSessionId`, `client`, `clientHint`. Header `X-Metra-Client`: `ops-web` \| `ops-ios` \| `cli`. Journals a turn (`turnIndex` within session). Returns `entry`, `message`, `handoff`, `sessionId`, `continuity` (summary / recent / recall flags). |
| GET | `/api/ask/journal` | Ask | Default: recent session summaries + turns. `?sessionId=` one session (Resume). `?q=` keyword search (episodic recall). |
| GET | `/api/capture` | Ask | List Capture Inbox (`?status=candidate\|all`). |
| POST | `/api/capture` | Ask | Create candidate. Ask: `{ turnId, sessionId? }`. Place: `{ source: place, text, homeId, placeId?, attachmentIds? }`. Manual: `{ summary }`. Sets `derivedFrom` once. |
| PATCH/POST | `/api/capture/{id}` | Ask | Update framing only - rejects `derivedFrom` mutation. |
| POST | `/api/capture/{id}/dismiss` | Ask | Status dismissed. |
| POST | `/api/capture/{id}/promote` | Ask (local homes) | Affirm into Future Development / Decision Registry candidate / OCC candidate. Never auto. |

CLI mirrors: `.\metra.ps1 ask sessions|log|get|recall`, `.\metra.ps1 capture list|note|promote|from-ask`.

**Ask continuity (Ops):** Advanced Recent offers **Resume** (reload journal turns into the Ask panel and keep `sessionId`) and **Recall into Ask** (arm `recallSessionId` for the next Ask as labeled evidence). Long sessions get an extractive Journal summary in engine context when older turns exceed the keep-recent window - not Capture, not silent memory soup.

## Route something (landing zone)

Accepts text, clipboard **Paste**, path references, and file **Attach** / drag-drop into a local quarantine (`%LOCALAPPDATA%\Metra\ops-place-quarantine\`). Metra recommends a durable home with Why and **What happens there** - nothing is created until you choose (Copy draft, Keep in view, Save for portfolio, or affirm for learning).

**Keep in view** parks on Attention. **Save for portfolio** creates a Capture Inbox candidate (pointers + framing) - distinct from Attention. Promote later on affirm.

Place learning lives in `docs/ops-place.local.json` (gitignored). Corrections via **This belongs in…** (Ask Where chip or Route) become Decision Registry candidates - never auto-promoted.

When `bindTailscale` is on, Ops start orchestrates Tailscale Serve so the share URL is `https://` (secure context for phone clipboard). Loopback Ops stays available without Serve. Funnel is out of scope.

## Next attention (attention memory)

The panel is **continuity**, not a task list. Metra remembers observations across snapshot builds in `docs/ops-attention.local.json` (local, gitignored).

| Concept | Meaning |
|---------|---------|
| Active | Observation still in view |
| Confidence | Fresh / Likely stale / Needs revalidation (affects ranking) |
| Why next | Why this item is surfaced now |
| Dismiss | Operator looked away - sticky until the underlying evidence changes |
| Snooze | Hide temporarily |
| Keep in view | Operator intention - temporary parking (not TicketTracker); same as Hold under the hood |
| Full re-scan | Only path that auto-closes missing covered observations |

Settings: **Attention visible count** (1-10) controls how many active items show before expanding. Keeping in view shows a quiet routing nudge toward a ticket or saved decision.

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

A full executable path in `editorCommand` (edit `docs/ops-preferences.local.json`) also works.

Guardrails: only existing folders inside a configured root or the Metra home may be opened, and the request must come from the operator machine (loopback or its own address) or carry a Host-issued `X-Metra-Local-Session`. Remote peers get a clear refusal and the path instead.
