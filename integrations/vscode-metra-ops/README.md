# Metra Ops VS Code / Cursor webview (Slice 7)

Embeds the HTML Ops desk and adds IDE affordances. **Does not write the workspace.** Apply still requires the Metra tray Host (**Apply once**).

## Install (Cursor or VS Code)

1. Start Metra Ops: `.\metra.ps1 host` (or Ops Start Menu shortcut).
2. In Cursor / VS Code: **Extensions: Install from Location...** and pick this folder:
   `integrations/vscode-metra-ops`
3. Command Palette: **Metra Ops: Open Desk**

Optional setting (User `settings.json`):

```json
{
  "metraOps.deskUrl": "http://127.0.0.1:7380/"
}
```

Use your Ops share URL when testing Tailscale bind (Slice 8). Session token for non-loopback mutate is read from `%LOCALAPPDATA%\\Metra\\ops-local-session.token` (issued by the Host).

## Bridge contract

Page -> host:

| type | purpose |
|------|---------|
| `bridgeHello` | page announces readiness |
| `askInChat` | open chat; tab title `{Project}: subject` |
| `openWorkspacePath` | reveal project path in OS |
| `copyText` | clipboard |
| `requestProposalApply` | HTTP `request-apply` only (never bare apply) |

Host -> page:

| type | purpose |
|------|---------|
| `surfaceReady` | surface + capabilities + optional sessionToken |
| `applyStatus` | status after request-apply |

Forbidden: `requestApply`, any host-side disk write.

## Browser without bridge

Opening the Ops URL in a normal browser still works. Resolve falls back to clipboard / in-page Ask / HTTP request-apply on loopback.
