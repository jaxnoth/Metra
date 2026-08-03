import type { DeskMode, DeskPayload, Handoff, Preferences, AskResult } from './types'

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

export function fetchSnapshot(): Promise<DeskPayload> {
  return fetch('/api/snapshot').then((r) => parseJson<DeskPayload>(r))
}

export function refreshSnapshot(full = false): Promise<DeskPayload> {
  return fetch('/api/refresh', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ full }),
  }).then((r) => parseJson<DeskPayload>(r))
}

export function putPreferences(deskMode: DeskMode): Promise<Preferences> {
  return fetch('/api/preferences', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ deskMode }),
  }).then((r) => parseJson<Preferences>(r))
}

export function postAsk(prompt: string, sessionId?: string | null): Promise<AskResult> {
  return fetch('/api/ask', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt, sessionId: sessionId || undefined }),
  }).then((r) => parseJson(r))
}

export function postClassify(query: string): Promise<Handoff> {
  return fetch('/api/classify', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  }).then((r) => parseJson<Handoff>(r))
}
