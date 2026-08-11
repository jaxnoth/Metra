import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  dismissAttention,
  fetchAskJournalSession,
  fetchProposalDiff,
  fetchSnapshot,
  holdAttention,
  noteAttention,
  openProjectPath,
  postAsk,
  ensureLocalSessionToken,
  postCaptureAccepted,
  postCaptureDismiss,
  postCaptureFromAsk,
  postCapturePromote,
  postCapturePropose,
  postPlace,
  postPlaceConfirm,
  postPlaceCorrect,
  postPlaceUpload,
  fetchPlaceHomes,
  postProposalRequestApply,
  putPreferences,
  refreshSnapshot,
  watchTickets,
  watchRecommend,
  releaseAttention,
  snoozeAttention,
  fetchAskEngine,
  postAskEngineAccept,
  postAskEngineSet,
  fetchSettings,
  putSettings,
  fetchUpdates,
  fetchProfileStatus,
  downloadProfileExport,
  issueProfileSyncToken,
  postProductUpdate,
} from './api'
import { AskMarkdown } from './AskMarkdown'
import { formatAskTabTitle, getMetraBridge } from './bridge'
import {
  DEFAULT_ATTENTION_VISIBLE_COUNT,
  normalizeAttentionVisibleCount,
} from './attentionVisibleCount'
import { MetraPresence } from './MetraPresence'
import type {
  AttentionItem,
  AskSessionSummary,
  AskEnginePanel,
  SettingsPortfolio,
  ProductUpdates,
  ProfileSyncStatus,
  CaptureItem,
  CaptureProposal,
  DeskPayload,
  DeskMode,
  Handoff,
  NextAttention,
  PlaceHome,
  PlaceRecommendation,
  PlaceUploadMeta,
} from './types'

type TabId = 'route' | 'projects' | 'recent' | 'health' | 'settings'

type RootDraft = {
  key: string
  name: string
  label: string
  path: string
  primary: boolean
  optional: boolean
}

function newRootDraftKey(): string {
  return `root-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`
}

function portfolioRootsToDrafts(portfolio: SettingsPortfolio | null): RootDraft[] {
  const roots = portfolio?.roots ?? []
  if (roots.length === 0) {
    return [
      {
        key: newRootDraftKey(),
        name: 'work',
        label: 'Work',
        path: portfolio?.primaryPath || '',
        primary: true,
        optional: false,
      },
    ]
  }
  return roots.map((r, i) => ({
    key: r.name || `root-${i}`,
    name: r.name || '',
    label: (r.label || r.name || `Folder ${i + 1}`).trim(),
    path: r.path || '',
    primary: Boolean(r.primary),
    optional: Boolean(r.optional),
  }))
}

type ChatTurn = {
  id: string
  role: 'you' | 'metra'
  text: string
  handoff?: Handoff | null
  answered?: boolean
  answerType?: string | null
  evidenceQuality?: string | null
  nextStep?: string | null
  /** Quiet Where chip when Ask route is weak or ambiguous. */
  showWhere?: boolean
  /** Park short-circuit: highlight Save for portfolio. */
  suggestCapture?: boolean
  /** Journal turn id for Save for portfolio. */
  turnId?: string | null
  sessionId?: string | null
}

const CHAT_LIMIT = 24

function nextChatId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
}

/** Desk already labels Metra - drop Cursor-chat persona banners from answer text. */
function stripAskUiChrome(text: string): string {
  if (!text) return text
  return text
    .split(/\r?\n/)
    .filter((line) => {
      if (/^\s*\*{0,2}Metra\*{0,2}\s*[·•|]\s*Model\s*:/i.test(line)) return false
      if (
        /^\s*\*{0,2}Metra\*{0,2}\s*[·•]/i.test(line) &&
        /model/i.test(line) &&
        /cursor|composer|language\s+model/i.test(line)
      ) {
        return false
      }
      return true
    })
    .join('\n')
    .trim()
}

/** Relative time for the awareness strip (countable truth companion). */
function formatUpdatedShort(iso: string | undefined): string {
  if (!iso) return 'Not refreshed yet'
  const t = Date.parse(iso)
  if (Number.isNaN(t)) return iso
  const mins = Math.max(0, Math.round((Date.now() - t) / 60000))
  if (mins < 1) return 'Updated just now'
  if (mins === 1) return 'Updated 1 minute ago'
  if (mins < 60) return `Updated ${mins} minutes ago`
  return `Updated ${new Date(t).toLocaleString()}`
}

/** Compact relative time for satellite roster (today / yesterday / N days ago). */
function formatRelativeUtc(iso: string | undefined): string {
  if (!iso) return ''
  const t = Date.parse(iso)
  if (Number.isNaN(t)) return iso
  const mins = Math.max(0, Math.round((Date.now() - t) / 60000))
  if (mins < 60) return 'today'
  const hours = Math.round(mins / 60)
  if (hours < 24) return 'today'
  const days = Math.round(hours / 24)
  if (days === 1) return 'yesterday'
  return `${days} days ago`
}

/** Quiet/busy narration - never invents certainty like "All clear." */
function awarenessNarration(
  waiting: number,
  emptyHint: string | null | undefined,
  gitChecked: boolean | undefined,
): string {
  if (waiting > 1) {
    return `I see ${waiting} items ready for review - discuss one, or type what you're thinking.`
  }
  if (waiting === 1) {
    return 'One item ready for review - discuss it, or type what you\'re thinking.'
  }
  const quiet = 'Clear for now. Toss me an idea whenever.'
  if (emptyHint && /not reviewed|quick check|light check|recheck|full refresh|Portfolio refresh/i.test(emptyHint)) {
    return `${quiet} ${emptyHint}`
  }
  if (gitChecked === false) {
    return `${quiet} Some areas were not reviewed - run Portfolio refresh to confirm.`
  }
  return quiet
}

async function copyText(text: string): Promise<boolean> {
  const bridge = getMetraBridge()
  if (bridge.ready && bridge.capabilities.copyText && bridge.send({ type: 'copyText', text })) {
    return true
  }
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch {
    /* Non-secure origins (plain http share URLs) have no async clipboard. */
  }
  return copyTextLegacy(text)
}

/** execCommand fallback so plain-http desk URLs can still copy. */
function copyTextLegacy(text: string): boolean {
  try {
    const area = document.createElement('textarea')
    area.value = text
    area.setAttribute('readonly', '')
    area.style.position = 'fixed'
    area.style.opacity = '0'
    document.body.appendChild(area)
    area.select()
    const ok = document.execCommand('copy')
    document.body.removeChild(area)
    return ok
  } catch {
    return false
  }
}

function confidenceLabel(c?: string | null): string {
  switch (c) {
    case 'fresh':
      return 'Checked recently'
    case 'likelyStale':
      return 'May be outdated'
    case 'needsRevalidation':
      return 'Needs a fresh check'
    default:
      return c || ''
  }
}

function kindLabel(kind?: string | null): string {
  switch (kind) {
    case 'git':
      return 'Git'
    case 'ticket':
      return 'Ticket'
    case 'verify':
      return 'Health check'
    case 'drift':
      return 'Setup'
    case 'decision':
      return 'Decision'
    case 'contract':
      return 'Preference'
    default:
      return kind || ''
  }
}

function attentionItemKey(item: AttentionItem): string {
  return item.key || item.id
}

function attentionPickerLabel(item: AttentionItem): string {
  const kind = kindLabel(item.kind)
  const summary = (item.summary || item.content || item.key || item.id || 'Item').trim()
  const max = 96
  const text = summary.length > max ? `${summary.slice(0, max - 1)}…` : summary
  if (kind && !summary.toLowerCase().startsWith(kind.toLowerCase())) {
    return `${kind}: ${text}`
  }
  return text
}

function PresenceBrand({
  askPending,
  attentionWaiting,
  attentionEmptyHint,
  gitChecked,
  generatedAt,
}: {
  askPending: boolean
  attentionWaiting: number
  attentionEmptyHint?: string | null
  gitChecked?: boolean
  generatedAt?: string | null
}) {
  return (
    <div className="brand">
      <MetraPresence
        voiceState={askPending ? 'listening' : 'idle'}
        attentionBusy={attentionWaiting > 0}
      />
      <div className="awareness-strip" aria-live="polite">
        <p className="awareness-narration muted">
          {askPending
            ? 'Working...'
            : awarenessNarration(attentionWaiting, attentionEmptyHint, gitChecked)}
        </p>
        <p className="awareness-meta muted">{formatUpdatedShort(generatedAt ?? undefined)}</p>
      </div>
    </div>
  )
}

function AttentionCard({
  item,
  advanced,
  busy,
  onAskSeed,
  onStatus,
  onDeskUpdate,
  primary = false,
}: {
  item: AttentionItem
  advanced: boolean
  busy: boolean
  onAskSeed: (prompt: string) => void
  onStatus: (message: string | null) => void
  onDeskUpdate: (payload: DeskPayload) => void
  primary?: boolean
}) {
  const conf = confidenceLabel(item.confidence)
  const typeLabel = kindLabel(item.kind)
  const metaBits = [
    item.project,
    typeLabel,
    conf,
    item.notRecheckedSince ? 'Not rechecked recently' : null,
  ].filter(Boolean)

  return (
    <div className={primary ? 'attention-card attention-card-primary' : 'attention-card'}>
      <p className="attention">{item.summary || item.content}</p>
      {item.detail && <p className="muted attention-detail">{item.detail}</p>}
      {item.whyNext && <p className="attention-why">{item.whyNext}</p>}
      {advanced && (
        <>
          <p className="muted attention-meta">{metaBits.join(' · ')}</p>
          {item.content && item.content !== item.summary && item.content !== item.detail && (
            <p className="muted attention-detail">
              Detail: <code>{item.content}</code>
            </p>
          )}
          {item.command && (
            <p className="attention-command">
              <code>{item.command}</code>
            </p>
          )}
          {item.projectPath && (
            <p className="muted attention-path">
              <code>{item.projectPath}</code>
            </p>
          )}
        </>
      )}
      <ResolveActions
        attention={item}
        advanced={advanced}
        busy={busy}
        onAskSeed={onAskSeed}
        onStatus={onStatus}
        onDeskUpdate={onDeskUpdate}
      />
    </div>
  )
}

function ResolveActions({
  attention,
  advanced,
  busy,
  onAskSeed,
  onStatus,
  onDeskUpdate,
}: {
  attention: NonNullable<NextAttention>
  advanced: boolean
  busy: boolean
  onAskSeed: (prompt: string) => void
  onStatus: (message: string | null) => void
  onDeskUpdate: (payload: DeskPayload) => void
}) {
  const capability = attention.editCapability ?? 'unsafe'
  const [diffOpen, setDiffOpen] = useState(false)
  const [diffText, setDiffText] = useState('')
  const [localBusy, setLocalBusy] = useState(false)
  const [feedback, setFeedback] = useState(attention.note || '')
  const [recommendPreview, setRecommendPreview] = useState<string | null>(null)
  const bridge = getMetraBridge()
  const key = attention.key || attention.id

  useEffect(() => {
    setFeedback(attention.note || '')
    setRecommendPreview(null)
  }, [attention.key, attention.id, attention.note])

  useEffect(() => {
    return bridge.onHostMessage((message) => {
      if (message.type === 'applyStatus' && message.proposalId === attention.proposalId) {
        onStatus(
          message.message
            ? `${message.status}: ${message.message}`
            : `Proposal status: ${message.status}`,
        )
      }
      if (message.type === 'surfaceReady' && message.sessionToken) {
        onStatus(null)
      }
    })
  }, [attention.proposalId, bridge, onStatus])

  async function onReview() {
    if (!attention.proposalId) return
    setLocalBusy(true)
    onStatus(null)
    try {
      const text = await fetchProposalDiff(attention.proposalId)
      setDiffText(text || '(empty diff)')
      setDiffOpen(true)
    } catch (e) {
      onStatus(e instanceof Error ? e.message : String(e))
    } finally {
      setLocalBusy(false)
    }
  }

  async function onApplyViaMetra() {
    if (!attention.proposalId || capability !== 'safe') return
    setLocalBusy(true)
    onStatus(null)
    try {
      if (
        bridge.ready &&
        bridge.capabilities.requestProposalApply &&
        bridge.send({ type: 'requestProposalApply', proposalId: attention.proposalId })
      ) {
        onStatus('Requested apply via IDE bridge. Confirm Apply once in the Metra tray.')
        return
      }
      const status = await postProposalRequestApply(attention.proposalId)
      onStatus(
        status.status === 'pendingApply'
          ? 'Queued for Metra tray confirm (Apply once). Watch the tray notification.'
          : `Proposal status: ${status.status}${status.resultMessage ? ` - ${status.resultMessage}` : ''}`,
      )
    } catch (e) {
      onStatus(e instanceof Error ? e.message : String(e))
    } finally {
      setLocalBusy(false)
    }
  }

  async function mutate(
    fn: () => Promise<DeskPayload>,
    okMessage: string,
  ) {
    if (!key) {
      onStatus('Missing attention key.')
      return
    }
    setLocalBusy(true)
    onStatus(null)
    try {
      const payload = await fn()
      onDeskUpdate(payload)
      onStatus(okMessage)
    } catch (e) {
      onStatus(e instanceof Error ? e.message : String(e))
    } finally {
      setLocalBusy(false)
    }
  }

  async function onOpenEditor() {
    const path = attention.projectPath || ''
    if (!path) {
      onStatus(
        attention.project
          ? `No folder path for ${attention.project}. Open that project from the workspace, or refresh the desk snapshot.`
          : 'No project path on this attention item.',
      )
      return
    }
    if (
      bridge.ready &&
      bridge.capabilities.openWorkspacePath &&
      bridge.send({ type: 'openWorkspacePath', path })
    ) {
      onStatus('Asked the IDE to reveal the project path.')
      return
    }
    setLocalBusy(true)
    try {
      const result = await openProjectPath(path)
      onStatus(result.message || `Opened ${path}.`)
      return
    } catch (err) {
      const detail = err instanceof Error ? err.message : String(err)
      const ok = await copyText(path)
      onStatus(
        ok
          ? `${detail} Copied the path instead: ${path}`
          : `${detail} Open this folder in the editor: ${path}`,
      )
    } finally {
      setLocalBusy(false)
    }
  }

  async function onCopyPrompt() {
    const text = attention.askPrompt || attention.content
    const ok = await copyText(text)
    onStatus(ok ? 'Ask prompt copied.' : 'Could not copy prompt.')
  }

  async function onCopyCommand() {
    const text = attention.command || ''
    if (!text) {
      onStatus('No command on this attention item.')
      return
    }
    const ok = await copyText(text)
    onStatus(ok ? 'Command copied.' : 'Could not copy command.')
  }

  function onAskMetra() {
    let prompt = attention.askPrompt || attention.content
    const draft = feedback.trim()
    if (draft && !prompt.includes(draft)) {
      prompt = `${prompt}\n\nOperator feedback (treat as current evidence): ${draft}`
    }
    const project = attention.project || 'Metra'
    const subject = attention.summary || attention.content || 'Ask'
    const tabTitle = formatAskTabTitle(project, subject)
    if (
      bridge.ready &&
      bridge.capabilities.askInChat &&
      bridge.send({ type: 'askInChat', project, subject, prompt, tabTitle })
    ) {
      onStatus(`Opened IDE chat as "${tabTitle}".`)
      return
    }
    onAskSeed(prompt)
  }

  async function onSaveFeedback(dismissAfter: boolean) {
    const text = feedback.trim()
    if (!text) {
      onStatus('Add a short note first (for example: email says resolved).')
      return
    }
    if (!key) {
      onStatus('Missing attention key.')
      return
    }
    setLocalBusy(true)
    onStatus(null)
    try {
      const payload = dismissAfter
        ? await dismissAttention(key, text)
        : await noteAttention(key, text)
      onDeskUpdate(payload)
      onStatus(
        dismissAfter
          ? attention.kind === 'ticket'
            ? 'Saved local ticket note and dismissed. No iSupport post.'
            : 'Saved note and dismissed.'
          : attention.kind === 'ticket'
            ? 'Saved local ticket note. No iSupport post.'
            : 'Saved note on this attention item.',
      )
    } catch (e) {
      onStatus(e instanceof Error ? e.message : String(e))
    } finally {
      setLocalBusy(false)
    }
  }

  const ticketIdFromKey = (() => {
    if (attention.kind !== 'ticket' || !key) return null
    const m = /^ticket:(.+)$/i.exec(key)
    return m ? m[1] : null
  })()

  async function onWatchRecommend(mode: 'preview' | 'confirm', force = false) {
    if (!ticketIdFromKey) {
      onStatus('Missing ticket id for recommendation.')
      return
    }
    if (mode === 'confirm' && force) {
      const ok = window.confirm(
        'Force write recommendation to iSupport even though local evidence is still thin?',
      )
      if (!ok) return
    }
    setLocalBusy(true)
    onStatus(null)
    setRecommendPreview(null)
    try {
      const res = await watchRecommend(ticketIdFromKey, {
        preview: mode === 'preview',
        confirm: mode === 'confirm',
        force,
      })
      if (res.desk) onDeskUpdate(res.desk)
      const store = res.store
      const next = store?.nextSteps || store?.warning || res.error || ''
      if (!res.ok || !store?.ok) {
        onStatus(next || 'Recommendation action failed.')
        return
      }
      if (store.body) setRecommendPreview(store.body)
      if (mode === 'preview') {
        const head = store.recommendable
          ? 'Preview: local recommend-draft saved (no iSupport write).'
          : 'Preview: next-evidence brief (not a recommendation; no iSupport write).'
        onStatus(next ? `${head} ${next}` : head)
      } else {
        onStatus(
          'Wrote recommendation to iSupport (store-as-review). Re-run supersedes the same section. Not resolved.',
        )
      }
    } catch (e) {
      onStatus(e instanceof Error ? e.message : String(e))
    } finally {
      setLocalBusy(false)
    }
  }

  const disabled = busy || localBusy

  return (
    <div className="resolve-actions">
      <p className="resolve-copy">{attention.resolveCopy}</p>
      {attention.doneWhen && (
        <p className="muted resolve-done">You're done when: {attention.doneWhen}</p>
      )}
      {ticketIdFromKey && (
        <div className="actions wrap" style={{ marginBottom: '0.75rem' }}>
          <button
            type="button"
            className="btn btn-secondary"
            disabled={disabled}
            onClick={() => void onWatchRecommend('preview')}
          >
            Preview recommendation
          </button>
          <button
            type="button"
            className="btn btn-primary"
            disabled={disabled}
            onClick={() => void onWatchRecommend('confirm')}
          >
            Write recommendation
          </button>
          <button
            type="button"
            className="btn btn-secondary"
            disabled={disabled}
            title="Write to iSupport even when local evidence is still thin"
            onClick={() => void onWatchRecommend('confirm', true)}
          >
            Force write
          </button>
        </div>
      )}
      {recommendPreview && (
        <pre className="attention-recommend-preview" style={{ whiteSpace: 'pre-wrap' }}>
          {recommendPreview}
        </pre>
      )}
      <label className="attention-feedback">
        <span className="muted">
          Your note (before Discuss)
          {attention.kind === 'ticket' ? ' - also saved locally in TicketTracker' : ''}
        </span>
        <textarea
          rows={2}
          value={feedback}
          disabled={disabled}
          placeholder="e.g. Email from requester says this is already resolved."
          onChange={(e) => setFeedback(e.target.value)}
        />
        <div className="actions wrap">
          <button
            type="button"
            className="btn btn-secondary"
            disabled={disabled || !feedback.trim()}
            onClick={() => void onSaveFeedback(false)}
          >
            Save note
          </button>
          <button
            type="button"
            className="btn btn-secondary"
            disabled={disabled || !feedback.trim()}
            onClick={() => void onSaveFeedback(true)}
          >
            Save and dismiss
          </button>
        </div>
      </label>
      <div className="actions">
        {capability === 'safe' && (
          <>
            <button
              type="button"
              className="btn btn-secondary"
              disabled={disabled || !attention.proposalId}
              onClick={() => void onReview()}
            >
              Review change
            </button>
            <button
              type="button"
              className="btn btn-primary"
              disabled={disabled || !attention.proposalId}
              onClick={() => void onApplyViaMetra()}
            >
              Apply via Metra
            </button>
            <button
              type="button"
              className="btn btn-secondary"
              disabled={disabled}
              onClick={() => void onOpenEditor()}
            >
              Open in editor
            </button>
          </>
        )}
        {capability === 'unsafe' && (
          <>
            <button
              type="button"
              className="btn btn-secondary"
              disabled={disabled}
              onClick={() => void onOpenEditor()}
            >
              Open in editor
            </button>
            {advanced && (
              <button
                type="button"
                className="btn btn-secondary"
                disabled={disabled}
                onClick={() => void onCopyPrompt()}
              >
                Copy prompt
              </button>
            )}
          </>
        )}
        {capability === 'git' && (
          <>
            <button
              type="button"
              className="btn btn-secondary"
              disabled={disabled}
              onClick={() => void onOpenEditor()}
            >
              Open in editor
            </button>
            {advanced && (
              <button
                type="button"
                className="btn btn-secondary"
                disabled={disabled || !attention.command}
                onClick={() => void onCopyCommand()}
              >
                Copy command
              </button>
            )}
          </>
        )}
        {attention.state === 'held' ? (
          <button
            type="button"
            className="btn btn-secondary"
            disabled={disabled}
            onClick={() => void mutate(() => releaseAttention(key), 'Released hold.')}
          >
            Release
          </button>
        ) : (
          <>
            <button
              type="button"
              className="btn btn-secondary"
              disabled={disabled}
              onClick={() => void mutate(() => dismissAttention(key), 'Dismissed - Metra will remember you looked away.')}
            >
              Dismiss
            </button>
            <button
              type="button"
              className="btn btn-secondary"
              disabled={disabled}
              onClick={() => void mutate(() => snoozeAttention(key, 1), 'Snoozed for 1 day.')}
            >
              Snooze
            </button>
            <button
              type="button"
              className="btn btn-secondary"
              disabled={disabled}
              onClick={() =>
                void mutate(
                  () => holdAttention(key),
                  'Kept in view for now. For lasting work, prefer a ticket or a saved decision.',
                )
              }
            >
              Keep in view
            </button>
          </>
        )}
      </div>
      {Boolean(attention.askPrompt) && (
        <div className="actions wrap bridge-actions">
          <button
            type="button"
            className="btn btn-secondary"
            disabled={disabled || !attention.askPrompt}
            onClick={() => onAskMetra()}
          >
            Discuss
          </button>
        </div>
      )}
      {diffOpen && (
        <div className="resolve-diff" role="dialog" aria-label="Proposal diff">
          <div className="resolve-diff-header">
            <strong>Proposed change</strong>
            <button type="button" className="btn btn-secondary" onClick={() => setDiffOpen(false)}>
              Close
            </button>
          </div>
          <pre className="resolve-diff-body">{diffText}</pre>
        </div>
      )}
    </div>
  )
}

/** Quiet Where chip for weak/ambiguous Ask routes - not a Classify dump. */
function WhereChip({
  handoff,
  sourceText,
  onCorrected,
}: {
  handoff: Handoff
  sourceText: string
  onCorrected?: (msg: string) => void
}) {
  const [open, setOpen] = useState(false)
  const [homes, setHomes] = useState<PlaceHome[]>([])
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (!open || homes.length > 0) return
    void fetchPlaceHomes()
      .then(setHomes)
      .catch(() => setHomes([]))
  }, [open, homes.length])

  if (handoff.kind === 'greeting' || handoff.kind === 'observation' || handoff.kind === 'park') return null

  return (
    <div className="where-chip">
      <p className="muted">
        Where: <strong>{handoff.where ?? 'Metra'}</strong>
        {handoff.ambiguous && handoff.runnerUp ? ` (also close: ${handoff.runnerUp})` : ''}
      </p>
      <button type="button" className="btn btn-secondary" onClick={() => setOpen((v) => !v)}>
        This belongs in…
      </button>
      {open && (
        <div className="where-correct">
          <p className="muted">Correction becomes a Decision Registry candidate and place memory - not auto-promoted.</p>
          <div className="actions wrap">
            {homes.map((h) => (
              <button
                key={h.id}
                type="button"
                className="btn btn-secondary"
                disabled={busy}
                onClick={() => {
                  setBusy(true)
                  void postPlaceCorrect(sourceText, h.id)
                    .then((r) => {
                      onCorrected?.(r.note || `Noted: ${r.homeLabel || h.label}`)
                      setOpen(false)
                    })
                    .catch((e) => onCorrected?.(e instanceof Error ? e.message : String(e)))
                    .finally(() => setBusy(false))
                }}
              >
                {h.label}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

function attachmentSuffix(attachments?: { fileName: string }[]): string {
  const names = (attachments ?? []).map((a) => a.fileName).filter(Boolean)
  if (names.length === 0) return ''
  return ` Linked ${names.join(', ')} (stays in quarantine).`
}

const ASK_IMAGE_EXT = /\.(png|jpe?g|gif|webp)$/i

function isAskImageFile(file: { fileName?: string; name?: string } | File): boolean {
  const name =
    file instanceof File
      ? file.name
      : String((file as { fileName?: string }).fileName || (file as { name?: string }).name || '')
  return ASK_IMAGE_EXT.test(name)
}

function PlaceResultCard({
  place,
  intakeText,
  attachmentIds,
  advanced,
  busy,
  onStatus,
  onDeskUpdate,
}: {
  place: PlaceRecommendation
  intakeText: string
  attachmentIds: string[]
  advanced: boolean
  busy: boolean
  onStatus: (s: string | null) => void
  onDeskUpdate: (d: DeskPayload) => void
}) {
  const [localBusy, setLocalBusy] = useState(false)
  const [ack, setAck] = useState<string | null>(null)
  const disabled = busy || localBusy

  async function onCopy() {
    if (!place.draft) return
    const ok = await copyText(place.draft)
    onStatus(ok ? 'Copied recommendation draft.' : 'Could not copy - select the draft text manually.')
  }

  async function onOpenPath(path: string) {
    try {
      setLocalBusy(true)
      const result = await openProjectPath(path)
      onStatus(result.message || `Opened ${result.path}`)
    } catch (e) {
      onStatus(e instanceof Error ? e.message : String(e))
    } finally {
      setLocalBusy(false)
    }
  }

  async function onKeepInView() {
    if (!place.homeId) return
    try {
      setLocalBusy(true)
      setAck(null)
      const res = await postPlaceConfirm(intakeText, place.homeId, true, attachmentIds, false)
      if (res.desk) onDeskUpdate(res.desk)
      const note = res.result?.note || 'Kept in view.'
      setAck(`Keeping this in view on Next attention.${attachmentSuffix(res.result?.attachments)}`)
      onStatus(note)
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e)
      setAck(msg)
      onStatus(msg)
    } finally {
      setLocalBusy(false)
    }
  }

  async function onSaveForPortfolio() {
    if (!place.homeId) return
    try {
      setLocalBusy(true)
      setAck(null)
      const res = await postPlaceConfirm(intakeText, place.homeId, false, attachmentIds, true)
      if (res.desk) onDeskUpdate(res.desk)
      setAck('Saved for later in Metra Capture Inbox (candidate only - not promoted).')
      onStatus(res.result?.note || 'Saved for portfolio.')
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e)
      setAck(msg)
      onStatus(msg)
    } finally {
      setLocalBusy(false)
    }
  }

  async function onAffirm() {
    if (!place.homeId) return
    try {
      setLocalBusy(true)
      setAck(null)
      const res = await postPlaceConfirm(
        intakeText,
        place.homeId,
        place.homeId === 'keep-in-view',
        attachmentIds,
        false,
      )
      if (res.desk) onDeskUpdate(res.desk)
      const note = res.result?.note || 'Recorded for learning.'
      setAck(
        `Noted - ${place.homeLabel} is the right home. Nothing was created there.${attachmentSuffix(
          res.result?.attachments,
        )}`,
      )
      onStatus(note)
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e)
      setAck(msg)
      onStatus(msg)
    } finally {
      setLocalBusy(false)
    }
  }

  return (
    <div className="place-result">
      <dl>
        <div>
          <dt>Recommended home</dt>
          <dd>{place.homeLabel}</dd>
        </div>
        <div>
          <dt>Why</dt>
          <dd>
            <ul className="place-why">
              {(place.why ?? []).map((w) => (
                <li key={w}>{w}</li>
              ))}
            </ul>
          </dd>
        </div>
        <div>
          <dt>What happens there</dt>
          <dd>{place.whatHappensThere}</dd>
        </div>
        <div>
          <dt>Your move</dt>
          <dd>{place.nextStep}</dd>
        </div>
      </dl>
      <p className="muted">
        {place.note ||
          'Recommendation only. Nothing is created until you choose a next step.'}
      </p>
      {place.pathRefs && place.pathRefs.length > 0 && (
        <div className="place-paths">
          {place.pathRefs.map((p) => (
            <button
              key={p.path}
              type="button"
              className="btn btn-secondary"
              disabled={disabled}
              onClick={() => void onOpenPath(p.openPath || p.path)}
            >
              Open {p.openPath || p.path}
            </button>
          ))}
        </div>
      )}
      {advanced && place.draft && (
        <pre className="place-draft">{place.draft}</pre>
      )}
      <div className="actions wrap">
        <button type="button" className="btn btn-secondary" disabled={disabled || !place.draft} onClick={() => void onCopy()}>
          Copy draft
        </button>
        <button type="button" className="btn btn-secondary" disabled={disabled} onClick={() => void onKeepInView()}>
          {localBusy ? 'Saving...' : 'Keep in view'}
        </button>
        <button type="button" className="btn btn-secondary" disabled={disabled} onClick={() => void onSaveForPortfolio()}>
          {localBusy ? 'Saving...' : 'Save for portfolio'}
        </button>
        <button type="button" className="btn btn-primary" disabled={disabled} onClick={() => void onAffirm()}>
          {localBusy ? 'Saving...' : "That's right"}
        </button>
      </div>
      {ack && (
        <p className="place-ack" role="status" aria-live="polite">
          {ack}
        </p>
      )}
    </div>
  )
}

export default function App() {
  const [desk, setDesk] = useState<DeskPayload | null>(null)
  const [tab, setTab] = useState<TabId>('route')
  const [prompt, setPrompt] = useState('')
  const [chat, setChat] = useState<ChatTurn[]>([])
  const [askSessionId, setAskSessionId] = useState<string | null>(null)
  /** Explicit episodic recall: prior journal session injected into the next Ask only. */
  const [recallSessionId, setRecallSessionId] = useState<string | null>(null)
  const [continuityNote, setContinuityNote] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  /** Ask in flight - drives presence mark + Working status. */
  const [askPending, setAskPending] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [askEnginePanel, setAskEnginePanel] = useState<AskEnginePanel | null>(null)
  const [askEngineOpen, setAskEngineOpen] = useState(false)
  const [settingsPortfolio, setSettingsPortfolio] = useState<SettingsPortfolio | null>(null)
  const [productUpdates, setProductUpdates] = useState<ProductUpdates | null>(null)
  const [profileSyncStatus, setProfileSyncStatus] = useState<ProfileSyncStatus | null>(null)
  const [profileSyncTokenShown, setProfileSyncTokenShown] = useState<string | null>(null)
  const [rootsDraft, setRootsDraft] = useState<RootDraft[]>(() => portfolioRootsToDrafts(null))
  const [cursorKeyDraft, setCursorKeyDraft] = useState('')
  const [machineRoleDraft, setMachineRoleDraft] = useState<'Hq' | 'Satellite' | 'Standalone'>('Standalone')
  const [opsBaseUrlDraft, setOpsBaseUrlDraft] = useState('')
  const [settingsStatus, setSettingsStatus] = useState<string | null>(null)
  const [resolveStatus, setResolveStatus] = useState<string | null>(null)
  const [ticketWatchStatus, setTicketWatchStatus] = useState<string | null>(null)
  const [selectedAttentionKey, setSelectedAttentionKey] = useState<string | null>(null)
  const [attentionShowAll, setAttentionShowAll] = useState(false)
  const [selectedHeldKey, setSelectedHeldKey] = useState<string | null>(null)
  const [compactViewport, setCompactViewport] = useState(() =>
    typeof window === 'undefined' ? false : window.matchMedia('(max-width: 42rem)').matches,
  )
  const [attentionOpen, setAttentionOpen] = useState(() =>
    typeof window === 'undefined' ? true : !window.matchMedia('(max-width: 42rem)').matches,
  )
  const [placeText, setPlaceText] = useState('')
  const [placeFiles, setPlaceFiles] = useState<PlaceUploadMeta[]>([])
  const [placePreviews, setPlacePreviews] = useState<Record<string, string>>({})
  const [placeResult, setPlaceResult] = useState<PlaceRecommendation | null>(null)
  const [placeStatus, setPlaceStatus] = useState<string | null>(null)
  const [placePending, setPlacePending] = useState(false)
  const [captureProposals, setCaptureProposals] = useState<
    Array<CaptureProposal & { accepted: boolean }>
  >([])
  const [captureProposeOpen, setCaptureProposeOpen] = useState(false)
  const [hasLocalSession, setHasLocalSession] = useState(false)
  const [captureDrafts, setCaptureDrafts] = useState<
    Record<string, { home: string; project: string; crossRootConfirm: boolean }>
  >({})
  const composerRef = useRef<HTMLTextAreaElement | null>(null)
  const chatEndRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    void ensureLocalSessionToken().then((t) => setHasLocalSession(Boolean(t)))
  }, [desk?.generatedAt])

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
  }, [chat, askPending])

  useEffect(() => {
    const media = window.matchMedia('(max-width: 42rem)')
    const onChange = (event: MediaQueryListEvent) => {
      setCompactViewport(event.matches)
      setAttentionOpen(!event.matches)
    }
    media.addEventListener('change', onChange)
    return () => media.removeEventListener('change', onChange)
  }, [])

  function appendChat(turns: ChatTurn[]) {
    setChat((prev) => [...prev, ...turns].slice(-CHAT_LIMIT))
  }

  const deskMode: DeskMode = desk?.preferences?.deskMode ?? 'general'
  const advanced = deskMode === 'advanced'
  const ticketWatchEnabled = desk?.preferences?.ticketWatchEnabled !== false

  const load = useCallback(async () => {
    setError(null)
    try {
      const payload = await fetchSnapshot()
      setDesk(payload)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  useEffect(() => {
    if (!advanced && tab !== 'route' && tab !== 'settings') {
      setTab('route')
    }
  }, [advanced, tab])

  const visibleTabs = useMemo(() => {
    if (!advanced) return [] as { id: TabId; label: string }[]
    return [
      { id: 'route' as const, label: 'Route' },
      { id: 'projects' as const, label: 'Projects' },
      { id: 'recent' as const, label: 'Recent' },
      { id: 'health' as const, label: 'Health' },
    ]
  }, [advanced])

  async function onPortfolioRefresh() {
    setBusy(true)
    setError(null)
    setTicketWatchStatus(null)
    try {
      // Full-depth portfolio scan; never covers tickets (Scan tickets owns that).
      const payload = await refreshSnapshot(true)
      setDesk(payload)
      setTicketWatchStatus('Portfolio refreshed (non-ticket Attention only).')
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function onScanTickets() {
    if (!ticketWatchEnabled) {
      setTicketWatchStatus('Ticket Watch is off - turn it on to scan tickets.')
      return
    }
    setBusy(true)
    setError(null)
    setTicketWatchStatus(null)
    try {
      const res = await watchTickets(false)
      setDesk(res.desk)
      const w = res.watch
      if (w.warning) {
        setTicketWatchStatus(w.warning)
      } else if (!w.available) {
        setTicketWatchStatus('TicketTracker not available - ticket scan skipped.')
      } else {
        const draftBit =
          w.draftAvailable || w.draftsWritten > 0
            ? ` Draft available (${w.draftsWritten}).`
            : ''
        const evidenceStatus = (() => {
          if (!(w.nextEvidenceAvailable || (w.evidenceSuggestions ?? 0) > 0)) return ''
          if (w.readyForRecommendation) {
            return ` Next evidence (${w.evidenceSuggestions}). Ready for recommendation.`
          }
          return ` Next evidence (${w.evidenceSuggestions}).`
        })()
        setTicketWatchStatus(
          `Tickets (${w.scope}): scanned ${w.scanned} - added ${w.added}, refreshed ${w.refreshed}, unchanged ${w.unchanged}.${draftBit}${evidenceStatus} No iSupport writes.`,
        )
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function onToggleTicketWatch(next: boolean) {
    setBusy(true)
    setError(null)
    try {
      const prefs = await putPreferences(deskMode, undefined, undefined, next)
      setDesk((prev) => (prev ? { ...prev, preferences: prefs } : prev))
      setTicketWatchStatus(
        next
          ? 'Ticket Watch on - Scan tickets is available. Portfolio refresh still ignores tickets.'
          : 'Ticket Watch off - Scan tickets disabled. Portfolio refresh never covers tickets.',
      )
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function onToggleAdvanced(next: boolean) {
    setBusy(true)
    setError(null)
    try {
      const prefs = await putPreferences(next ? 'advanced' : 'general')
      setDesk((prev) =>
        prev
          ? {
              ...prev,
              preferences: prefs,
            }
          : prev,
      )
      if (!next) {
        setTab('route')
        setSettingsOpen(false)
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function onAttentionVisibleCount(next: number) {
    setBusy(true)
    setError(null)
    try {
      const normalized = normalizeAttentionVisibleCount(next)
      const prefs = await putPreferences(deskMode, normalized)
      setDesk((prev) => (prev ? { ...prev, preferences: prefs } : prev))
      setAttentionShowAll(false)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function onEditorCommand(next: string) {
    setBusy(true)
    setError(null)
    try {
      const prefs = await putPreferences(deskMode, undefined, next)
      setDesk((prev) => (prev ? { ...prev, preferences: prefs } : prev))
      // meta.editor is resolved during snapshot build, so re-read for the new label.
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function loadAskEnginePanel() {
    try {
      const panel = await fetchAskEngine()
      setAskEnginePanel(panel)
    } catch {
      setAskEnginePanel(null)
    }
  }

  async function loadSettingsPortfolio() {
    try {
      const portfolio = await fetchSettings()
      setSettingsPortfolio(portfolio)
      setRootsDraft(portfolioRootsToDrafts(portfolio))
      const role = portfolio.machineRole
      setMachineRoleDraft(role === 'Hq' || role === 'Satellite' || role === 'Standalone' ? role : 'Standalone')
      setOpsBaseUrlDraft(portfolio.opsBaseUrl ?? '')
    } catch {
      setSettingsPortfolio(null)
    }
  }

  async function onSaveMachineRole() {
    setBusy(true)
    setError(null)
    setSettingsStatus(null)
    try {
      const body: Parameters<typeof putSettings>[0] = {
        machineRole: machineRoleDraft,
      }
      if (opsBaseUrlDraft.trim()) {
        body.opsBaseUrl = opsBaseUrlDraft.trim()
      } else {
        body.clearOpsBaseUrl = true
      }
      const result = await putSettings(body)
      setSettingsPortfolio(result.portfolio)
      const role = result.portfolio.machineRole
      setMachineRoleDraft(role === 'Hq' || role === 'Satellite' || role === 'Standalone' ? role : machineRoleDraft)
      setOpsBaseUrlDraft(result.portfolio.opsBaseUrl ?? '')
      setSettingsStatus('Role saved.')
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function loadProductUpdates(force = false) {
    try {
      const updates = await fetchUpdates(force)
      setProductUpdates(updates)
    } catch {
      setProductUpdates(null)
    }
  }

  async function loadProfileSyncStatus() {
    try {
      const status = await fetchProfileStatus()
      setProfileSyncStatus(status)
    } catch {
      setProfileSyncStatus(null)
    }
  }

  useEffect(() => {
    if (!settingsOpen && tab !== 'settings') return
    void loadSettingsPortfolio()
    void loadProductUpdates(false)
    void loadProfileSyncStatus()
    // eslint-disable-next-line react-hooks/exhaustive-deps -- load when Settings opens
  }, [settingsOpen, tab])

  async function onDownloadProfilePack() {
    setBusy(true)
    setError(null)
    setSettingsStatus(null)
    try {
      await downloadProfileExport()
      setSettingsStatus('Downloaded metra-profile.zip.')
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function onIssueProfileSyncToken(rotate: boolean) {
    setBusy(true)
    setError(null)
    setSettingsStatus(null)
    try {
      const issued = await issueProfileSyncToken(rotate)
      if (issued.token) {
        setProfileSyncTokenShown(issued.token)
        setSettingsStatus(issued.message || 'Sync token issued. Copy it for the satellite.')
      } else {
        setProfileSyncTokenShown(null)
        setSettingsStatus(issued.message || 'Token already exists. Use Rotate to mint a new one.')
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function onCopyProfileSyncToken() {
    if (!profileSyncTokenShown) return
    try {
      await navigator.clipboard.writeText(profileSyncTokenShown)
      setSettingsStatus('Sync token copied to clipboard.')
    } catch {
      setError('Could not copy token to clipboard.')
    }
  }

  async function onCheckUpdates() {
    setBusy(true)
    setError(null)
    setSettingsStatus(null)
    try {
      await loadProductUpdates(true)
      setSettingsStatus('Checked for updates.')
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function onUpdateProduct(target: 'metra' | 'ollama') {
    setBusy(true)
    setError(null)
    setSettingsStatus(null)
    try {
      const result = await postProductUpdate(target)
      if (result.updates) setProductUpdates(result.updates)
      else await loadProductUpdates(true)
      const baseMsg = result.message || (result.ok ? 'Update finished.' : 'Update failed.')
      setSettingsStatus(
        result.restartRequired ? `${baseMsg} Restart Metra Ops to finish.` : baseMsg,
      )
      if (!result.ok) setError(result.message || 'Update failed.')
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function onSavePortfolioFolders() {
    setBusy(true)
    setError(null)
    setSettingsStatus(null)
    try {
      if (rootsDraft.length === 0) {
        throw new Error('Add at least one projects folder.')
      }
      if (!rootsDraft.some((r) => r.primary)) {
        throw new Error('Mark one folder as primary.')
      }
      for (const r of rootsDraft) {
        if (!r.label.trim()) throw new Error('Each folder needs a label.')
        if (!r.path.trim()) throw new Error(`Folder "${r.label.trim()}" needs a path.`)
      }
      const result = await putSettings({
        roots: rootsDraft.map((r) => ({
          name: r.name || undefined,
          label: r.label.trim(),
          path: r.path.trim(),
          primary: r.primary,
          optional: r.primary ? false : r.optional,
        })),
      })
      setSettingsPortfolio(result.portfolio)
      setRootsDraft(portfolioRootsToDrafts(result.portfolio))
      setSettingsStatus('Projects folders saved. Refresh the desk to reload project lists.')
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  function updateRootDraft(key: string, patch: Partial<RootDraft>) {
    setRootsDraft((prev) =>
      prev.map((row) => {
        if (row.key !== key) return row
        const next = { ...row, ...patch }
        if (next.primary) next.optional = false
        return next
      }),
    )
  }

  function setPrimaryRootDraft(key: string) {
    setRootsDraft((prev) =>
      prev.map((row) => ({
        ...row,
        primary: row.key === key,
        optional: row.key === key ? false : row.optional,
      })),
    )
  }

  function addRootDraft() {
    setRootsDraft((prev) => [
      ...prev,
      {
        key: newRootDraftKey(),
        name: '',
        label: `Folder ${prev.length + 1}`,
        path: '',
        primary: prev.length === 0,
        optional: prev.length > 0,
      },
    ])
  }

  function removeRootDraft(key: string) {
    setRootsDraft((prev) => {
      if (prev.length <= 1) return prev
      const next = prev.filter((r) => r.key !== key)
      if (!next.some((r) => r.primary) && next.length > 0) {
        next[0] = { ...next[0], primary: true, optional: false }
      }
      return next
    })
  }

  async function onSaveCursorApiKey() {
    if (!cursorKeyDraft.trim()) {
      setError('Paste a Cursor API key first, or use Clear key.')
      return
    }
    setBusy(true)
    setError(null)
    setSettingsStatus(null)
    try {
      const result = await putSettings({ cursorApiKey: cursorKeyDraft.trim() })
      setSettingsPortfolio(result.portfolio)
      setCursorKeyDraft('')
      setSettingsStatus('Cursor API key saved for Ask (User environment).')
      await loadAskEnginePanel()
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function onClearCursorApiKey() {
    setBusy(true)
    setError(null)
    setSettingsStatus(null)
    try {
      const result = await putSettings({ clearCursorApiKey: true })
      setSettingsPortfolio(result.portfolio)
      setCursorKeyDraft('')
      setSettingsStatus('Cursor API key cleared.')
      await loadAskEnginePanel()
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function onAskAcceptRecommended() {
    setBusy(true)
    setError(null)
    try {
      await postAskEngineAccept()
      await loadAskEnginePanel()
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function onAskEngineSet(engine: string) {
    setBusy(true)
    setError(null)
    try {
      await postAskEngineSet(engine)
      await loadAskEnginePanel()
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  function continuityLabel(c: import('./types').AskContinuity | null | undefined): string | null {
    if (!c) return null
    const bits: string[] = []
    if (c.usedSummarization && c.summarizedTurnCount) {
      bits.push(`Summarized ${c.summarizedTurnCount} earlier turn(s)`)
    }
    if (c.recallSessionId) {
      bits.push(`Recall session ${c.recallSessionId.slice(0, 8)}…`)
    }
    return bits.length ? bits.join(' · ') : null
  }

  function startNewAskSession() {
    setChat([])
    setAskSessionId(null)
    setRecallSessionId(null)
    setContinuityNote(null)
    setResolveStatus('Started a new Ask session.')
  }

  async function resumeAskSession(sessionId: string) {
    if (!sessionId) return
    setBusy(true)
    setError(null)
    try {
      const payload = await fetchAskJournalSession(sessionId)
      const turns = payload.turns ?? []
      const rebuilt: ChatTurn[] = []
      for (const t of turns) {
        if (t.prompt) {
          rebuilt.push({
            id: `${t.id}-you`,
            role: 'you',
            text: t.prompt,
            sessionId: t.sessionId || sessionId,
          })
        }
        if (t.message) {
          rebuilt.push({
            id: `${t.id}-metra`,
            role: 'metra',
            text: stripAskUiChrome(t.message),
            answered: true,
            handoff: t.handoff,
            turnId: t.id,
            sessionId: t.sessionId || sessionId,
          })
        }
      }
      setChat(rebuilt.slice(-CHAT_LIMIT))
      setAskSessionId(sessionId)
      setRecallSessionId(null)
      setContinuityNote(continuityLabel(payload.continuity) || 'Resumed from Session Journal.')
      setTab('route')
      setSettingsOpen(false)
      setResolveStatus('Resumed Ask session from Recent.')
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setBusy(false)
    }
  }

  function recallAskSession(sessionId: string) {
    if (!sessionId) return
    setRecallSessionId(sessionId)
    setTab('route')
    setSettingsOpen(false)
    setResolveStatus('Recall armed - next Ask includes that journal session as labeled evidence.')
  }

  async function runAsk(question: string, imageIds?: string[]) {
    const ids = (imageIds ?? []).filter(Boolean).slice(0, 3)
    const q = question.trim()
    if (!q && ids.length === 0) return
    const displayPrompt = q || 'Describe what matters in this screenshot for the next check.'
    setPrompt('')
    setBusy(true)
    setAskPending(true)
    setError(null)
    const youId = nextChatId()
    appendChat([
      {
        id: youId,
        role: 'you',
        text: ids.length > 0 ? `${displayPrompt} [${ids.length} image(s)]` : displayPrompt,
      },
    ])
    try {
      const result = await postAsk(q, askSessionId, recallSessionId, ids)
      if (result.sessionId) setAskSessionId(result.sessionId)
      setContinuityNote(continuityLabel(result.continuity))
      // Prefer journal/scrubbed prompt so chat state does not keep raw secrets.
      if (result.secretsScrubbed && result.entry?.prompt) {
        setChat((prev) =>
          prev.map((t) => (t.id === youId ? { ...t, text: result.entry!.prompt } : t)),
        )
      }
      appendChat([
        {
          id: nextChatId(),
          role: 'metra',
          text: stripAskUiChrome(result.message || ''),
          answered: Boolean(result.answered),
          answerType: result.answerType || null,
          evidenceQuality: result.evidenceQuality || null,
          nextStep: result.nextStep || null,
          handoff: result.handoff,
          showWhere: Boolean(result.showWhere),
          suggestCapture: Boolean(result.suggestCapture),
          turnId: result.entry?.id || null,
          sessionId: result.sessionId || result.entry?.sessionId || askSessionId,
        },
      ])
      if (ids.length > 0) {
        setPlaceFiles((prev) => prev.filter((f) => !ids.includes(f.id)))
        setPlacePreviews((prev) => {
          const next = { ...prev }
          for (const id of ids) {
            if (next[id]) {
              URL.revokeObjectURL(next[id])
              delete next[id]
            }
          }
          return next
        })
      }
      await load()
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setAskPending(false)
      setBusy(false)
    }
  }

  async function onSaveAskTurn(turn: ChatTurn) {
    if (!turn.turnId) return
    setBusy(true)
    setResolveStatus(null)
    try {
      const res = await postCapturePropose({
        turnId: turn.turnId,
        sessionId: turn.sessionId || askSessionId,
      })
      const rows = (res.proposals ?? []).map((p) => ({
        ...p,
        accepted: true,
      }))
      if (rows.length === 0) {
        // Fallback: single create when propose returns empty (legacy path).
        await postCaptureFromAsk(turn.turnId, turn.sessionId || askSessionId)
        setResolveStatus('Saved for later in Metra Capture Inbox.')
        setCaptureProposeOpen(false)
        setCaptureProposals([])
        await load()
        return
      }
      setCaptureProposals(rows)
      setCaptureProposeOpen(true)
      setResolveStatus('Review proposed Capture rows, then Create selected.')
    } catch (e) {
      setResolveStatus(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function onCreateAcceptedCaptures() {
    const accepted = captureProposals.filter((p) => p.accepted)
    if (accepted.length === 0) {
      setResolveStatus('Select at least one proposal to create.')
      return
    }
    setBusy(true)
    try {
      const res = await postCaptureAccepted(
        accepted.map((p) => ({
          proposalId: p.proposalId,
          summary: p.summary,
          suggestedHome: p.suggestedHome,
          suggestedProject: p.suggestedProject,
          derivedFrom: p.derivedFrom,
          accepted: true,
        })),
      )
      setCaptureProposeOpen(false)
      setCaptureProposals([])
      setResolveStatus(
        `Created ${res.count ?? res.items?.length ?? 0} Capture candidate(s). Promote from Captures when ready.`,
      )
      await load()
    } catch (e) {
      setResolveStatus(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function onDismissCapture(id: string) {
    setBusy(true)
    try {
      await postCaptureDismiss(id)
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  function captureDraftFor(c: CaptureItem) {
    const existing = captureDrafts[c.id]
    if (existing) return existing
    return {
      home: c.suggestedHome || 'FutureDevelopment',
      project: c.suggestedProject || '',
      crossRootConfirm: false,
    }
  }

  function patchCaptureDraft(
    id: string,
    patch: Partial<{ home: string; project: string; crossRootConfirm: boolean }>,
    seed?: CaptureItem,
  ) {
    setCaptureDrafts((prev) => {
      const base =
        prev[id] ||
        (seed
          ? {
              home: seed.suggestedHome || 'FutureDevelopment',
              project: seed.suggestedProject || '',
              crossRootConfirm: false,
            }
          : { home: 'FutureDevelopment', project: '', crossRootConfirm: false })
      return { ...prev, [id]: { ...base, ...patch } }
    })
  }

  async function onPromoteCapture(id: string, seed?: CaptureItem) {
    const draft = seed ? captureDraftFor(seed) : captureDrafts[id]
    const home = draft?.home || seed?.suggestedHome || 'FutureDevelopment'
    if (home === 'ProjectAgents' || home === 'TicketTracker') {
      setError(
        home === 'ProjectAgents'
          ? 'ProjectAgents is suggest-only. Edit AGENTS.md in Cursor, or promote to ProjectBacklog instead.'
          : 'TicketTracker promote is suggest-only. Use TicketTracker note/brief; Capture does not write iSupport.',
      )
      return
    }
    if (home === 'ProjectBacklog' && !hasLocalSession) {
      setError(
        'ProjectBacklog promote requires a local Metra session. Use Host/CLI, or promote to FutureDevelopment / OCC / DecisionRegistry from remote.',
      )
      return
    }
    setBusy(true)
    try {
      await postCapturePromote(id, {
        home,
        project: draft?.project || seed?.suggestedProject || undefined,
        crossRootConfirm: draft?.crossRootConfirm === true,
      })
      setResolveStatus('Promoted capture into the affirmed home.')
      setCaptureDrafts((prev) => {
        const next = { ...prev }
        delete next[id]
        return next
      })
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  function putSomewhereFromAsk(turn: ChatTurn) {
    const fromYou =
      [...chat].reverse().find((t) => t.role === 'you')?.text ||
      turn.text ||
      ''
    const seed = fromYou.trim()
    if (!seed) {
      setPlaceStatus('Nothing to put somewhere yet.')
      return
    }
    setPrompt(seed)
    setPlaceResult(null)
    setPlaceStatus('Seeded from Ask - review, then Put somewhere.')
    setTab('route')
    setSettingsOpen(false)
    requestAnimationFrame(() => {
      composerRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' })
      composerRef.current?.focus()
    })
  }

  async function onAsk(e: FormEvent) {
    e.preventDefault()
    const imageIds = placeFiles.filter(isAskImageFile).map((f) => f.id)
    await runAsk(prompt.trim(), imageIds)
  }

  function onAskFromAttention(seed: string) {
    setResolveStatus(null)
    void runAsk(seed.trim())
  }

  async function onPastePlace() {
    setPlaceStatus(null)
    try {
      if (navigator.clipboard?.read) {
        const items = await navigator.clipboard.read()
        const imageFiles: File[] = []
        for (const item of items) {
          const type = item.types.find((t) => t.startsWith('image/'))
          if (!type) continue
          const blob = await item.getType(type)
          const ext = type.includes('jpeg')
            ? 'jpg'
            : type.includes('png')
              ? 'png'
              : type.includes('webp')
                ? 'webp'
                : type.includes('gif')
                  ? 'gif'
                  : 'png'
          imageFiles.push(new File([blob], `paste-${Date.now()}.${ext}`, { type }))
        }
        if (imageFiles.length > 0) {
          await stageFiles(imageFiles)
          setPlaceStatus(`Pasted ${imageFiles.length} image(s) for Ask or Put somewhere`)
          composerRef.current?.focus()
          return
        }
      }
      if (navigator.clipboard?.readText) {
        const text = await navigator.clipboard.readText()
        if (text) {
          setPrompt((prev) => (prev ? `${prev.trim()}\n${text}` : text))
          setPlaceStatus('Pasted - review then Put somewhere')
          composerRef.current?.focus()
          return
        }
      }
      throw new Error('blocked')
    } catch {
      composerRef.current?.focus()
      setPlaceStatus('Clipboard blocked on this page - long-press and paste into the box')
    }
  }

  async function stageFiles(fileList: FileList | File[]) {
    const files = Array.from(fileList)
    if (!files.length) return
    setPlacePending(true)
    setPlaceStatus(null)
    try {
      const uploaded: PlaceUploadMeta[] = []
      const previewAdds: Record<string, string> = {}
      for (const f of files) {
        const meta = await postPlaceUpload(f)
        uploaded.push(meta)
        if (isAskImageFile(f) || isAskImageFile(meta)) {
          previewAdds[meta.id] = URL.createObjectURL(f)
        }
      }
      setPlaceFiles((prev) => [...prev, ...uploaded])
      if (Object.keys(previewAdds).length > 0) {
        setPlacePreviews((prev) => ({ ...prev, ...previewAdds }))
      }
      const imageCount = uploaded.filter(isAskImageFile).length
      const otherCount = uploaded.length - imageCount
      if (imageCount > 0 && otherCount === 0) {
        setPlaceStatus(`Staged ${imageCount} image(s) - Ask or Put somewhere`)
      } else if (imageCount > 0) {
        setPlaceStatus(
          `Staged ${imageCount} image(s) for Ask; ${otherCount} other file(s) for Put somewhere`,
        )
      } else {
        setPlaceStatus(`Staged ${uploaded.length} file(s) for Put somewhere`)
      }
    } catch (e) {
      setPlaceStatus(e instanceof Error ? e.message : String(e))
    } finally {
      setPlacePending(false)
    }
  }

  async function onRouteSomething() {
    const text = prompt.trim()
    if (!text && placeFiles.length === 0) return
    setPlaceText(text)
    setPlacePending(true)
    setBusy(true)
    setPlaceStatus(null)
    setPlaceResult(null)
    try {
      const result = await postPlace(
        text || placeFiles.map((f) => f.fileName).join(' '),
        placeFiles.map((f) => f.id),
      )
      setPlaceResult(result)
      setPrompt('')
    } catch (err) {
      setPlaceStatus(err instanceof Error ? err.message : String(err))
    } finally {
      setPlacePending(false)
      setBusy(false)
    }
  }

  const showSettings = settingsOpen || tab === 'settings'
  const showRoute = !showSettings && (!advanced || tab === 'route')
  const askImageFiles = placeFiles.filter(isAskImageFile)
  const placeOtherFiles = placeFiles.filter((f) => !isAskImageFile(f))
  const canAsk =
    !busy && (prompt.trim().length > 0 || askImageFiles.length > 0)
  const askEngineName = String(askEnginePanel?.capability?.engine || '').toLowerCase()
  const imageVisionDegrade =
    askImageFiles.length > 0 && askEngineName.length > 0 && askEngineName !== 'cursor'
  const attentionWaiting =
    desk?.attentionCount ??
    desk?.attention?.activeCount ??
    (desk?.nextAttention ? 1 : 0)
  const attentionHeld = desk?.attention?.heldCount ?? desk?.attention?.held?.length ?? 0
  const attentionVisibleCount = normalizeAttentionVisibleCount(
    desk?.attention?.visibleCount ??
      desk?.preferences?.attentionVisibleCount ??
      DEFAULT_ATTENTION_VISIBLE_COUNT,
  )

  return (
    <div className="app">
      <header className="topbar">
        {!showRoute && (
          <PresenceBrand
            askPending={askPending}
            attentionWaiting={attentionWaiting}
            attentionEmptyHint={desk?.attentionEmptyHint}
            gitChecked={desk?.gitChecked}
            generatedAt={desk?.generatedAt}
          />
        )}
        <button
          type="button"
          className="icon-btn"
          aria-label="Settings"
          onClick={() => {
            setSettingsOpen((v) => !v)
            if (!settingsOpen) setTab('settings')
            else setTab('route')
          }}
        >
          Settings
        </button>
      </header>

      {advanced && !showSettings && (
        <nav className="tabs" aria-label="Desk sections">
          {visibleTabs.map((t) => (
            <button
              key={t.id}
              type="button"
              className={`tab${tab === t.id ? ' active' : ''}`}
              onClick={() => setTab(t.id)}
            >
              {t.label}
            </button>
          ))}
        </nav>
      )}

      {error && <p className="error">{error}</p>}

      {showRoute && (
        <div className="desk-stack">
          <div className="desk-presence-stack">
            <PresenceBrand
              askPending={askPending}
              attentionWaiting={attentionWaiting}
              attentionEmptyHint={desk?.attentionEmptyHint}
              gitChecked={desk?.gitChecked}
              generatedAt={desk?.generatedAt}
            />
          <section className="panel panel-ask">
            <div className="panel-heading">
              <h2>Where should we start?</h2>
              <div className="actions">
                <button
                  type="button"
                  className="btn btn-secondary"
                  disabled={busy || askPending || (chat.length === 0 && !askSessionId && !recallSessionId)}
                  onClick={() => startNewAskSession()}
                >
                  New session
                </button>
              </div>
            </div>
            {recallSessionId && (
              <p className="continuity-note" role="status">
                Recall armed: <code>{recallSessionId.slice(0, 12)}…</code>
                {' · '}
                <button
                  type="button"
                  className="linkish"
                  disabled={busy}
                  onClick={() => setRecallSessionId(null)}
                >
                  Clear
                </button>
              </p>
            )}
            {continuityNote && !recallSessionId && (
              <p className="continuity-note muted" role="status">
                {continuityNote}
              </p>
            )}
            <form className="ask-row shared-composer" onSubmit={onAsk}>
              <textarea
                ref={composerRef}
                value={prompt}
                onChange={(e) => setPrompt(e.target.value)}
                placeholder="Idea, question, or rough draft…"
                aria-label="Where should we start"
                onDragOver={(e) => e.preventDefault()}
                onDrop={(e) => {
                  e.preventDefault()
                  if (e.dataTransfer.files?.length) void stageFiles(e.dataTransfer.files)
                }}
              />
              <div className="actions composer-actions">
                <button
                  type="submit"
                  className="btn btn-primary"
                  disabled={!canAsk}
                  title={
                    placeOtherFiles.length > 0 && askImageFiles.length === 0 && !prompt.trim()
                      ? 'Non-image attachments go with Put somewhere.'
                      : imageVisionDegrade
                        ? 'Images need the Cursor Ask engine for vision in this release.'
                        : undefined
                  }
                >
                  {askPending ? 'Working...' : 'Ask'}
                </button>
                <button
                  type="button"
                  className="btn btn-secondary"
                  disabled={
                    busy ||
                    placePending ||
                    (!prompt.trim() && placeFiles.length === 0)
                  }
                  onClick={() => void onRouteSomething()}
                >
                  {placePending ? 'Recommending...' : 'Put somewhere'}
                </button>
                <button
                  type="button"
                  className="btn btn-quiet"
                  disabled={busy || placePending}
                  onClick={() => void onPastePlace()}
                >
                  Paste
                </button>
                <label className="btn btn-quiet file-btn">
                  Attach
                  <input
                    type="file"
                    multiple
                    accept=".png,.jpg,.jpeg,.gif,.webp,.txt,.md,.json,.csv,.log,.pdf,.xml,.yaml,.yml,.ps1,.sql,.html,.htm,image/*"
                    hidden
                    onChange={(e) => {
                      if (e.target.files?.length) void stageFiles(e.target.files)
                      e.target.value = ''
                    }}
                  />
                </label>
              </div>
              <p className="composer-trust muted">
                Ask starts a conversation. Put somewhere recommends a home. Nothing is created until
                you choose a next step.
              </p>
              {imageVisionDegrade && (
                <p className="composer-file-note muted">
                  Screenshots need the Cursor Ask engine for vision. Current engine will degrade
                  honestly if you Ask with images.
                </p>
              )}
              {placeFiles.length > 0 && (
                <>
                  <p className="composer-file-note muted">
                    {askImageFiles.length > 0 && placeOtherFiles.length === 0
                      ? 'Images go with Ask (vision-read) or Put somewhere.'
                      : askImageFiles.length > 0
                        ? 'Images go with Ask; other attachments go with Put somewhere.'
                        : 'Attachments go with Put somewhere.'}
                  </p>
                  <ul className="place-files">
                    {placeFiles.map((f) => (
                      <li key={f.id}>
                        {placePreviews[f.id] ? (
                          <img
                            className="place-file-thumb"
                            src={placePreviews[f.id]}
                            alt={f.fileName}
                          />
                        ) : null}
                        <span>
                          {f.fileName}
                          {isAskImageFile(f) ? ' (Ask)' : ' (Put)'}
                        </span>
                        <button
                          type="button"
                          className="btn btn-quiet"
                          onClick={() => {
                            setPlaceFiles((prev) => prev.filter((x) => x.id !== f.id))
                            setPlacePreviews((prev) => {
                              const next = { ...prev }
                              if (next[f.id]) {
                                URL.revokeObjectURL(next[f.id])
                                delete next[f.id]
                              }
                              return next
                            })
                          }}
                        >
                          Remove
                        </button>
                      </li>
                    ))}
                  </ul>
                </>
              )}
              {placeStatus && !placeResult?.ok && (
                <p className="muted resolve-status">{placeStatus}</p>
              )}
            </form>
            {(chat.length > 0 || askPending) && (
              <div className="chat" aria-live="polite" aria-label="Ask history">
                {chat.map((turn) => (
                  <div key={turn.id} className={`chat-turn chat-turn-${turn.role}`}>
                    <div className="chat-role">{turn.role === 'you' ? 'You' : 'Reply'}</div>
                    {turn.text &&
                      (turn.role === 'you' ? (
                        <p className="chat-you">{turn.text}</p>
                      ) : (
                        <AskMarkdown
                          text={turn.text}
                          className={turn.answered ? 'ask-reply' : 'ask-unavailable'}
                        />
                      ))}
                    {turn.role === 'metra' && turn.showWhere && turn.handoff && (
                      <WhereChip
                        handoff={turn.handoff}
                        sourceText={
                          [...chat].reverse().find((t) => t.role === 'you')?.text || turn.text
                        }
                        onCorrected={(msg) => setResolveStatus(msg)}
                      />
                    )}
                    {turn.role === 'metra' &&
                      (turn.answerType || turn.evidenceQuality) &&
                      !['greeting', 'observation', 'park'].includes(
                        String(turn.answerType || '').toLowerCase(),
                      ) && (
                        <p className="muted small" style={{ marginTop: '0.35rem' }}>
                          {[
                            turn.answerType ? `answer=${turn.answerType}` : null,
                            turn.evidenceQuality ? `evidence=${turn.evidenceQuality}` : null,
                          ]
                            .filter(Boolean)
                            .join(' · ')}
                        </p>
                      )}
                    {turn.role === 'metra' && turn.turnId && (
                      <div className="actions wrap">
                        <button
                          type="button"
                          className={turn.suggestCapture ? 'btn btn-primary' : 'btn btn-secondary'}
                          disabled={busy}
                          onClick={() => void onSaveAskTurn(turn)}
                        >
                          Save for portfolio
                        </button>
                        <button
                          type="button"
                          className="btn btn-secondary"
                          disabled={busy}
                          onClick={() => putSomewhereFromAsk(turn)}
                        >
                          Put somewhere
                        </button>
                      </div>
                    )}
                  </div>
                ))}
                {askPending && (
                  <div className="chat-turn chat-turn-metra chat-pending" aria-busy="true">
                    <div className="chat-role">Reply</div>
                    <p className="ask-pending">Working on that...</p>
                  </div>
                )}
                <div ref={chatEndRef} />
              </div>
            )}
            {captureProposeOpen && captureProposals.length > 0 && (
              <div className="capture-propose-sheet" role="region" aria-label="Capture proposals">
                <h3>Save for portfolio</h3>
                <p className="muted small">
                  Affirm rows to create Capture candidates. Nothing is written until you Create
                  selected.
                </p>
                <ul className="list">
                  {captureProposals.map((p, idx) => (
                    <li key={p.proposalId || idx}>
                      <label className="settings-check">
                        <input
                          type="checkbox"
                          checked={p.accepted}
                          disabled={busy}
                          onChange={(e) => {
                            const accepted = e.target.checked
                            setCaptureProposals((prev) =>
                              prev.map((row, i) =>
                                i === idx ? { ...row, accepted } : row,
                              ),
                            )
                          }}
                        />
                        <span>
                          <strong>{p.summary}</strong>
                        </span>
                      </label>
                      <div className="muted small">
                        {p.suggestedHome}
                        {p.suggestedProject ? ` · ${p.suggestedProject}` : ''}
                        {p.rootLabel ? ` · root ${p.rootLabel}` : ''}
                        {p.requiresHostSession ? ' · needs Host session' : ''}
                        {p.requiresCrossRoot ? ' · cross-root' : ''}
                      </div>
                    </li>
                  ))}
                </ul>
                <div className="actions wrap">
                  <button
                    type="button"
                    className="btn btn-primary"
                    disabled={busy || !captureProposals.some((p) => p.accepted)}
                    onClick={() => void onCreateAcceptedCaptures()}
                  >
                    Create selected
                  </button>
                  <button
                    type="button"
                    className="btn btn-secondary"
                    disabled={busy}
                    onClick={() => {
                      setCaptureProposeOpen(false)
                      setCaptureProposals([])
                      setResolveStatus(null)
                    }}
                  >
                    Cancel
                  </button>
                </div>
              </div>
            )}
          </section>
          </div>

          <section
            className={`panel panel-attention${attentionOpen ? ' attention-expanded' : ''}`}
          >
            <div className="panel-heading attention-heading">
              <button
                type="button"
                className="attention-toggle"
                aria-expanded={attentionOpen}
                aria-label={`Attention has ${attentionWaiting} waiting${attentionHeld > 0 ? `, ${attentionHeld} held` : ''}. ${
                  attentionOpen ? 'Collapse' : 'Expand'
                } attention${compactViewport ? ' on mobile' : ''}.`}
                onClick={() => setAttentionOpen((open) => !open)}
              >
                <span className="attention-toggle-title">Attention</span>
                <span className="attention-toggle-count">
                  {attentionWaiting} waiting
                  {attentionHeld > 0 ? ` · ${attentionHeld} held` : ''}
                  <span aria-hidden="true">{attentionOpen ? ' ▾' : ' ▸'}</span>
                </span>
              </button>
              {attentionOpen && (
                <div className="actions attention-refresh">
                  <button
                    type="button"
                    className="btn btn-secondary"
                    disabled={busy}
                    title="Refresh non-ticket Attention (git, drift, verify, decisions). Does not scan tickets."
                    onClick={() => void onPortfolioRefresh()}
                  >
                    {busy ? 'Refreshing...' : 'Portfolio refresh'}
                  </button>
                  <label
                    className="switch"
                    title="Enable gate for Scan tickets. Portfolio refresh never covers tickets."
                  >
                    <input
                      type="checkbox"
                      checked={ticketWatchEnabled}
                      disabled={busy}
                      onChange={(e) => void onToggleTicketWatch(e.target.checked)}
                      aria-label="Ticket Watch"
                    />
                    Ticket Watch
                  </label>
                  <button
                    type="button"
                    className="btn btn-secondary"
                    disabled={busy || !ticketWatchEnabled}
                    title={
                      ticketWatchEnabled
                        ? 'Mine-scope tickets into Attention. No iSupport writes.'
                        : 'Turn Ticket Watch on to scan tickets.'
                    }
                    onClick={() => void onScanTickets()}
                  >
                    {busy ? 'Scanning...' : 'Scan tickets'}
                  </button>
                </div>
              )}
            </div>
            {attentionOpen && ticketWatchStatus && (
              <p className="place-ack" role="status" aria-live="polite">
                {ticketWatchStatus}
              </p>
            )}
            {attentionOpen && (() => {
              const active = desk?.attention?.active ?? (desk?.nextAttention ? [desk.nextAttention] : [])
              const held = desk?.attention?.held ?? []
              const heldCount = desk?.attention?.heldCount ?? held.length
              const heldKeys = held.map((h) => attentionItemKey(h))
              const visibleRows = attentionShowAll
                ? active
                : active.slice(0, attentionVisibleCount)
              const focused =
                active.find((a) => attentionItemKey(a) === selectedAttentionKey) ??
                visibleRows[0] ??
                active[0] ??
                null
              const selectedHeldKeyResolved =
                selectedHeldKey && heldKeys.includes(selectedHeldKey)
                  ? selectedHeldKey
                  : heldKeys[0] ?? null
              const selectedHeld =
                held.find((h) => attentionItemKey(h) === selectedHeldKeyResolved) ??
                held[0] ??
                null
              const overflowCount = Math.max(0, active.length - attentionVisibleCount)
              const notRechecked = desk?.attention?.notRecheckedCount ?? 0

              const heldBlock =
                heldCount > 0 && selectedHeld ? (
                  <div className="holding-block">
                    <h3>Keeping in view ({heldCount})</h3>
                    {desk?.attention?.holdRoutingHint && (
                      <p className="muted hold-hint">{desk.attention.holdRoutingHint}</p>
                    )}
                    {heldCount > 1 && (
                      <label className="attention-picker">
                        <span className="muted">Item</span>
                        <select
                          value={selectedHeldKeyResolved ?? ''}
                          onChange={(e) => setSelectedHeldKey(e.target.value || null)}
                        >
                          {held.map((h) => {
                            const key = attentionItemKey(h)
                            return (
                              <option key={key} value={key}>
                                {attentionPickerLabel(h)}
                              </option>
                            )
                          })}
                        </select>
                      </label>
                    )}
                    <AttentionCard
                      key={attentionItemKey(selectedHeld)}
                      item={selectedHeld}
                      advanced={advanced}
                      busy={busy}
                      onAskSeed={onAskFromAttention}
                      onStatus={setResolveStatus}
                      onDeskUpdate={setDesk}
                    />
                  </div>
                ) : null

              if (!focused) {
                return (
                  <div className="attention-empty">
                    <p className="attention">No active attention.</p>
                    <p className="muted">
                      {desk?.attentionEmptyHint ||
                        (desk && !desk.gitChecked
                          ? 'Nothing waiting from this light check. Run Portfolio refresh to confirm.'
                          : 'Nothing waiting from Portfolio refresh. Use Scan tickets when Ticket Watch is on.')}
                    </p>
                    {heldBlock}
                  </div>
                )
              }

              return (
                <div className="attention-block">
                  <p className="muted attention-count">
                    {desk?.attention?.activeCount ?? active.length} waiting
                    {notRechecked > 0 ? ` · ${notRechecked} not rechecked yet` : ''}
                  </p>
                  <div className="attention-list-region" role="list" aria-label="Attention summaries">
                    {visibleRows.map((item) => {
                      const key = attentionItemKey(item)
                      const selected = attentionItemKey(focused) === key
                      return (
                        <button
                          key={key}
                          type="button"
                          role="listitem"
                          className={`attention-summary-row${selected ? ' is-selected' : ''}`}
                          aria-pressed={selected}
                          onClick={() => setSelectedAttentionKey(key)}
                        >
                          <span className="attention-summary-label">
                            {attentionPickerLabel(item)}
                          </span>
                        </button>
                      )
                    })}
                  </div>
                  {overflowCount > 0 && (
                    <div className="actions attention-overflow-actions">
                      <button
                        type="button"
                        className="btn btn-quiet"
                        onClick={() => setAttentionShowAll((v) => !v)}
                      >
                        {attentionShowAll
                          ? 'Show fewer'
                          : `Show all (${active.length})`}
                      </button>
                    </div>
                  )}
                  <AttentionCard
                    key={attentionItemKey(focused)}
                    item={focused}
                    advanced={advanced}
                    busy={busy}
                    onAskSeed={onAskFromAttention}
                    onStatus={setResolveStatus}
                    onDeskUpdate={setDesk}
                    primary
                  />
                  {heldBlock}
                  {resolveStatus && <p className="muted resolve-status">{resolveStatus}</p>}
                </div>
              )
            })()}
          </section>

          {placeResult?.ok && (
            <section className="panel motion-panel panel-motion">
              <h2>Recommended place</h2>
              <p className="muted">
                Recommendation only. Nothing is created until you choose a next step.
              </p>
              <PlaceResultCard
                place={placeResult}
                intakeText={placeText.trim() || placeFiles.map((f) => f.fileName).join(' ')}
                attachmentIds={placeFiles.map((f) => f.id)}
                advanced={advanced}
                busy={busy || placePending}
                onStatus={setPlaceStatus}
                onDeskUpdate={setDesk}
              />
            </section>
          )}
        </div>
      )}

      {advanced && tab === 'projects' && !showSettings && (
        <section className="panel">
          <h2>Projects</h2>
          <ul className="list">
            {(desk?.projects ?? []).map((p) => (
              <li key={p.name}>
                <strong>{p.name}</strong>
                {p.pinned ? <span className="muted"> - pinned</span> : null}
                <div className="muted">
                  {p.present ? 'Present' : 'Missing'}
                  {p.purpose ? ` - ${p.purpose}` : ''}
                </div>
                {p.capabilities && p.capabilities.length > 0 && (
                  <div className="muted">Capabilities: {p.capabilities.join(', ')}</div>
                )}
                {p.serves && p.serves.length > 0 && (
                  <div className="muted">Serves: {p.serves.join(', ')}</div>
                )}
                {p.gitIsRepo && (
                  <div className="muted">
                    Git: {p.gitSummary || 'clean'}
                    {p.gitBranch ? ` on ${p.gitBranch}` : ''}
                  </div>
                )}
              </li>
            ))}
          </ul>
        </section>
      )}

      {advanced && tab === 'recent' && !showSettings && (
        <section className="panel">
          <h2>Recent conversations</h2>
          <p className="muted">
            Continuity window of recent Ask sessions - not permanent Metra memory. Resume reloads
            turns into Ask; Recall injects that session as labeled evidence on the next Ask.
            Snapshot: {desk?.generatedAt ?? 'n/a'}
          </p>
          <ul className="list">
            {(desk?.recent ?? []).length === 0 && (
              <li className="muted">No recent conversations yet.</li>
            )}
            {(desk?.recent ?? []).map((r) => {
              const session = r as AskSessionSummary
              const key = session.sessionId || session.id || session.at
              const sid = session.sessionId || session.id || ''
              return (
                <li key={key}>
                  <div>{session.prompt}</div>
                  <div className="muted">
                    {session.turnCount ? `${session.turnCount} turn(s) · ` : ''}
                    {session.where ? `${session.where} · ` : ''}
                    {session.origin ? `${session.origin} · ` : ''}
                    {session.at}
                  </div>
                  {sid ? (
                    <div className="actions wrap">
                      <button
                        type="button"
                        className="btn btn-primary"
                        disabled={busy}
                        onClick={() => void resumeAskSession(sid)}
                      >
                        Resume
                      </button>
                      <button
                        type="button"
                        className="btn btn-secondary"
                        disabled={busy}
                        onClick={() => recallAskSession(sid)}
                      >
                        Recall into Ask
                      </button>
                    </div>
                  ) : null}
                </li>
              )
            })}
          </ul>
          <h2>Captures</h2>
          <p className="muted">
            Portfolio intake candidates. Save for portfolio proposes rows first; Create selected parks
            here. Promote writes a durable home on affirm. Keep in view stays on Attention.
          </p>
          {!hasLocalSession && (
            <p className="muted small">
              No local Host session detected - ProjectBacklog promote is disabled until you open Ops
              from Host/loopback.
            </p>
          )}
          <ul className="list">
            {(desk?.captures ?? []).length === 0 && (
              <li className="muted">No capture candidates.</li>
            )}
            {(desk?.captures ?? []).map((c: CaptureItem) => {
              const draft = captureDraftFor(c)
              const promoteBlocked =
                draft.home === 'ProjectAgents' ||
                draft.home === 'TicketTracker' ||
                (draft.home === 'ProjectBacklog' && !hasLocalSession)
              return (
                <li key={c.id}>
                  <strong>{c.summary}</strong>
                  <div className="muted">
                    {c.suggestedHome || 'FutureDevelopment'}
                    {c.suggestedProject ? ` · ${c.suggestedProject}` : ''}
                    {c.derivedFrom?.type ? ` · from ${c.derivedFrom.type}` : ''}
                    {c.at ? ` · ${c.at}` : ''}
                  </div>
                  <div className="settings-roots" style={{ marginTop: '0.5rem' }}>
                    <label className="settings-field settings-field-compact">
                      <span className="muted">Home</span>
                      <select
                        disabled={busy}
                        value={draft.home}
                        onChange={(e) =>
                          patchCaptureDraft(c.id, { home: e.target.value }, c)
                        }
                      >
                        <option value="FutureDevelopment">FutureDevelopment</option>
                        <option value="OCC">OCC</option>
                        <option value="DecisionRegistry">DecisionRegistry</option>
                        <option value="ProjectBacklog">ProjectBacklog</option>
                        <option value="ProjectAgents">ProjectAgents (suggest-only)</option>
                        <option value="TicketTracker">TicketTracker (suggest-only)</option>
                      </select>
                    </label>
                    {(draft.home === 'ProjectBacklog' || draft.home === 'ProjectAgents') && (
                      <label className="settings-field settings-field-compact">
                        <span className="muted">Project</span>
                        <input
                          type="text"
                          disabled={busy}
                          value={draft.project}
                          onChange={(e) =>
                            patchCaptureDraft(c.id, { project: e.target.value }, c)
                          }
                          placeholder="Registered project name"
                          spellCheck={false}
                        />
                      </label>
                    )}
                    {draft.home === 'ProjectBacklog' && (
                      <label className="settings-check">
                        <input
                          type="checkbox"
                          disabled={busy}
                          checked={draft.crossRootConfirm}
                          onChange={(e) =>
                            patchCaptureDraft(
                              c.id,
                              { crossRootConfirm: e.target.checked },
                              c,
                            )
                          }
                        />
                        <span>Confirm cross-root write</span>
                      </label>
                    )}
                  </div>
                  <div className="actions wrap">
                    <button
                      type="button"
                      className="btn btn-primary"
                      disabled={busy || promoteBlocked}
                      title={
                        draft.home === 'ProjectAgents'
                          ? 'Suggest-only - edit AGENTS.md in Cursor'
                          : draft.home === 'TicketTracker'
                            ? 'Suggest-only - use TicketTracker note/brief'
                            : draft.home === 'ProjectBacklog' && !hasLocalSession
                              ? 'Requires local Host session'
                              : undefined
                      }
                      onClick={() => void onPromoteCapture(c.id, c)}
                    >
                      Promote
                    </button>
                    <button
                      type="button"
                      className="btn btn-secondary"
                      disabled={busy}
                      onClick={() => void onDismissCapture(c.id)}
                    >
                      Dismiss
                    </button>
                  </div>
                </li>
              )
            })}
          </ul>
        </section>
      )}

      {advanced && tab === 'health' && !showSettings && (
        <section className="panel">
          <h2>Health</h2>
          <p className="muted">Visibility only - no scores.</p>
          <ul className="list">
            <li>
              <strong>Missing AGENTS</strong>
              <div className="muted">
                {(desk?.health.missingAgents ?? []).length === 0
                  ? 'None in the capped list'
                  : desk!.health.missingAgents.join(', ')}
              </div>
            </li>
            <li>
              <strong>Git status</strong>
              <div className={desk?.health.gitChecked ? 'muted' : 'warn'}>
                {desk?.health.gitStatusLabel ?? 'unknown'}
              </div>
            </li>
            <li>
              <strong>Snapshot</strong>
              <div className={desk?.health.snapshotStale ? 'warn' : 'muted'}>
                {desk?.health.snapshotStale ? 'Stale - refresh recommended' : 'Fresh enough'}
              </div>
            </li>
          </ul>
        </section>
      )}

      {showSettings && (
        <section className="panel">
          <h2>Settings</h2>
          {settingsStatus ? (
            <p className="muted" role="status">
              {settingsStatus}
            </p>
          ) : null}
          <div className="settings-row">
            <div>
              <strong>Profile Sync</strong>
              <p className="muted">
                HQ-published, satellite-pulled. Fingerprint is publisher-side - satellites update
                after <code>profile sync</code> or upgrade pull. Download a pack here, or sync from
                a laptop with <code>.\metra.ps1 profile sync</code>. No Apply-to-this-device over
                Tailscale.
              </p>
              {profileSyncStatus ? (
                <ul className="muted" style={{ margin: '0.4rem 0', paddingLeft: '1.1rem' }}>
                  <li>Fingerprint: {profileSyncStatus.contentHash}</li>
                  <li>Last write: {profileSyncStatus.maxWriteUtc || '(none)'}</li>
                  <li>
                    Files: {profileSyncStatus.fileCount} (pack v
                    {profileSyncStatus.profilePackVersion})
                  </li>
                </ul>
              ) : (
                <p className="muted">Status unavailable (needs operator session).</p>
              )}
              <div style={{ marginTop: '0.6rem' }}>
                <strong>Satellites</strong>
                {profileSyncStatus?.satellites && profileSyncStatus.satellites.length > 0 ? (
                  <ul className="muted" style={{ margin: '0.4rem 0', paddingLeft: '1.1rem' }}>
                    {profileSyncStatus.satellites.map((sat) => (
                      <li key={sat.machineName}>
                        {sat.machineName} - {sat.state}
                        {sat.lastSeenUtc ? ` - seen ${formatRelativeUtc(sat.lastSeenUtc)}` : ''}
                      </li>
                    ))}
                  </ul>
                ) : (
                  <p className="muted" style={{ margin: '0.4rem 0' }}>
                    No satellites have checked in yet. They report after profile status or sync.
                  </p>
                )}
              </div>
              <div className="settings-root-actions">
                <button type="button" disabled={busy} onClick={() => void onDownloadProfilePack()}>
                  Download profile zip
                </button>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => void onIssueProfileSyncToken(false)}
                >
                  Issue sync token
                </button>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => void onIssueProfileSyncToken(true)}
                >
                  Rotate sync token
                </button>
                <button type="button" disabled={busy} onClick={() => void loadProfileSyncStatus()}>
                  Refresh status
                </button>
              </div>
              {profileSyncTokenShown ? (
                <div
                  className="muted"
                  style={{
                    marginTop: '0.5rem',
                    display: 'flex',
                    flexWrap: 'wrap',
                    gap: '0.5rem',
                    alignItems: 'center',
                  }}
                >
                  <span>
                    Token: <code style={{ wordBreak: 'break-all' }}>{profileSyncTokenShown}</code>
                  </span>
                  <button type="button" disabled={busy} onClick={() => void onCopyProfileSyncToken()}>
                    Copy
                  </button>
                </div>
              ) : null}
            </div>
          </div>
          <div className="settings-row">
            <div>
              <strong>How I show up on this PC</strong>
              <p className="muted">
                Choose how this machine fits into your Metra setup. Standalone keeps everything
                on this PC. HQ is home base - other devices come here to work in Metra.
                Satellite connects to your main Metra machine.
              </p>
              <label className="settings-field">
                <span className="muted">Role</span>
                <select
                  disabled={busy}
                  value={machineRoleDraft}
                  onChange={(e) =>
                    setMachineRoleDraft(e.target.value as 'Hq' | 'Satellite' | 'Standalone')
                  }
                >
                  <option value="Standalone">Standalone - everything stays on this PC</option>
                  <option value="Hq">HQ (Main Metra machine)</option>
                  <option value="Satellite">Satellite - connects to your main Metra machine</option>
                </select>
              </label>
              <label className="settings-field">
                <span className="muted">Main Metra address</span>
                <input
                  type="text"
                  disabled={busy}
                  value={opsBaseUrlDraft}
                  onChange={(e) => setOpsBaseUrlDraft(e.target.value)}
                  placeholder="https://metra.example.ts.net"
                  spellCheck={false}
                />
              </label>
              <p className="muted" style={{ marginTop: '0.35rem' }}>
                Binding: {settingsPortfolio?.bindingSummary ?? 'unknown'}
              </p>
              <button type="button" disabled={busy} onClick={() => void onSaveMachineRole()}>
                Save role
              </button>
            </div>
          </div>
          <div className="settings-row">
            <div>
              <strong>Projects folders</strong>
              <p className="muted">
                {settingsPortfolio?.hint ??
                  'Each folder is a parent that contains project folders. Give each a label; mark one as primary.'}
              </p>
              <div className="settings-roots">
                {rootsDraft.map((row) => (
                  <div className="settings-root-card" key={row.key}>
                    <div className="settings-root-top">
                      <label className="settings-field settings-field-compact">
                        <span className="muted">Label</span>
                        <input
                          type="text"
                          disabled={busy}
                          value={row.label}
                          onChange={(e) => updateRootDraft(row.key, { label: e.target.value })}
                          placeholder="Work"
                          spellCheck={false}
                        />
                      </label>
                      <div className="settings-root-flags">
                        <label className="settings-check">
                          <input
                            type="radio"
                            name="settings-primary-root"
                            disabled={busy}
                            checked={row.primary}
                            onChange={() => setPrimaryRootDraft(row.key)}
                          />
                          <span>Primary</span>
                        </label>
                        <label className="settings-check">
                          <input
                            type="checkbox"
                            disabled={busy || row.primary}
                            checked={row.optional}
                            onChange={(e) =>
                              updateRootDraft(row.key, { optional: e.target.checked })
                            }
                          />
                          <span>Optional</span>
                        </label>
                        <button
                          type="button"
                          className="settings-root-remove"
                          disabled={busy || rootsDraft.length <= 1}
                          onClick={() => removeRootDraft(row.key)}
                          title={
                            rootsDraft.length <= 1
                              ? 'At least one folder is required'
                              : 'Remove folder'
                          }
                        >
                          Remove
                        </button>
                      </div>
                    </div>
                    <label className="settings-field">
                      <span className="muted">Path</span>
                      <input
                        type="text"
                        disabled={busy}
                        value={row.path}
                        onChange={(e) => updateRootDraft(row.key, { path: e.target.value })}
                        placeholder="C:\Projects"
                        spellCheck={false}
                      />
                    </label>
                    {row.optional ? (
                      <p className="muted settings-root-note">
                        May be offline (for example cloud sync not set up on this machine).
                      </p>
                    ) : null}
                  </div>
                ))}
              </div>
              <div className="settings-root-actions">
                <button type="button" disabled={busy} onClick={() => addRootDraft()}>
                  Add folder
                </button>
                <button type="button" disabled={busy} onClick={() => void onSavePortfolioFolders()}>
                  Save folders
                </button>
              </div>
            </div>
          </div>
          <div className="settings-row">
            <div>
              <strong>Ask</strong>
              <p className="muted">
                {desk?.ask?.available
                  ? desk.ask.providerLabel
                    ? `AI available. Powered by ${desk.ask.providerLabel}.`
                    : 'AI available.'
                  : desk?.ask?.selected
                    ? 'Ask unavailable - engine selected but not running.'
                    : 'Ask unavailable - no AI engine configured.'}
              </p>
              {askEnginePanel?.recommendation?.summary ? (
                <p className="muted">{askEnginePanel.recommendation.summary}</p>
              ) : null}
              <button
                type="button"
                disabled={busy}
                onClick={() => void onAskAcceptRecommended()}
              >
                Use recommended settings
              </button>
            </div>
          </div>
          <div className="settings-row">
            <div>
              <strong>Advanced Ask engine</strong>
              <p className="muted">
                Override engine (Ollama pins, llama.cpp experimental, Cursor Ask).
                Enterprise appears only when IT configured it.
              </p>
              <button
                type="button"
                disabled={busy}
                onClick={() => {
                  const next = !askEngineOpen
                  setAskEngineOpen(next)
                  if (next) void loadAskEnginePanel()
                }}
              >
                {askEngineOpen ? 'Hide Advanced' : 'Show Advanced'}
              </button>
              {askEngineOpen ? (
                <div style={{ marginTop: '0.75rem' }}>
                  {askEnginePanel ? (
                    <ul className="muted">
                      {askEnginePanel.menu.map((item) => (
                        <li key={item.id} style={{ marginBottom: '0.5rem' }}>
                          <button
                            type="button"
                            disabled={busy || item.disabled}
                            onClick={() => void onAskEngineSet(item.id)}
                          >
                            {item.label}
                          </button>
                          {item.note ? <span> - {item.note}</span> : null}
                        </li>
                      ))}
                    </ul>
                  ) : null}
                  <p className="muted">
                    Cursor Ask API key - status:{' '}
                    {settingsPortfolio?.ask?.apiKeyPresent ? 'key present' : 'not set'}.
                  </p>
                  <label className="settings-field">
                    <span className="muted">API key</span>
                    <input
                      type="password"
                      disabled={busy}
                      value={cursorKeyDraft}
                      onChange={(e) => setCursorKeyDraft(e.target.value)}
                      placeholder="Paste key - never shown again"
                      autoComplete="off"
                      spellCheck={false}
                    />
                  </label>
                  <button type="button" disabled={busy} onClick={() => void onSaveCursorApiKey()}>
                    Save key
                  </button>{' '}
                  <button type="button" disabled={busy} onClick={() => void onClearCursorApiKey()}>
                    Clear key
                  </button>
                </div>
              ) : null}
            </div>
          </div>
          <div className="settings-row">
            <div>
              <strong>Advanced desk</strong>
              <p className="muted">Show Projects, Recent, and Health tabs.</p>
            </div>
            <label className="switch">
              <input
                type="checkbox"
                checked={advanced}
                disabled={busy}
                onChange={(e) => void onToggleAdvanced(e.target.checked)}
              />
              {advanced ? 'On' : 'Off'}
            </label>
          </div>
          <div className="settings-row">
            <div>
              <strong>Ticket Watch</strong>
              <p className="muted">
                Enable gate for Scan tickets only. Portfolio refresh never covers tickets. Off disables
                Scan tickets. No iSupport writes either way.
              </p>
            </div>
            <label className="switch">
              <input
                type="checkbox"
                checked={ticketWatchEnabled}
                disabled={busy}
                onChange={(e) => void onToggleTicketWatch(e.target.checked)}
              />
              {ticketWatchEnabled ? 'On' : 'Off'}
            </label>
          </div>
          <div className="settings-row">
            <div>
              <strong>Attention visible count</strong>
              <p className="muted">
                How many waiting summaries show before Show all. Detail stays one focused card.
              </p>
            </div>
            <label>
              <select
                disabled={busy}
                value={attentionVisibleCount}
                onChange={(e) => void onAttentionVisibleCount(Number(e.target.value))}
                aria-label="Attention visible count"
              >
                {Array.from({ length: 10 }, (_, i) => i + 1).map((n) => (
                  <option key={n} value={n}>
                    {n}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <div className="settings-row">
            <div>
              <strong>Editor</strong>
              <p className="muted">
                What Open in editor launches on the operator machine.
                {desk?.meta?.editor?.label ? ` Currently: ${desk.meta.editor.label}.` : ''}
              </p>
            </div>
            <label>
              <select
                disabled={busy}
                value={desk?.preferences?.editorCommand ?? 'auto'}
                onChange={(e) => void onEditorCommand(e.target.value)}
              >
                <option value="auto">Auto (Cursor, then VS Code)</option>
                <option value="cursor">Cursor</option>
                <option value="code">VS Code</option>
                <option value="system">Windows default</option>
              </select>
            </label>
          </div>
          <div className="settings-row">
            <div>
              <strong>Updates</strong>
              <p className="muted">
                Metra installer and Ollama Ask runtime. Checks stay quiet; nothing installs until you click Update.
              </p>
              {productUpdates ? (
                <ul className="muted" style={{ marginTop: '0.5rem' }}>
                  {productUpdates.lastUpdatedAt ? (
                    <li style={{ marginBottom: '0.5rem' }}>
                      Last applied:{' '}
                      {productUpdates.lastMetraVersion
                        ? `Metra ${productUpdates.lastMetraVersion}`
                        : null}
                      {productUpdates.lastMetraVersion && productUpdates.lastOllamaVersion
                        ? '; '
                        : null}
                      {productUpdates.lastOllamaVersion
                        ? `Ollama ${productUpdates.lastOllamaVersion}`
                        : null}
                    </li>
                  ) : null}
                  <li style={{ marginBottom: '0.5rem' }}>
                    Metra: {productUpdates.metra.message || productUpdates.metra.status}
                    {productUpdates.metra.canUpdate ? (
                      <>
                        {' '}
                        <button
                          type="button"
                          disabled={busy}
                          onClick={() => void onUpdateProduct('metra')}
                        >
                          Update Metra
                        </button>
                      </>
                    ) : null}
                  </li>
                  <li style={{ marginBottom: '0.5rem' }}>
                    Ollama: {productUpdates.ollama.message || productUpdates.ollama.status}
                    {productUpdates.ollama.canUpdate ? (
                      <>
                        {' '}
                        <button
                          type="button"
                          disabled={busy}
                          onClick={() => void onUpdateProduct('ollama')}
                        >
                          Update Ollama
                        </button>
                      </>
                    ) : null}
                  </li>
                </ul>
              ) : (
                <p className="muted">Checking…</p>
              )}
              <button type="button" disabled={busy} onClick={() => void onCheckUpdates()}>
                Check for updates
              </button>
            </div>
          </div>
          <div className="settings-row">
            <div>
              <strong>Home folder</strong>
              <p className="muted">
                <code className="path">{desk?.meta.homeLabel ?? '...'}</code>
              </p>
            </div>
          </div>
          <div className="settings-row">
            <div>
              <strong>Version</strong>
              <p className="muted">{desk?.meta.version ?? 'unknown'}</p>
            </div>
          </div>
          <div className="settings-row">
            <div>
              <strong>Advanced IDE</strong>
              <p className="muted">Cursor Ops canvas remains available for operators.</p>
            </div>
            <a className="btn btn-secondary" href="https://cursor.com" target="_blank" rel="noreferrer">
              Open Cursor
            </a>
          </div>
        </section>
      )}
    </div>
  )
}
