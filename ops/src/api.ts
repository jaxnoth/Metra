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
const SESSION_STORAGE_KEY = 'metraLocalSession'
const SESSION_TOKEN_RE = /^[0-9a-f]{64}$/i

function stripLocationHash(): void {
  try {
    if (typeof window === 'undefined') return
    const clean = `${window.location.pathname}${window.location.search}`
    window.history.replaceState(null, document.title, clean)
  } catch {
    /* ignore */
  }
}

/**
 * Host may open desk with #metraLocalSession=<64-hex>.
 * Valid: store in sessionStorage then strip. Malformed: ignore (do not store) and still strip.
 */
function consumeHashOrStoredSessionToken(): string | null {
  try {
    if (typeof window === 'undefined') return null
    const hash = window.location.hash || ''
    if (/metraLocalSession=/i.test(hash)) {
      const match = hash.match(/(?:^|#|&)metraLocalSession=([0-9a-fA-F]*)/)
      const raw = match?.[1] ?? ''
      stripLocationHash()
      if (SESSION_TOKEN_RE.test(raw)) {
        sessionStorage.setItem(SESSION_STORAGE_KEY, raw.toLowerCase())
        return raw.toLowerCase()
      }
      // Malformed bootstrap - do not store; hash already stripped.
      return null
    }
    const stored = sessionStorage.getItem(SESSION_STORAGE_KEY)
    return stored && SESSION_TOKEN_RE.test(stored) ? stored : null
  } catch {
    return null
  }
}

export function clearLocalSessionToken(): void {
  cachedSessionToken = null
  try {
    sessionStorage.removeItem(SESSION_STORAGE_KEY)
  } catch {
    /* ignore */
  }
}

/** Prefer bridge / hash bootstrap; else loopback /api/local-session. */
export async function ensureLocalSessionToken(): Promise<string | null> {
  const bridge = getMetraBridge()
  if (bridge.sessionToken && SESSION_TOKEN_RE.test(bridge.sessionToken)) {
    cachedSessionToken = bridge.sessionToken
    return cachedSessionToken
  }
  const bootstrapped = consumeHashOrStoredSessionToken()
  if (bootstrapped) {
    cachedSessionToken = bootstrapped
    return cachedSessionToken
  }
  if (cachedSessionToken && SESSION_TOKEN_RE.test(cachedSessionToken)) {
    return cachedSessionToken
  }
  cachedSessionToken = null
  try {
    const res = await fetch('/api/local-session')
    if (!res.ok) return null
    const body = (await res.json()) as { token?: string }
    const tok = body.token ? String(body.token) : ''
    cachedSessionToken = SESSION_TOKEN_RE.test(tok) ? tok : null
    return cachedSessionToken
  } catch {
    return null
  }
}

/**
 * Probe local authority (session token and/or same-machine).
 * GET /api/local-authority always returns 200 with { authorized }.
 * Clears stored bootstrap only when the server reports not authorized while a token was presented.
 */
export async function verifyLocalSessionAuthority(): Promise<boolean> {
  const token = await ensureLocalSessionToken()
  try {
    const res = await fetch('/api/local-authority', withSessionHeaders(undefined, token))
    if (!res.ok) return false
    const body = (await res.json()) as { authorized?: boolean }
    const ok = Boolean(body.authorized)
    if (!ok && token) clearLocalSessionToken()
    return ok
  } catch {
    return false
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

export type TicketWatchResult = {
  ok: boolean
  available: boolean
  scope: string
  synced: boolean
  syncError?: string
  warning?: string
  scanned: number
  added: number
  refreshed: number
  unchanged: number
  draftsWritten: number
  /** True when at least one local analyze draft was written this scan. */
  draftAvailable?: boolean
  /** E1: count of Next evidence notes written this scan. */
  evidenceSuggestions?: number
  nextEvidenceAvailable?: boolean
  /** E1: at least one draftState=recommendable (Ready for recommendation - no auto-write). */
  readyForRecommendation?: boolean
  iSupportWrites: boolean
}

export type WatchTicketsResponse = {
  ok: boolean
  watch: TicketWatchResult
  desk: DeskPayload
}

/** Mine-scope TicketWatch scan into Attention. No iSupport writes. */
export function watchTickets(draft = false): Promise<WatchTicketsResponse> {
  return fetch('/api/watch/tickets', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ draft }),
  }).then((r) => parseJson<WatchTicketsResponse>(r))
}

export type TicketWatchStoreResult = {
  ok: boolean
  id: string
  preview: boolean
  confirm: boolean
  force: boolean
  mineEligible: boolean
  recommendable: boolean
  body?: string
  noteId?: string
  iSupportWrite: boolean
  recommendationWritten: boolean
  warning?: string
  nextSteps?: string
  autoStoreRecommend?: boolean
}

export type WatchRecommendResponse = {
  ok: boolean
  store: TicketWatchStoreResult
  desk: DeskPayload
  error?: string
}

/** M3: Preview local recommend-draft or Confirm Affirm A TT recommend. */
export function watchRecommend(
  id: string,
  opts: { preview?: boolean; confirm?: boolean; force?: boolean; minutes?: number } = {},
): Promise<WatchRecommendResponse> {
  const confirm = Boolean(opts.confirm)
  const preview = confirm ? false : opts.preview !== false
  return fetch('/api/watch/recommend', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      id,
      preview,
      confirm,
      force: Boolean(opts.force),
      minutes: opts.minutes ?? 15,
    }),
  }).then((r) => parseJson<WatchRecommendResponse>(r))
}

export function putPreferences(
  deskMode: DeskMode,
  attentionVisibleCount?: number,
  editorCommand?: string,
  ticketWatchEnabled?: boolean,
): Promise<Preferences> {
  const body: Record<string, unknown> = { deskMode }
  if (typeof attentionVisibleCount === 'number') {
    body.attentionVisibleCount = attentionVisibleCount
  }
  if (typeof editorCommand === 'string' && editorCommand) {
    body.editorCommand = editorCommand
  }
  if (typeof ticketWatchEnabled === 'boolean') {
    body.ticketWatchEnabled = ticketWatchEnabled
  }
  return fetch('/api/preferences', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }).then((r) => parseJson<Preferences>(r))
}

export function fetchAskEngine(): Promise<import('./types').AskEnginePanel> {
  return fetch('/api/ask/engine').then((r) => parseJson(r))
}

export async function postAskEngineSet(engine: string, sizeBand?: string): Promise<{ ok: boolean; capability?: import('./types').AskCapability }> {
  const token = await ensureLocalSessionToken()
  return fetch(
    '/api/ask/engine',
    withSessionHeaders(
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'set', engine, sizeBand }),
      },
      token,
    ),
  ).then((r) => parseJson(r))
}

export async function postAskEngineAccept(): Promise<{ ok: boolean }> {
  const token = await ensureLocalSessionToken()
  return fetch(
    '/api/ask/engine',
    withSessionHeaders(
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'accept' }),
      },
      token,
    ),
  ).then((r) => parseJson(r))
}

export function fetchSettings(): Promise<import('./types').SettingsPortfolio> {
  return fetch('/api/settings').then((r) => parseJson(r))
}

export async function putSettings(body: {
  roots?: import('./types').SettingsRootInput[]
  primaryPath?: string
  personalPath?: string
  clearPersonal?: boolean
  cursorApiKey?: string
  clearCursorApiKey?: boolean
  machineRole?: 'Hq' | 'Satellite' | 'Standalone'
  opsBaseUrl?: string
  clearOpsBaseUrl?: boolean
}): Promise<import('./types').SettingsSaveResult> {
  const token = await ensureLocalSessionToken()
  return fetch(
    '/api/settings',
    withSessionHeaders(
      {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      },
      token,
    ),
  ).then((r) => parseJson(r))
}

export function fetchUpdates(force = false): Promise<import('./types').ProductUpdates> {
  const q = force ? '?force=1' : ''
  return fetch(`/api/updates${q}`).then((r) => parseJson(r))
}

export async function postProductUpdate(
  target: 'metra' | 'ollama',
): Promise<import('./types').ProductUpdateApplyResponse> {
  const token = await ensureLocalSessionToken()
  const res = await fetch(
    '/api/updates',
    withSessionHeaders(
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ target }),
      },
      token,
    ),
  )
  let body: {
    accepted?: boolean
    error?: string | null
    message?: string | null
    job?: import('./types').ProductUpdateApplyJob | null
  } = {}
  try {
    body = (await res.json()) as typeof body
  } catch {
    /* ignore */
  }
  if (res.status === 202 || res.status === 409 || res.status === 422) {
    return {
      accepted: Boolean(body.accepted),
      error: body.error ?? null,
      message: body.message ?? null,
      job: body.job ?? null,
      statusCode: res.status,
    }
  }
  if (!res.ok) {
    const detail = body.message || body.error || res.statusText || `HTTP ${res.status}`
    throw new Error(String(detail))
  }
  return {
    accepted: Boolean(body.accepted),
    error: body.error ?? null,
    message: body.message ?? null,
    job: body.job ?? null,
    statusCode: res.status,
  }
}

export async function fetchProfileStatus(): Promise<import('./types').ProfileSyncStatus> {
  const token = await ensureLocalSessionToken()
  return fetch('/api/profile/status', withSessionHeaders({}, token)).then((r) => parseJson(r))
}

export async function downloadProfileExport(): Promise<void> {
  const token = await ensureLocalSessionToken()
  const res = await fetch('/api/profile/export', withSessionHeaders({}, token))
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
  const blob = await res.blob()
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = 'metra-profile.zip'
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}

export async function issueProfileSyncToken(
  rotate = false,
): Promise<import('./types').ProfileSyncTokenIssue> {
  const token = await ensureLocalSessionToken()
  return fetch(
    '/api/profile/issue-sync-token',
    withSessionHeaders(
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ rotate }),
      },
      token,
    ),
  ).then((r) => parseJson(r))
}

export function dismissAttention(key: string, note?: string): Promise<DeskPayload> {
  return fetch(`/api/attention/${encodeURIComponent(key)}/dismiss`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(note ? { note } : {}),
  }).then((r) => parseJson<DeskPayload>(r))
}

export function noteAttention(key: string, note: string): Promise<DeskPayload> {
  return fetch(`/api/attention/${encodeURIComponent(key)}/note`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ note }),
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

export function postAsk(
  prompt: string,
  sessionId?: string | null,
  recallSessionId?: string | null,
  imageIds?: string[] | null,
): Promise<AskResult> {
  return fetch('/api/ask', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'X-Metra-Client': 'ops-web',
    },
    body: JSON.stringify({
      prompt,
      sessionId: sessionId || undefined,
      recallSessionId: recallSessionId || undefined,
      imageIds: imageIds && imageIds.length > 0 ? imageIds : undefined,
      client: 'ops-web',
      clientHint: /Mobi|Android|iPhone/i.test(navigator.userAgent) ? 'phone' : 'desktop',
    }),
  }).then((r) => parseJson(r))
}

export type AskJournalSessionPayload = {
  sessionId: string
  turnCount: number
  continuity?: import('./types').AskContinuity | null
  turns: import('./types').AskEntry[]
}

export function fetchAskJournalSession(sessionId: string): Promise<AskJournalSessionPayload> {
  const q = new URLSearchParams({ sessionId })
  return fetch(`/api/ask/journal?${q}`).then((r) => parseJson(r))
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

/** Ladder 2b: propose Capture rows from Ask (no ledger write). */
export async function postCapturePropose(opts: {
  turnId?: string | null
  sessionId?: string | null
}): Promise<{ proposals: import('./types').CaptureProposal[] }> {
  const token = await ensureLocalSessionToken()
  return fetch(
    '/api/capture/propose',
    withSessionHeaders(
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Metra-Client': 'ops-web',
        },
        body: JSON.stringify({
          turnId: opts.turnId || undefined,
          sessionId: opts.sessionId || undefined,
        }),
      },
      token,
    ),
  ).then((r) => parseJson(r))
}

/** Ladder 2b: create only accepted proposal rows. */
export async function postCaptureAccepted(
  acceptedProposals: Array<{
    proposalId?: string
    summary: string
    suggestedHome?: string
    suggestedProject?: string | null
    derivedFrom?: { type?: string; sessionId?: string; turnId?: string }
    accepted: boolean
  }>,
): Promise<{ items: import('./types').CaptureItem[]; count: number }> {
  const token = await ensureLocalSessionToken()
  return fetch(
    '/api/capture',
    withSessionHeaders(
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Metra-Client': 'ops-web',
        },
        body: JSON.stringify({ acceptedProposals }),
      },
      token,
    ),
  ).then((r) => parseJson(r))
}

export function postCaptureDismiss(id: string): Promise<import('./types').CaptureItem> {
  return fetch(`/api/capture/${encodeURIComponent(id)}/dismiss`, {
    method: 'POST',
    headers: { 'X-Metra-Client': 'ops-web' },
  }).then((r) => parseJson(r))
}

export async function postCapturePromote(
  id: string,
  opts?: { home?: string; project?: string; crossRootConfirm?: boolean },
): Promise<import('./types').CaptureItem> {
  const token = await ensureLocalSessionToken()
  return fetch(
    `/api/capture/${encodeURIComponent(id)}/promote`,
    withSessionHeaders(
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Metra-Client': 'ops-web',
        },
        body: JSON.stringify({
          home: opts?.home || undefined,
          project: opts?.project || undefined,
          crossRootConfirm: opts?.crossRootConfirm === true,
        }),
      },
      token,
    ),
  ).then((r) => parseJson(r))
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
