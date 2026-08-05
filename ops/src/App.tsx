import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  dismissAttention,
  fetchProposalDiff,
  fetchSnapshot,
  holdAttention,
  openProjectPath,
  postAsk,
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
} from './api'
import { formatAskTabTitle, getMetraBridge } from './bridge'
import { MetraPresence } from './MetraPresence'
import type {
  AttentionItem,
  DeskPayload,
  DeskMode,
  Handoff,
  NextAttention,
  PlaceHome,
  PlaceRecommendation,
  PlaceUploadMeta,
} from './types'

type TabId = 'route' | 'projects' | 'recent' | 'health' | 'settings'

type ChatTurn = {
  id: string
  role: 'you' | 'metra'
  text: string
  handoff?: Handoff | null
  answered?: boolean
  /** Quiet Where chip when Ask route is weak or ambiguous. */
  showWhere?: boolean
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

function formatUpdated(iso: string | undefined): string {
  if (!iso) return 'Not refreshed yet'
  const t = Date.parse(iso)
  if (Number.isNaN(t)) return iso
  const mins = Math.max(0, Math.round((Date.now() - t) / 60000))
  if (mins < 1) return 'Last updated just now'
  if (mins === 1) return 'Last updated 1 minute ago'
  if (mins < 60) return `Last updated ${mins} minutes ago`
  return `Last updated ${new Date(t).toLocaleString()}`
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
      return 'Unpublished work'
    case 'verify':
      return 'Health check'
    case 'drift':
      return 'Setup mismatch'
    case 'decision':
      return 'Decision'
    case 'contract':
      return 'Preference'
    default:
      return kind || ''
  }
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
    item.notRecheckedSince ? 'Not rechecked this time' : null,
  ].filter(Boolean)

  return (
    <div className={primary ? 'attention-card attention-card-primary' : 'attention-card'}>
      <p className="attention">{item.summary || item.content}</p>
      {item.whyNext && <p className="attention-why">{item.whyNext}</p>}
      {advanced && (
        <>
          <p className="muted attention-meta">{metaBits.join(' · ')}</p>
          {item.content && item.content !== item.summary && (
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
  const bridge = getMetraBridge()
  const key = attention.key || attention.id

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
    const prompt = attention.askPrompt || attention.content
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

  const disabled = busy || localBusy

  return (
    <div className="resolve-actions">
      <p className="resolve-copy">{attention.resolveCopy}</p>
      {attention.doneWhen && (
        <p className="muted resolve-done">You're done when: {attention.doneWhen}</p>
      )}
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
            <button
              type="button"
              className="btn btn-primary"
              disabled={disabled || !attention.askPrompt}
              onClick={() => onAskMetra()}
            >
              Ask Metra
            </button>
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
      const res = await postPlaceConfirm(intakeText, place.homeId, true, attachmentIds)
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
      <p className="muted">{place.note || 'Recommendation only - nothing is created until you choose a next step.'}</p>
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
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  /** Ask in flight - drives presence mark + Working status. */
  const [askPending, setAskPending] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [resolveStatus, setResolveStatus] = useState<string | null>(null)
  const [attentionExpanded, setAttentionExpanded] = useState(false)
  const [placeText, setPlaceText] = useState('')
  const [placeFiles, setPlaceFiles] = useState<PlaceUploadMeta[]>([])
  const [placeResult, setPlaceResult] = useState<PlaceRecommendation | null>(null)
  const [placeStatus, setPlaceStatus] = useState<string | null>(null)
  const [placePending, setPlacePending] = useState(false)
  const [placeDrag, setPlaceDrag] = useState(false)
  const placeAreaRef = useRef<HTMLTextAreaElement | null>(null)
  const chatEndRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
  }, [chat, askPending])

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

  async function onVisibleCount(next: number) {
    setBusy(true)
    setError(null)
    try {
      const prefs = await putPreferences(deskMode, next)
      setDesk((prev) =>
        prev
          ? {
              ...prev,
              preferences: prefs,
              attention: prev.attention
                ? { ...prev.attention, visibleCount: prefs.attentionVisibleCount ?? next }
                : prev.attention,
            }
          : prev,
      )
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

  async function runAsk(question: string) {
    if (!question.trim()) return
    setPrompt('')
    setBusy(true)
    setAskPending(true)
    setError(null)
    appendChat([{ id: nextChatId(), role: 'you', text: question }])
    try {
      const result = await postAsk(question, askSessionId)
      if (result.sessionId) setAskSessionId(result.sessionId)
      appendChat([
        {
          id: nextChatId(),
          role: 'metra',
          text: stripAskUiChrome(result.message || ''),
          answered: Boolean(result.answered),
          handoff: result.handoff,
          showWhere: Boolean(result.showWhere),
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
          setPlaceText((prev) => (prev ? `${prev.trim()}\n${text}` : text))
          setPlaceStatus('Pasted - review then Route something')
          placeAreaRef.current?.focus()
          return
        }
      }
      throw new Error('blocked')
    } catch {
      placeAreaRef.current?.focus()
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

  async function onRouteSomething(e?: FormEvent) {
    e?.preventDefault()
    const text = placeText.trim()
    if (!text && placeFiles.length === 0) return
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
    } catch (err) {
      setPlaceStatus(err instanceof Error ? err.message : String(err))
    } finally {
      setPlacePending(false)
      setBusy(false)
    }
  }

  const showSettings = settingsOpen || tab === 'settings'
  const showRoute = !showSettings && (!advanced || tab === 'route')

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <MetraPresence voiceState={askPending ? 'listening' : 'idle'} />
          <p className="meta" aria-live="polite">
            {askPending ? 'Working...' : formatUpdated(desk?.generatedAt)}
          </p>
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
        <>
          <section className="panel">
            <h2>What do you need help with?</h2>
            <form className="ask-row" onSubmit={onAsk}>
              <textarea
                value={prompt}
                onChange={(e) => setPrompt(e.target.value)}
                placeholder="Ask a question or describe what you are trying to do"
                aria-label="Question"
              />
              <div className="actions">
                <button type="submit" className="btn btn-primary" disabled={busy || !prompt.trim()}>
                  {askPending ? 'Working...' : 'Ask'}
                </button>
              </div>
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

          <section className="panel">
            <h2>Next attention</h2>
            {(() => {
              const active = desk?.attention?.active ?? (desk?.nextAttention ? [desk.nextAttention] : [])
              const visibleCount = desk?.attention?.visibleCount ?? desk?.preferences?.attentionVisibleCount ?? 1
              const shown = active.slice(0, Math.max(1, visibleCount))
              const more = active.slice(shown.length)
              const held = desk?.attention?.held ?? []
              const heldCount = desk?.attention?.heldCount ?? held.length

              if (!shown.length) {
                return (
                  <div className="attention-empty">
                    <p className="attention">Nothing waiting.</p>
                    <p className="muted">
                      {desk?.attentionEmptyHint ||
                        (desk && !desk.gitChecked
                          ? 'Nothing waiting from this quick check. Some areas were not reviewed. Run a full refresh to confirm.'
                          : 'Nothing waiting. The last full check found no open items.')}
                    </p>
                    <div className="actions">
                      <button
                        type="button"
                        className="btn btn-secondary"
                        disabled={busy}
                        onClick={() => void onRefresh(true)}
                      >
                        {busy ? 'Scanning...' : 'Full re-scan'}
                      </button>
                    </div>
                    {heldCount > 0 && (
                      <div className="holding-block">
                        <h3>Keeping in view ({heldCount})</h3>
                        {desk?.attention?.holdRoutingHint && (
                          <p className="muted hold-hint">{desk.attention.holdRoutingHint}</p>
                        )}
                        {held.map((h) => (
                          <AttentionCard
                            key={h.key || h.id}
                            item={h}
                            advanced={advanced}
                            busy={busy}
                            onAskSeed={onAskFromAttention}
                            onStatus={setResolveStatus}
                            onDeskUpdate={setDesk}
                          />
                        ))}
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
                  {shown.map((item) => (
                    <AttentionCard
                      key={item.key || item.id}
                      item={item}
                      advanced={advanced}
                      busy={busy}
                      onAskSeed={onAskFromAttention}
                      onStatus={setResolveStatus}
                      onDeskUpdate={setDesk}
                      primary
                    />
                  ))}
                  {more.length > 0 && (
                    <div className="attention-more">
                      <button
                        type="button"
                        className="btn btn-secondary"
                        onClick={() => setAttentionExpanded((v) => !v)}
                      >
                        {attentionExpanded ? 'Hide' : `${more.length} more waiting`}
                      </button>
                      {attentionExpanded &&
                        more.map((item) => (
                          <AttentionCard
                            key={item.key || item.id}
                            item={item}
                            advanced={advanced}
                            busy={busy}
                            onAskSeed={onAskFromAttention}
                            onStatus={setResolveStatus}
                            onDeskUpdate={setDesk}
                          />
                        ))}
                    </div>
                  )}
                  {heldCount > 0 && (
                    <div className="holding-block">
                      <h3>Keeping in view ({heldCount})</h3>
                      {desk?.attention?.holdRoutingHint && (
                        <p className="muted hold-hint">{desk.attention.holdRoutingHint}</p>
                      )}
                      {held.map((h) => (
                        <AttentionCard
                          key={h.key || h.id}
                          item={h}
                          advanced={advanced}
                          busy={busy}
                          onAskSeed={onAskFromAttention}
                          onStatus={setResolveStatus}
                          onDeskUpdate={setDesk}
                        />
                      ))}
                    </div>
                  )}
                  {resolveStatus && <p className="muted resolve-status">{resolveStatus}</p>}
                </div>
              )
            })()}
          </section>

          <section className="panel place-panel">
            <h2>Not sure where something belongs?</h2>
            <p>
              Describe it or drop a file. Metra will recommend the right home and explain why.
            </p>
            <p className="muted">Recommendation only - nothing is created until you choose a next step.</p>
            <form
              className={`place-intake${placeDrag ? ' drag' : ''}`}
              onSubmit={(e) => void onRouteSomething(e)}
              onDragOver={(e) => {
                e.preventDefault()
                setPlaceDrag(true)
              }}
              onDragLeave={() => setPlaceDrag(false)}
              onDrop={(e) => {
                e.preventDefault()
                setPlaceDrag(false)
                if (e.dataTransfer.files?.length) void stageFiles(e.dataTransfer.files)
              }}
            >
              <textarea
                ref={placeAreaRef}
                value={placeText}
                onChange={(e) => setPlaceText(e.target.value)}
                placeholder="Paste a note, path, error, or describe the thing"
                aria-label="Route something intake"
              />
              <div className="actions wrap">
                <button type="button" className="btn btn-secondary" disabled={busy || placePending} onClick={() => void onPastePlace()}>
                  Paste
                </button>
                <label className="btn btn-secondary file-btn">
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
                <button
                  type="submit"
                  className="btn btn-primary"
                  disabled={busy || placePending || (!placeText.trim() && placeFiles.length === 0)}
                >
                  {placePending ? 'Routing...' : 'Route something'}
                </button>
              </div>
              {placeFiles.length > 0 && (
                <ul className="place-files">
                  {placeFiles.map((f) => (
                    <li key={f.id}>
                      <span>{f.fileName}</span>
                      <button
                        type="button"
                        className="btn btn-secondary"
                        onClick={() => setPlaceFiles((prev) => prev.filter((x) => x.id !== f.id))}
                      >
                        Remove
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </form>
            {placeStatus && <p className="muted resolve-status">{placeStatus}</p>}
            {placeResult?.ok && (
              <PlaceResultCard
                place={placeResult}
                intakeText={placeText.trim() || placeFiles.map((f) => f.fileName).join(' ')}
                attachmentIds={placeFiles.map((f) => f.id)}
                advanced={advanced}
                busy={busy || placePending}
                onStatus={setPlaceStatus}
                onDeskUpdate={setDesk}
              />
            )}
          </section>
        </>
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
          <h2>Recent</h2>
          <p className="muted">Snapshot: {desk?.generatedAt ?? 'n/a'}</p>
          <ul className="list">
            {(desk?.recent ?? []).length === 0 && <li className="muted">No Ask captures yet.</li>}
            {(desk?.recent ?? []).map((r) => (
              <li key={r.id}>
                <div>{r.prompt}</div>
                <div className="muted">{r.at}</div>
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
              <strong>Attention visible count</strong>
              <p className="muted">How many active attention items to show before expanding (1-10).</p>
            </div>
            <label>
              <input
                type="number"
                min={1}
                max={10}
                disabled={busy}
                value={desk?.preferences?.attentionVisibleCount ?? desk?.attention?.visibleCount ?? 1}
                onChange={(e) => {
                  const n = Number(e.target.value)
                  if (!Number.isFinite(n)) return
                  void onVisibleCount(Math.min(10, Math.max(1, Math.round(n))))
                }}
              />
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
              <strong>Refresh</strong>
              <p className="muted">Rebuild the shared portfolio snapshot.</p>
            </div>
            <div className="actions">
              <button type="button" className="btn btn-secondary" disabled={busy} onClick={() => void onRefresh(false)}>
                Quick
              </button>
              <button type="button" className="btn btn-secondary" disabled={busy} onClick={() => void onRefresh(true)}>
                Full
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
