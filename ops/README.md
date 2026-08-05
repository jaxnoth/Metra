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

Three peer panels (do not blend):

| Panel | Job |
|-------|-----|
| **Ask** | Help me think or do |
| **Next attention** | Metra noticed something |
| **Route something** | Help me find the right home |

| Mode | Surface |
|------|---------|
| General (default) | Ask, Next attention, Route something |
| Advanced | + Projects, Recent, Health |

Shared portfolio brain: `docs/canvas-snapshot.json` via `Get-MetraDeskPayload` (same snapshot as the Cursor canvas).

## Route something (landing zone)

Accepts text, clipboard **Paste**, path references, and file **Attach** / drag-drop into a local quarantine (`%LOCALAPPDATA%\Metra\ops-place-quarantine\`). Metra recommends a durable home with Why and **What happens there** - nothing is created until you choose (Copy draft, Keep in view, or affirm for learning).

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
