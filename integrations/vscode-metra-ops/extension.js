// Metra Ops webview host (Slice 7). Plain JS for Cursor / VS Code-family without a build step.
// Page owns Resolve; this host adds IDE affordances. Disk apply stays on the Metra tray Host.

const vscode = require('vscode');
const fs = require('fs');
const http = require('http');
const path = require('path');
const os = require('os');

const FORBIDDEN_TYPES = new Set(['requestApply', 'apply']);

function getLocalSessionTokenPath() {
  return path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local'), 'Metra', 'ops-local-session.token');
}

function readLocalSessionToken() {
  try {
    const p = getLocalSessionTokenPath();
    if (fs.existsSync(p)) {
      return fs.readFileSync(p, 'utf8').trim();
    }
  } catch {
    /* ignore */
  }
  return '';
}

function fetchJson(urlPath, deskOrigin, method, body, sessionToken) {
  return new Promise((resolve, reject) => {
    const url = new URL(urlPath, deskOrigin);
    const payload = body ? Buffer.from(body, 'utf8') : null;
    const headers = {
      Accept: 'application/json',
    };
    if (payload) {
      headers['Content-Type'] = 'application/json';
      headers['Content-Length'] = String(payload.length);
    }
    if (sessionToken) {
      headers['X-Metra-Local-Session'] = sessionToken;
    }
    const req = http.request(
      {
        hostname: url.hostname,
        port: url.port || 80,
        path: url.pathname + url.search,
        method: method || 'GET',
        headers,
        timeout: 15000,
      },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          let json = null;
          try {
            json = text ? JSON.parse(text) : null;
          } catch {
            json = { raw: text };
          }
          resolve({ statusCode: res.statusCode || 0, body: json, text });
        });
      },
    );
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('timeout'));
    });
    if (payload) req.write(payload);
    req.end();
  });
}

function resolveDeskUrl(config) {
  const configured = (config.get('deskUrl') || '').trim();
  if (configured) return configured.replace(/\/?$/, '/');
  return 'http://127.0.0.1:7380/';
}

function formatTabTitle(project, subject) {
  const proj = (project || 'Metra').trim() || 'Metra';
  const short = String(subject || 'Ask')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 48) || 'Ask';
  return `${proj}: ${short}`;
}

/**
 * @param {vscode.ExtensionContext} context
 */
function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand('metraOps.openDesk', async () => {
      const config = vscode.workspace.getConfiguration('metraOps');
      const deskUrl = resolveDeskUrl(config);
      const sessionToken = readLocalSessionToken();

      const panel = vscode.window.createWebviewPanel(
        'metraOpsDesk',
        'Metra Ops',
        vscode.ViewColumn.Beside,
        {
          enableScripts: true,
          retainContextWhenHidden: true,
        },
      );

      panel.webview.html = getShellHtml(panel.webview, deskUrl);

      const postToIframe = (message) => {
        panel.webview.postMessage(message);
      };

      const surfaceReady = {
        type: 'surfaceReady',
        surface: 'vscode-webview',
        capabilities: {
          askInChat: true,
          openWorkspacePath: true,
          copyText: true,
          requestProposalApply: true,
        },
        sessionToken: sessionToken || undefined,
        deskUrl,
      };

      // Push readiness after the shell loads; also reply to bridgeHello.
      setTimeout(() => postToIframe(surfaceReady), 400);

      panel.webview.onDidReceiveMessage(async (message) => {
        if (!message || typeof message !== 'object') return;
        if (FORBIDDEN_TYPES.has(message.type)) {
          vscode.window.showErrorMessage('Metra Ops: forbidden bridge message (apply is Host-only).');
          return;
        }

        if (message.type === 'bridgeHello') {
          postToIframe(surfaceReady);
          return;
        }

        if (message.type === 'copyText') {
          await vscode.env.clipboard.writeText(String(message.text || ''));
          return;
        }

        if (message.type === 'openWorkspacePath') {
          const target = String(message.path || '').trim();
          if (!target) return;
          try {
            const uri = vscode.Uri.file(target);
            await vscode.commands.executeCommand('revealFileInOS', uri);
          } catch (err) {
            vscode.window.showWarningMessage(
              `Could not open path in OS explorer: ${err instanceof Error ? err.message : String(err)}`,
            );
            await vscode.env.clipboard.writeText(target);
          }
          return;
        }

        if (message.type === 'askInChat') {
          const project = String(message.project || 'Metra');
          const subject = String(message.subject || message.prompt || 'Ask');
          const prompt = String(message.prompt || '');
          const tabTitle = String(message.tabTitle || formatTabTitle(project, subject));
          panel.title = tabTitle;
          try {
            // Cursor / VS Code-family chat open - best effort.
            await vscode.commands.executeCommand('workbench.action.chat.open', {
              query: prompt,
              isPartialQuery: false,
            });
          } catch {
            await vscode.env.clipboard.writeText(prompt);
            vscode.window.showInformationMessage(
              `Ask prompt copied for chat tab "${tabTitle}". Paste into Chat.`,
            );
          }
          return;
        }

        if (message.type === 'requestProposalApply') {
          const proposalId = String(message.proposalId || '').trim();
          if (!proposalId) return;
          try {
            const token = sessionToken || readLocalSessionToken();
            const result = await fetchJson(
              `/api/proposals/${encodeURIComponent(proposalId)}/request-apply`,
              deskUrl,
              'POST',
              null,
              token,
            );
            const status = (result.body && result.body.status) || `HTTP ${result.statusCode}`;
            const resultMessage =
              (result.body && (result.body.resultMessage || result.body.error)) || undefined;
            postToIframe({
              type: 'applyStatus',
              proposalId,
              status: String(status),
              message: resultMessage ? String(resultMessage) : undefined,
            });
            if (result.statusCode >= 200 && result.statusCode < 300) {
              vscode.window.showInformationMessage(
                `Metra Ops: proposal ${proposalId} -> ${status}. Confirm Apply once in the Metra tray.`,
              );
            } else {
              vscode.window.showWarningMessage(
                `Metra Ops: request-apply failed (${result.statusCode}) ${resultMessage || ''}`.trim(),
              );
            }
          } catch (err) {
            postToIframe({
              type: 'applyStatus',
              proposalId,
              status: 'error',
              message: err instanceof Error ? err.message : String(err),
            });
          }
        }
      });
    }),
  );
}

/**
 * @param {vscode.Webview} webview
 * @param {string} deskUrl
 */
function getShellHtml(webview, deskUrl) {
  const csp = [
    `default-src 'none'`,
    `frame-src ${deskUrl} http://127.0.0.1:* http://localhost:* http://metra`,
    `script-src 'unsafe-inline' ${webview.cspSource}`,
    `style-src 'unsafe-inline' ${webview.cspSource}`,
  ].join('; ');

  const safeUrl = deskUrl.replace(/"/g, '&quot;');

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta http-equiv="Content-Security-Policy" content="${csp}" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Metra Ops</title>
  <style>
    html, body, iframe { margin: 0; padding: 0; width: 100%; height: 100%; border: 0; }
    body { background: #0f1720; }
  </style>
</head>
<body>
  <iframe id="desk" src="${safeUrl}" title="Metra Ops desk"></iframe>
  <script>
    const vscode = acquireVsCodeApi();
    const frame = document.getElementById('desk');

    window.addEventListener('message', (event) => {
      const data = event.data;
      if (!data || typeof data !== 'object') return;
      // From Ops desk iframe
      if (data.metraBridge || data.type === 'bridgeHello' || data.type === 'askInChat' ||
          data.type === 'openWorkspacePath' || data.type === 'copyText' ||
          data.type === 'requestProposalApply') {
        const { metraBridge, ...rest } = data;
        vscode.postMessage(rest);
        return;
      }
      // From extension host -> forward into iframe
      if (data.type === 'surfaceReady' || data.type === 'applyStatus') {
        try { frame.contentWindow.postMessage(data, '*'); } catch (e) { /* ignore */ }
      }
    });
  </script>
</body>
</html>`;
}

function deactivate() {}

module.exports = { activate, deactivate, formatTabTitle, FORBIDDEN_TYPES };
