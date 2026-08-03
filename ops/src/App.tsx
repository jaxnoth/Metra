import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { fetchSnapshot, postAsk, postClassify, putPreferences, refreshSnapshot } from './api'
import { MetraPresence } from './MetraPresence'
import type { DeskPayload, DeskMode, Handoff } from './types'

type TabId = 'route' | 'projects' | 'recent' | 'health' | 'settings'

type ChatTurn = {
  id: string
  role: 'you' | 'metra'
  text: string
  handoff?: Handoff | null
  answered?: boolean
  /** Classify keeps the routing card; answered Ask does not. */
  showHandoff?: boolean
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

/** Compact Classify preview - Where + Next only. Full dumps bury the answer. */
function HandoffCard({ handoff }: { handoff: Handoff }) {
  if (handoff.kind === 'greeting') {
    if (!handoff.next) return null
    return (
      <div className="handoff handoff-greeting">
        <p className="muted">{handoff.next}</p>
      </div>
    )
  }

  return (
    <div className="handoff">
      <dl>
        <div>
          <dt>Where</dt>
          <dd>{handoff.where ?? 'No strong match yet'}</dd>
        </div>
        {handoff.ambiguous && handoff.runnerUp && (
          <div>
            <dt>Also close</dt>
            <dd>{handoff.runnerUp}</dd>
          </div>
        )}
        <div>
          <dt>Next</dt>
          <dd>{handoff.next}</dd>
        </div>
      </dl>
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
  /** Ask or Classify in flight - drives presence mark + Working status. */
  const [askPending, setAskPending] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)
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

  async function onAsk(e: FormEvent) {
    e.preventDefault()
    const question = prompt.trim()
    if (!question) return
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
          // Answer is the product; routing dump stays on Classify.
          showHandoff: false,
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

  async function onClassify() {
    const question = prompt.trim()
    if (!question) return
    setPrompt('')
    setBusy(true)
    setAskPending(true)
    setError(null)
    appendChat([{ id: nextChatId(), role: 'you', text: question }])
    try {
      const result = await postClassify(question)
      appendChat([
        {
          id: nextChatId(),
          role: 'metra',
          text: result.what || 'Classification preview',
          handoff: result,
          showHandoff: true,
        },
      ])
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setAskPending(false)
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
                    {turn.role === 'metra' && turn.showHandoff && turn.handoff && (
                      <HandoffCard handoff={turn.handoff} />
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
            {desk?.nextAttention ? (
              <p className="attention">{desk.nextAttention.content}</p>
            ) : (
              <p className="muted">Nothing queued right now.</p>
            )}
          </section>

          <section className="panel">
            <h2>Not sure where something goes?</h2>
            <p>Classify uses Metra routing as a labeled preview.</p>
            <div className="actions">
              <button
                type="button"
                className="btn btn-secondary"
                disabled={busy || !prompt.trim()}
                onClick={() => void onClassify()}
              >
                Classify / Handoff
              </button>
            </div>
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
