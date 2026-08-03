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

| Mode | Surface |
|------|---------|
| General (default) | Ask, next attention, Classify/Handoff |
| Advanced | + Projects, Recent, Health |

Shared portfolio brain: `docs/canvas-snapshot.json` via `Get-MetraDeskPayload` (same snapshot as the Cursor canvas).
