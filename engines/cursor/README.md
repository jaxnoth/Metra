# Metra Ask Cursor engine (operator-tier)

Loopback sidecar implementing the Metra Ask contract:

- `GET /health`
- `POST /v1/complete`

Uses `@cursor/sdk` with the **local** runtime. Answer-only posture is enforced in the prompt wrapper.

```powershell
cd engines\cursor
npm install
$env:CURSOR_API_KEY = '...'   # or rely on User env
node .\server.mjs
```

Ops auto-starts this when `ask.enabled` + `ask.engine=cursor`, Node is on PATH, and `Get-MetraCursorApiKey` resolves. That auto-start is temporary until the installer ships Node + sidecar.
