# Metra Ask Cursor engine (premium path)

Loopback sidecar implementing the Metra Ask contract:

- `GET /health`
- `POST /v1/complete`

Uses `@cursor/sdk` with the **local** runtime. Answer-only posture is enforced in the prompt wrapper.

Secrets scrub (defense in depth): the sidecar mirrors Metra's high-signal secret patterns on inbound prompt/context and outbound message. PowerShell (`AskSecrets.ps1` + journal write) remains authoritative - do not treat the Node mirror as the only gate.

## Consumer packaging (ladder 1)

Cursor Ask must be **turnkey** when selected - do **not** document "install Node yourself."

| Component | Location |
|-----------|----------|
| Private Node | `runtimes/node/node.exe` (preferred over PATH) |
| Sidecar + deps | `engines/cursor` with `node_modules` prebundled |
| API key | User-scope `CURSOR_API_KEY` via `.\metra.ps1 ask key set` |

Installer staging allows `engines/cursor/node_modules` and `runtimes/node`. Local Ollama Ask does **not** need this stack.

```powershell
# Operator/dev only when private Node is absent:
cd engines\cursor
npm install
$env:CURSOR_API_KEY = '...'   # or ask key set
# Prefer: Start-MetraAskEngine (uses Get-MetraAskNodePath)
```

Ops auto-starts the sidecar when `ask.engine=cursor` and Node + deps + key are ready.
