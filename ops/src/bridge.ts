/**
 * Metra Ops IDE webview bridge (Slice 7).
 * Page owns Resolve; host adds IDE affordances. Host still owns disk apply.
 * Graceful degrade: when no bridge, callers fall back to HTTP / clipboard.
 */

export type BridgeSurface = 'vscode-webview' | 'browser'

export type BridgeCapabilities = {
  askInChat: boolean
  openWorkspacePath: boolean
  copyText: boolean
  requestProposalApply: boolean
}

export type SurfaceReadyMessage = {
  type: 'surfaceReady'
  surface: BridgeSurface
  capabilities: BridgeCapabilities
  sessionToken?: string
  deskUrl?: string
}

export type ApplyStatusMessage = {
  type: 'applyStatus'
  proposalId: string
  status: string
  message?: string
}

export type HostToPageMessage = SurfaceReadyMessage | ApplyStatusMessage

export type PageToHostMessage =
  | { type: 'bridgeHello' }
  | { type: 'askInChat'; project: string; subject: string; prompt: string; tabTitle: string }
  | { type: 'openWorkspacePath'; path: string }
  | { type: 'copyText'; text: string }
  | { type: 'requestProposalApply'; proposalId: string }

/** Forbidden legacy name - never use. */
export const FORBIDDEN_BRIDGE_APPLY_TYPE = 'requestApply'

type VsCodeApi = {
  postMessage: (message: unknown) => void
  getState?: () => unknown
  setState?: (state: unknown) => void
}

declare global {
  interface Window {
    acquireVsCodeApi?: () => VsCodeApi
    __METRA_BRIDGE__?: MetraBridgeHandle
  }
}

export type MetraBridgeHandle = {
  ready: boolean
  surface: BridgeSurface
  capabilities: BridgeCapabilities
  sessionToken: string | null
  deskUrl: string | null
  send: (message: PageToHostMessage) => boolean
  onHostMessage: (handler: (message: HostToPageMessage) => void) => () => void
}

const defaultCapabilities: BridgeCapabilities = {
  askInChat: false,
  openWorkspacePath: false,
  copyText: false,
  requestProposalApply: false,
}

function tryAcquireVsCodeApi(): VsCodeApi | null {
  try {
    if (typeof window !== 'undefined' && typeof window.acquireVsCodeApi === 'function') {
      return window.acquireVsCodeApi()
    }
  } catch {
    /* not in webview */
  }
  return null
}

function isInIframe(): boolean {
  try {
    return typeof window !== 'undefined' && window.parent !== window
  } catch {
    return false
  }
}

/** `{Project}: short subject` tab title from registry route stop. */
export function formatAskTabTitle(project: string, subject: string): string {
  const proj = (project || 'Metra').trim() || 'Metra'
  const short = (subject || 'Ask').replace(/\s+/g, ' ').trim().slice(0, 48) || 'Ask'
  return `${proj}: ${short}`
}

export function createMetraBridge(): MetraBridgeHandle {
  const vscode = tryAcquireVsCodeApi()
  const iframeParent = !vscode && isInIframe()
  const listeners = new Set<(message: HostToPageMessage) => void>()

  const handle: MetraBridgeHandle = {
    ready: false,
    surface: 'browser',
    capabilities: { ...defaultCapabilities },
    sessionToken: null,
    deskUrl: null,
    send(message) {
      if (message.type === (FORBIDDEN_BRIDGE_APPLY_TYPE as PageToHostMessage['type'])) {
        return false
      }
      if (vscode) {
        vscode.postMessage(message)
        return true
      }
      if (iframeParent) {
        window.parent.postMessage({ ...message, metraBridge: true }, '*')
        return true
      }
      return false
    },
    onHostMessage(handler) {
      listeners.add(handler)
      return () => listeners.delete(handler)
    },
  }

  function emit(message: HostToPageMessage) {
    if (message.type === 'surfaceReady') {
      handle.ready = true
      handle.surface = message.surface
      handle.capabilities = { ...defaultCapabilities, ...message.capabilities }
      handle.sessionToken = message.sessionToken || null
      handle.deskUrl = message.deskUrl || null
    }
    for (const listener of listeners) {
      try {
        listener(message)
      } catch {
        /* ignore listener errors */
      }
    }
  }

  function onWindowMessage(event: MessageEvent) {
    const data = event.data
    if (!data || typeof data !== 'object') return
    if (data.type === 'surfaceReady' || data.type === 'applyStatus') {
      emit(data as HostToPageMessage)
    }
  }

  if (typeof window !== 'undefined') {
    window.addEventListener('message', onWindowMessage)
    // VS Code posts to the webview document; also listen via vscode if available.
  }

  // Announce so the extension shell can reply with surfaceReady.
  queueMicrotask(() => {
    handle.send({ type: 'bridgeHello' })
  })

  window.__METRA_BRIDGE__ = handle
  return handle
}

let singleton: MetraBridgeHandle | null = null

export function getMetraBridge(): MetraBridgeHandle {
  if (!singleton) {
    singleton = createMetraBridge()
  }
  return singleton
}

export function hasMetraBridgeHost(): boolean {
  return Boolean(tryAcquireVsCodeApi() || isInIframe())
}
