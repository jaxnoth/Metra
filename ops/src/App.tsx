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
  postCaptureDismiss,
  postCaptureFromAsk,
  postCapturePromote,
  postPlace,
  postPlaceConfirm,
  postPlaceCorrect,
  postPlaceUpload,
  fetchPlaceHomes,
  postProposalRequestApply,
  putPreferences,
  refreshSnapshot,
  releaseAttention,
  snoozeAttention,
  fetchAskEngine,
  postAskEngineAccept,
  postAskEngineSet,
  fetchSettings,
  putSettings,
  fetchUpdates,
  postProductUpdate,
} from './api'
import { formatAskTabTitle, getMetraBridge } from './bridge'
import { MetraPresence } from './MetraPresence'
import type {
  AttentionItem,
  AskSessionSummary,
  AskEnginePanel,
  SettingsPortfolio,
  ProductUpdates,
  CaptureItem,
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
  /** Quiet Where chip when Ask route is weak or ambiguous. */
  showWhere?: boolean
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
  if (emptyHint && /not reviewed|quick check|recheck|full refresh/i.test(emptyHint)) {
    return `${quiet} ${emptyHint}`
  }
  if (gitChecked === false) {
    return `${quiet} Some areas were not reviewed - run a full refresh to confirm.`
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
  const bridge = getMetraBridge()
  const key = attention.key || attention.id

  useEffect(() => {
    setFeedback(attention.note || '')
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

  const disabled = busy || localBusy

  return (
    <div className="resolve-actions">
      <p className="resolve-copy">{attention.resolveCopy}</p>
      {attention.doneWhen && (
        <p className="muted resolve-done">You're done when: {attention.doneWhen}</p>
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

  if (handoff.kind === 'greeting') return null

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
  const [rootsDraft, setRootsDraft] = useState<RootDraft[]>(() => portfolioRootsToDrafts(null))
  const [cursorKeyDraft, setCursorKeyDraft] = useState('')
  const [settingsStatus, setSettingsStatus] = useState<string | null>(null)
  const [resolveStatus, setResolveStatus] = useState<string | null>(null)
  const [selectedAttentionKey, setSelectedAttentionKey] = useState<string | null>(null)
  const [selectedHeldKey, setSelectedHeldKey] = useState<string | null>(null)
  const [compactViewport, setCompactViewport] = useState(() =>
    typeof window === 'undefined' ? false : window.matchMedia('(max-width: 42rem)').matches,
  )
  const [attentionOpen, setAttentionOpen] = useState(() =>
    typeof window === 'undefined' ? true : !window.matchMedia('(max-width: 42rem)').matches,
  )
  const [placeText, setPlaceText] = useState('')
  const [placeFiles, setPlaceFiles] = useState<PlaceUploadMeta[]>([])
  const [placeResult, setPlaceResult] = useState<PlaceRecommendation | null>(null)
  const [placeStatus, setPlaceStatus] = useState<string | null>(null)
  const [placePending, setPlacePending] = useState(false)
  const composerRef = useRef<HTMLTextAreaElement | null>(null)
  const chatEndRef = useRef<HTMLDivElement | null>(null)

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

  async function onRefresh(full = false) {
    setBusy(true)
    setError(null)
    try {
      const payload = await refreshSnapshot(full)
      setDesk(payload)
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
    } catch {
      setSettingsPortfolio(null)
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

  useEffect(() => {
    if (!settingsOpen && tab !== 'settings') return
    void loadSettingsPortfolio()
    void loadProductUpdates(false)
    // eslint-disable-next-line react-hooks/exhaustive-deps -- load when Settings opens
  }, [settingsOpen, tab])

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
      setSettingsStatus(result.message || (result.ok ? 'Update finished.' : 'Update failed.'))
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

  async function runAsk(question: string) {
    if (!question.trim()) return
    setPrompt('')
    setBusy(true)
    setAskPending(true)
    setError(null)
    const youId = nextChatId()
    appendChat([{ id: youId, role: 'you', text: question }])
    try {
      const result = await postAsk(question, askSessionId, recallSessionId)
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
          handoff: result.handoff,
          showWhere: Boolean(result.showWhere),
          turnId: result.entry?.id || null,
          sessionId: result.sessionId || result.entry?.sessionId || askSessionId,
        },
      ])
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
      await postCaptureFromAsk(turn.turnId, turn.sessionId || askSessionId)
      setResolveStatus('Saved for later in Metra Capture Inbox.')
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

  async function onPromoteCapture(id: string, home?: string) {
    setBusy(true)
    try {
      await postCapturePromote(id, home)
      setResolveStatus('Promoted capture into the affirmed home.')
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
    await runAsk(prompt.trim())
  }

  function onAskFromAttention(seed: string) {
    setResolveStatus(null)
    void runAsk(seed.trim())
  }

  async function onPastePlace() {
    setPlaceStatus(null)
    try {
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
      for (const f of files) {
        uploaded.push(await postPlaceUpload(f))
      }
      setPlaceFiles((prev) => [...prev, ...uploaded])
      setPlaceStatus(`Staged ${uploaded.length} file(s)`)
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
  const attentionWaiting =
    desk?.attentionCount ??
    desk?.attention?.activeCount ??
    (desk?.nextAttention ? 1 : 0)
  const attentionHeld = desk?.attention?.heldCount ?? desk?.attention?.held?.length ?? 0

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <MetraPresence voiceState={askPending ? 'listening' : 'idle'} />
          <div className="awareness-strip" aria-live="polite">
            <p className="awareness-narration muted">
              {askPending
                ? 'Working...'
                : awarenessNarration(
                    attentionWaiting,
                    desk?.attentionEmptyHint,
                    desk?.gitChecked,
                  )}
            </p>
            <p className="awareness-meta muted">{formatUpdatedShort(desk?.generatedAt)}</p>
          </div>
        </div>
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
                  disabled={busy || !prompt.trim() || placeFiles.length > 0}
                  title={
                    placeFiles.length > 0
                      ? 'Ask image intake is not available yet. Use Put somewhere for attachments.'
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
              {placeFiles.length > 0 && (
                <>
                  <p className="composer-file-note muted">
                    Attachments go with Put somewhere; Ask image intake is not available yet.
                  </p>
                  <ul className="place-files">
                    {placeFiles.map((f) => (
                      <li key={f.id}>
                        <span>{f.fileName}</span>
                        <button
                          type="button"
                          className="btn btn-quiet"
                          onClick={() =>
                            setPlaceFiles((prev) => prev.filter((x) => x.id !== f.id))
                          }
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
                    {turn.text && (
                      <p
                        className={
                          turn.role === 'you'
                            ? 'chat-you'
                            : turn.answered
                              ? 'ask-reply'
                              : 'ask-unavailable'
                        }
                      >
                        {turn.text}
                      </p>
                    )}
                    {turn.role === 'metra' && turn.showWhere && turn.handoff && (
                      <WhereChip
                        handoff={turn.handoff}
                        sourceText={
                          [...chat].reverse().find((t) => t.role === 'you')?.text || turn.text
                        }
                        onCorrected={(msg) => setResolveStatus(msg)}
                      />
                    )}
                    {turn.role === 'metra' && turn.turnId && (
                      <div className="actions wrap">
                        <button
                          type="button"
                          className="btn btn-secondary"
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
          </section>

          <section className="panel panel-attention">
            <div className="panel-heading attention-heading">
              <button
                type="button"
                className="attention-toggle"
                aria-expanded={attentionOpen}
                aria-label={`${attentionWaiting} waiting${attentionHeld > 0 ? `, ${attentionHeld} held` : ''}. ${
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
                    onClick={() => void onRefresh(false)}
                  >
                    {busy ? 'Refreshing...' : 'Quick'}
                  </button>
                  <button
                    type="button"
                    className="btn btn-secondary"
                    disabled={busy}
                    onClick={() => void onRefresh(true)}
                  >
                    {busy ? 'Scanning...' : 'Full refresh'}
                  </button>
                </div>
              )}
            </div>
            {attentionOpen && (() => {
              const active = desk?.attention?.active ?? (desk?.nextAttention ? [desk.nextAttention] : [])
              const held = desk?.attention?.held ?? []
              const heldCount = desk?.attention?.heldCount ?? held.length
              const activeKeys = active.map((a) => a.key || a.id)
              const heldKeys = held.map((h) => h.key || h.id)
              const selectedKey =
                selectedAttentionKey && activeKeys.includes(selectedAttentionKey)
                  ? selectedAttentionKey
                  : activeKeys[0] ?? null
              const selected =
                active.find((a) => (a.key || a.id) === selectedKey) ?? active[0] ?? null
              const selectedHeldKeyResolved =
                selectedHeldKey && heldKeys.includes(selectedHeldKey)
                  ? selectedHeldKey
                  : heldKeys[0] ?? null
              const selectedHeld =
                held.find((h) => (h.key || h.id) === selectedHeldKeyResolved) ?? held[0] ?? null

              if (!selected) {
                return (
                  <div className="attention-empty">
                    <p className="attention">No active attention.</p>
                    <p className="muted">
                      {desk?.attentionEmptyHint ||
                        (desk && !desk.gitChecked
                          ? 'Nothing waiting from this quick check. Some areas were not reviewed. Run a full refresh to confirm.'
                          : 'Nothing waiting. The last full check found no open items.')}
                    </p>
                    {heldCount > 0 && selectedHeld && (
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
                                const key = h.key || h.id
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
                          key={selectedHeld.key || selectedHeld.id}
                          item={selectedHeld}
                          advanced={advanced}
                          busy={busy}
                          onAskSeed={onAskFromAttention}
                          onStatus={setResolveStatus}
                          onDeskUpdate={setDesk}
                        />
                      </div>
                    )}
                  </div>
                )
              }

              return (
                <div className="attention-block">
                  <p className="muted attention-count">
                    {desk?.attention?.activeCount ?? active.length} waiting
                    {(desk?.attention?.notRecheckedCount ?? 0) > 0
                      ? ` · ${desk!.attention!.notRecheckedCount} not rechecked yet`
                      : ''}
                  </p>
                  {active.length > 1 && (
                    <label className="attention-picker">
                      <span className="muted">Showing</span>
                      <select
                        value={selectedKey ?? ''}
                        onChange={(e) => setSelectedAttentionKey(e.target.value || null)}
                        aria-label="Select attention item"
                      >
                        {active.map((item, index) => {
                          const key = item.key || item.id
                          return (
                            <option key={key} value={key}>
                              {index + 1}. {attentionPickerLabel(item)}
                            </option>
                          )
                        })}
                      </select>
                    </label>
                  )}
                  <AttentionCard
                    key={selected.key || selected.id}
                    item={selected}
                    advanced={advanced}
                    busy={busy}
                    onAskSeed={onAskFromAttention}
                    onStatus={setResolveStatus}
                    onDeskUpdate={setDesk}
                    primary
                  />
                  {heldCount > 0 && selectedHeld && (
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
                              const key = h.key || h.id
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
                        key={selectedHeld.key || selectedHeld.id}
                        item={selectedHeld}
                        advanced={advanced}
                        busy={busy}
                        onAskSeed={onAskFromAttention}
                        onStatus={setResolveStatus}
                        onDeskUpdate={setDesk}
                      />
                    </div>
                  )}
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
            Portfolio intake candidates. Save for portfolio parks here; promote writes a durable home
            on affirm. Keep in view stays on Attention.
          </p>
          <ul className="list">
            {(desk?.captures ?? []).length === 0 && (
              <li className="muted">No capture candidates.</li>
            )}
            {(desk?.captures ?? []).map((c: CaptureItem) => (
              <li key={c.id}>
                <strong>{c.summary}</strong>
                <div className="muted">
                  {c.suggestedHome || 'FutureDevelopment'}
                  {c.derivedFrom?.type ? ` · from ${c.derivedFrom.type}` : ''}
                  {c.at ? ` · ${c.at}` : ''}
                </div>
                <div className="actions wrap">
                  <button
                    type="button"
                    className="btn btn-primary"
                    disabled={busy}
                    onClick={() => void onPromoteCapture(c.id, c.suggestedHome)}
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
            ))}
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
