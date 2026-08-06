import type {
  DeskMode,
  DeskPayload,
  Preferences,
  AskResult,
  PlaceRecommendation,
  PlaceUploadMeta,
  PlaceHome,
} from './types'
import { getMetraBridge } from './bridge'

async function parseJson<T>(res: Response): Promise<T> {
  if (!res.ok) {
    let detail = res.statusText
    try {
      const body = await res.json()
      if (body?.error) detail = String(body.error)
    } catch {
      /* ignore */
    }
    throw new Error(detail || `HTTP ${res.status}`)
  }
  return res.json() as Promise<T>
}

let cachedSessionToken: string | null = null

/** Prefer bridge-delivered Host token; else loopback /api/local-session. */
export async function ensureLocalSessionToken(): Promise<string | null> {
  const bridge = getMetraBridge()
  if (bridge.sessionToken) {
    cachedSessionToken = bridge.sessionToken
    return cachedSessionToken
  }
  if (cachedSessionToken) return cachedSessionToken
  try {
    const res = await fetch('/api/local-session')
    if (!res.ok) return null
    const body = (await res.json()) as { token?: string }
    cachedSessionToken = body.token ? String(body.token) : null
    return cachedSessionToken
  } catch {
    return null
  }
}

function withSessionHeaders(init?: RequestInit, token?: string | null): RequestInit {
  const headers = new Headers(init?.headers || {})
  if (token) {
    headers.set('X-Metra-Local-Session', token)
  }
  return { ...init, headers }
}

export function fetchSnapshot(): Promise<DeskPayload> {
  return fetch('/api/snapshot').then((r) => parseJson<DeskPayload>(r))
}

export interface OpenPathResult {
  ok: boolean
  path: string
  editor: string
  kind: string
  message: string
}

/** Desk process opens the folder; the browser cannot launch the editor itself. */
export async function openProjectPath(path: string): Promise<OpenPathResult> {
  const token = await ensureLocalSessionToken()
  return fetch(
    '/api/open',
    withSessionHeaders(
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path }),
      },
      token,
    ),
  ).then((r) => parseJson<OpenPathResult>(r))
}

export function refreshSnapshot(full = false): Promise<DeskPayload> {
  return fetch('/api/refresh', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ full }),
  }).then((r) => parseJson<DeskPayload>(r))
}

export function putPreferences(
  deskMode: DeskMode,
  attentionVisibleCount?: number,
  editorCommand?: string,
): Promise<Preferences> {
  const body: Record<string, unknown> = { deskMode }
  if (typeof attentionVisibleCount === 'number') {
    body.attentionVisibleCount = attentionVisibleCount
  }
  if (typeof editorCommand === 'string' && editorCommand) {
    body.editorCommand = editorCommand
  }
  return fetch('/api/preferences', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }).then((r) => parseJson<Preferences>(r))
}

export function dismissAttention(key: string): Promise<DeskPayload> {
  return fetch(`/api/attention/${encodeURIComponent(key)}/dismiss`, {
    method: 'POST',
  }).then((r) => parseJson<DeskPayload>(r))
}

export function snoozeAttention(key: string, days = 1): Promise<DeskPayload> {
  return fetch(`/api/attention/${encodeURIComponent(key)}/snooze`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ days }),
  }).then((r) => parseJson<DeskPayload>(r))
}

export function reopenAttention(key: string): Promise<DeskPayload> {
  return fetch(`/api/attention/${encodeURIComponent(key)}/reopen`, {
    method: 'POST',
  }).then((r) => parseJson<DeskPayload>(r))
}

export function holdAttention(key: string): Promise<DeskPayload> {
  return fetch(`/api/attention/${encodeURIComponent(key)}/hold`, {
    method: 'POST',
  }).then((r) => parseJson<DeskPayload>(r))
}

export function releaseAttention(key: string): Promise<DeskPayload> {
  return fetch(`/api/attention/${encodeURIComponent(key)}/release`, {
    method: 'POST',
  }).then((r) => parseJson<DeskPayload>(r))
}

export function postAsk(prompt: string, sessionId?: string | null): Promise<AskResult> {
  return fetch('/api/ask', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Metra-Client': 'ops-web',
    },
    body: JSON.stringify({
      prompt,
      sessionId: sessionId || undefined,
      client: 'ops-web',
      clientHint: /Mobi|Android|iPhone/i.test(navigator.userAgent) ? 'phone' : 'desktop',
    }),
  }).then((r) => parseJson(r))
}

export function postCaptureFromAsk(
  turnId: string,
  sessionId?: string | null,
  summary?: string,
): Promise<import('./types').CaptureItem> {
  return fetch('/api/capture', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Metra-Client': 'ops-web',
    },
    body: JSON.stringify({
      source: 'ask',
      turnId,
      sessionId: sessionId || undefined,
      summary: summary || undefined,
    }),
  }).then((r) => parseJson(r))
}

export function postCaptureDismiss(id: string): Promise<import('./types').CaptureItem> {
  return fetch(`/api/capture/${encodeURIComponent(id)}/dismiss`, {
    method: 'POST',
    headers: { 'X-Metra-Client': 'ops-web' },
  }).then((r) => parseJson(r))
}

export function postCapturePromote(
  id: string,
  home?: string,
): Promise<import('./types').CaptureItem> {
  return fetch(`/api/capture/${encodeURIComponent(id)}/promote`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Metra-Client': 'ops-web',
    },
    body: JSON.stringify({ home: home || undefined }),
  }).then((r) => parseJson(r))
}

export function postPlace(
  text: string,
  attachments: string[] = [],
): Promise<PlaceRecommendation> {
  return fetch('/api/place', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text, attachments }),
  }).then((r) => parseJson<PlaceRecommendation>(r))
}

export async function postPlaceUpload(file: File): Promise<PlaceUploadMeta> {
  const buf = await file.arrayBuffer()
  const bytes = new Uint8Array(buf)
  let binary = ''
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
  const contentBase64 = btoa(binary)
  return fetch('/api/place/upload', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      fileName: file.name,
      contentType: file.type || 'application/octet-stream',
      contentBase64,
    }),
  }).then((r) => parseJson<PlaceUploadMeta>(r))
}

export function postPlaceConfirm(
  text: string,
  homeId: string,
  keepInView = false,
  attachments: string[] = [],
  saveForPortfolio = false,
): Promise<{
  result: {
    ok: boolean
    note?: string
    attentionKey?: string | null
    captureId?: string | null
    attachments?: { id: string; fileName: string }[]
  }
  desk?: DeskPayload | null
}> {
  return fetch('/api/place/confirm', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text, homeId, keepInView, saveForPortfolio, attachments }),
  }).then((r) => parseJson(r))
}

export function postPlaceCorrect(
  text: string,
  homeId: string,
): Promise<{ ok: boolean; homeLabel?: string; note?: string }> {
  return fetch('/api/place/correct', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text, homeId }),
  }).then((r) => parseJson(r))
}

export function fetchPlaceHomes(): Promise<PlaceHome[]> {
  return fetch('/api/place/homes').then((r) => parseJson<PlaceHome[]>(r))
}

export type ProposalStatusView = {
  id: string
  status: string
  contentHash?: string
  expiresAt?: string
  resultMessage?: string | null
}

export function fetchProposalDiff(id: string): Promise<string> {
  return fetch(`/api/proposals/${encodeURIComponent(id)}/diff`).then(async (r) => {
    if (!r.ok) {
      throw new Error(r.statusText || `HTTP ${r.status}`)
    }
    return r.text()
  })
}

export async function postProposalRequestApply(id: string): Promise<ProposalStatusView> {
  const token = await ensureLocalSessionToken()
  return fetch(
    `/api/proposals/${encodeURIComponent(id)}/request-apply`,
    withSessionHeaders({ method: 'POST' }, token),
  ).then((r) => parseJson<ProposalStatusView>(r))
}
