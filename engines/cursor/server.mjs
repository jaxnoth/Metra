/**
 * Metra Ask engine - Cursor implementer.
 * Loopback contract only: GET /health, POST /v1/complete.
 * Answer-only: do not edit, create, or delete files; do not run mutating commands.
 */
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import { Agent, Cursor, CursorAgentError } from '@cursor/sdk'
import {
  adaptSelectionForAvailableModels,
  isRetryableModelFailure,
  pickFallbackExcluding,
  resolveModelSelection,
  selectionModelKey,
  toSdkModelOpt,
} from './model-selection.mjs'
import {
  acquireSessionLease,
  classifyRunError,
  createSessionEntry,
  disposeAllSessions,
  getHealthPayload,
  getSession,
  putSession,
  recordRunError,
  recordRunFinished,
  releaseSessionLease,
  retireSession,
} from './session-cache.mjs'

const PORT = Number(process.env.METRA_ASK_PORT || 7381)
const ENGINE = 'cursor'
const RUNS_LOG_MAX_BYTES = 512 * 1024

function getAskLogDir() {
  if (process.env.METRA_ASK_LOG_DIR && String(process.env.METRA_ASK_LOG_DIR).trim()) {
    return String(process.env.METRA_ASK_LOG_DIR).trim()
  }
  const localApp = process.env.LOCALAPPDATA || process.env.HOME || process.cwd()
  return path.join(localApp, 'Metra', 'logs')
}

function getRunsLogPath() {
  return path.join(getAskLogDir(), `ask-engine-${PORT}.runs.log`)
}

/** Append-only run/listen diagnostics. Survives Start-Process truncating stdout/stderr redirects. */
function appendRunsLog(line) {
  try {
    const file = getRunsLogPath()
    fs.mkdirSync(path.dirname(file), { recursive: true })
    let existing = ''
    try {
      if (fs.existsSync(file) && fs.statSync(file).size > RUNS_LOG_MAX_BYTES) {
        existing = fs.readFileSync(file, 'utf8')
        const keepFrom = Math.max(0, existing.length - Math.floor(RUNS_LOG_MAX_BYTES / 2))
        existing = existing.slice(keepFrom)
        fs.writeFileSync(file, existing, 'utf8')
      }
    } catch {
      /* ignore rotate read failures */
    }
    fs.appendFileSync(file, `${new Date().toISOString()} ${line}\n`, 'utf8')
  } catch {
    /* never fail the request on log I/O */
  }
}

/**
 * Cursor Ask defaults to composer-2.5 when env unset. auto-smart is adapted at runtime
 * when the API key cannot use Cursor Router (see model-selection.mjs).
 */
const MODEL_SELECTION = resolveModelSelection()
const MODEL = MODEL_SELECTION.label

/** @type {string[] | null} */
let cachedAvailableModelIds = null
/** @type {number} */
let cachedAvailableModelIdsAt = 0
const MODEL_CACHE_MS = 5 * 60 * 1000
let activeModelLabel = MODEL

async function getAvailableModelIds(apiKey) {
  const now = Date.now()
  if (cachedAvailableModelIds && now - cachedAvailableModelIdsAt < MODEL_CACHE_MS) {
    return cachedAvailableModelIds
  }
  try {
    const result = await Cursor.models.list({ apiKey })
    const raw = result?.models ?? result ?? []
    const ids = (Array.isArray(raw) ? raw : [])
      .map((m) => (typeof m === 'string' ? m : m?.id))
      .filter(Boolean)
    if (ids.length > 0) {
      cachedAvailableModelIds = ids.map((id) => String(id).trim())
      cachedAvailableModelIdsAt = now
      return cachedAvailableModelIds
    }
  } catch (err) {
    appendRunsLog(`models.list failed: ${err?.message || err}`)
  }
  return null
}

async function resolveSdkSelection(apiKey, selection) {
  const available = await getAvailableModelIds(apiKey)
  if (!available) return selection
  const adapted = adaptSelectionForAvailableModels(selection, available)
  if (adapted.adapted) {
    appendRunsLog(
      `router fallback ${adapted.fallbackFrom} -> ${adapted.fallbackTo}`,
    )
    activeModelLabel = adapted.selection.label
  }
  return adapted.selection
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    const chunks = []
    req.on('data', (c) => chunks.push(c))
    req.on('end', () => {
      try {
        const raw = Buffer.concat(chunks).toString('utf8')
        resolve(raw ? JSON.parse(raw) : {})
      } catch (err) {
        reject(err)
      }
    })
    req.on('error', reject)
  })
}

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj)
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': '*',
  })
  res.end(body)
}

function formatRecentTurns(recentTurns) {
  if (!Array.isArray(recentTurns) || recentTurns.length === 0) return null
  const lines = recentTurns.map((t) => {
    const idx = t?.turnIndex != null ? `Turn ${t.turnIndex}` : 'Turn'
    const prompt = (t?.prompt || '').trim()
    const message = (t?.message || '').trim()
    if (!prompt && !message) return null
    return message ? `- ${idx}: Q: ${prompt} | A: ${message}` : `- ${idx}: Q: ${prompt}`
  }).filter(Boolean)
  return lines.length ? lines.join('\n') : null
}

function formatEvidenceItems(items, maxItems = 6, maxCharsPerItem = 400) {
  if (!Array.isArray(items) || items.length === 0) return null
  const lines = []
  let total = 0
  const maxTotal = 2400
  for (const raw of items.slice(0, maxItems)) {
    if (!raw || typeof raw !== 'object') continue
    const kind = String(raw.kind || 'item').trim()
    const label = String(raw.label || '').trim()
    let excerpt = String(raw.excerpt || '').trim().replace(/\s+/g, ' ')
    if (excerpt.length > maxCharsPerItem) {
      excerpt = `${excerpt.slice(0, Math.max(0, maxCharsPerItem - 1))}...`
    }
    if (!label && !excerpt) continue
    if (total + excerpt.length > maxTotal && lines.length > 0) break
    lines.push(`- [${kind}] ${label}${excerpt ? `: ${excerpt}` : ''}`)
    total += excerpt.length
  }
  return lines.length ? lines.join('\n') : null
}

function buildPrompt(userPrompt, context, options = {}) {
  const where = context?.where || context?.route?.where || 'Metra'
  const what = context?.what || context?.route?.what || ''
  const whySrc = context?.why ?? context?.route?.why
  const why = Array.isArray(whySrc) ? whySrc.filter(Boolean).join('; ') : ''
  const forWhomSrc = context?.forWhom ?? context?.route?.forWhom
  const forWhom = Array.isArray(forWhomSrc) ? forWhomSrc.filter(Boolean).join('; ') : ''
  const evidence = context?.evidence && typeof context.evidence === 'object' ? context.evidence : null
  const quality = String(evidence?.quality || '').toLowerCase()
  const limits = evidence?.limits && typeof evidence.limits === 'object' ? evidence.limits : {}
  const maxItems = Number(limits.maxItems) > 0 ? Number(limits.maxItems) : 6
  const maxCharsPerItem = Number(limits.maxCharsPerItem) > 0 ? Number(limits.maxCharsPerItem) : 400
  const evidenceBlock = formatEvidenceItems(evidence?.items, maxItems, maxCharsPerItem)
  const capability = context?.capability && typeof context.capability === 'object' ? context.capability : null
  const capStatus = capability?.status ? String(capability.status) : ''
  const includeJournal =
    Boolean(options.includeJournalContinuity) ||
    Boolean(context?.forceContinuity) ||
    Boolean(context?.recall) ||
    Boolean(context?.continuity?.hasJournalContext)

  const sessionSummary =
    includeJournal &&
    (context?.sessionSummary || context?.continuity?.sessionSummary)
      ? String(context.sessionSummary || context.continuity.sessionSummary).trim()
      : ''
  const recentTurns = context?.recentTurns || context?.continuity?.recentTurns
  const recentBlock = includeJournal ? formatRecentTurns(recentTurns) : null
  const recallBlock = context?.recall || context?.continuity?.recallSummary
    ? String(context.recall || context.continuity.recallSummary).trim()
    : ''
  const recallSid = context?.recallSessionId || context?.continuity?.recallSessionId
    ? String(context.recallSessionId || context.continuity.recallSessionId).trim()
    : ''

  const thinOrNone = quality === 'thin' || quality === 'none'
  const hasImageEvidence =
    Array.isArray(evidence?.items) &&
    evidence.items.some((it) => String(it?.kind || '').toLowerCase() === 'image')
  const evidenceRules = thinOrNone
    ? [
        'EVIDENCE QUALITY (mandatory):',
        `- evidence.quality=${quality || 'thin'} - treat the answer as provisional, not grounded.`,
        '- Do not invent live system status (Orion, iSupport, hosts, queues) without bound tool results in evidence.',
        '- Prefer one concrete next check over a confident claim.',
        '- Session Journal continuity is not factual evidence unless an evidence item is marked factual.',
      ]
    : [
        'EVIDENCE QUALITY (mandatory):',
        `- evidence.quality=${quality || 'adequate'} - ground claims in the evidence items below.`,
        '- Do not invent live system status beyond what evidence items support.',
        '- Session Journal continuity is not factual evidence unless an evidence item is marked factual.',
      ]

  const visionRules = hasImageEvidence || options.hasImages
    ? [
        '',
        'VISION-READ (mandatory when images are attached):',
        '- Describe visible content as observations, not live system truth.',
        '- Prefer attributable phrasing: "The screenshot appears to show...", "Visible text in the image reads...", "The image appears to indicate...".',
        '- Distinguish quoted visible text from your interpretation.',
        '- Quote visible text when relevant; say when text is partially legible or uncertain.',
        '- Do not claim current live status (Orion is down, ticket is resolved, host is failing) from screenshots alone.',
        '- Recommend one concrete next check that would ground live status outside the image.',
      ]
    : []

  return [
    'You are Metra answering from the HTML Ops desk.',
    'Speak as Metra. Do not say you are Cursor or that you are running inside Cursor.',
    'Do not open with a Metra / Model disclosure line (no "Metra · Model: ...").',
    'The Ops desk UI already labels Metra - start directly with the useful answer.',
    'ANSWER-ONLY MODE (mandatory):',
    '- Do not edit, create, delete, move, or rename any files.',
    '- Do not run shell commands that change state (install, write, git commit, deploy).',
    '- You may read files and explain.',
    '- If the user needs code changes, tell them to open Cursor to build - one short line, not a tutorial.',
    '',
    'DESK BREVITY (mandatory):',
    '- Lead with the verdict in one or two sentences.',
    '- Then at most a short bullet list of concrete next steps or file paths.',
    '- Prefer a few high-signal findings over exhaustive catalogs, tables, and section essays.',
    '- Do not paste routing furniture (Where / What / Why / Next / Also close / For whom).',
    '- Do not end with offers like "Want me to..." or "I can also walk through...".',
    '- Skip Brightspace / unrelated warnings unless the user asked about them.',
    '',
    'DESK HONESTY (mandatory):',
    '- Do not invent operator biography or personal observations.',
    '- Session Journal is continuity evidence, not personal memory.',
    '- Do not promise to write files, save notes, or create Capture entries.',
    '- For park / save / remember asks, point at Save for portfolio or .\\metra.ps1 capture note.',
    '',
    ...evidenceRules,
    ...visionRules,
    capStatus ? `- capability.status=${capStatus}` : null,
    '',
    'Route context from Metra (use for cwd and focus - do not reprint as labels):',
    `- Where: ${where}`,
    what ? `- What: ${what}` : null,
    why ? `- Why: ${why}` : null,
    forWhom ? `- For whom: ${forWhom}` : null,
    evidenceBlock
      ? ['', 'Bound evidence items (respect limits; do not invent beyond these):', evidenceBlock].join(
          '\n',
        )
      : null,
    sessionSummary
      ? [
          '',
          'Earlier turns in this Ask session (Session Journal extractive summary - labeled evidence, not Capture):',
          sessionSummary,
        ].join('\n')
      : null,
    recentBlock
      ? [
          '',
          'Recent Ask turns from Session Journal (use for continued Ops conversation; do not invent beyond these):',
          recentBlock,
        ].join('\n')
      : null,
    recallBlock
      ? [
          '',
          `Operator-recalled prior Ask session${recallSid ? ` (${recallSid})` : ''} (explicit episodic recall - use only as supporting evidence):`,
          recallBlock,
        ].join('\n')
      : null,
    '',
    'User ask:',
    userPrompt,
  ]
    .filter((line) => line !== null)
    .join('\n')
}

/** Strip Cursor-chat persona banners and echoed routing cards from desk answers. */
function stripDeskChrome(text) {
  if (!text || typeof text !== 'string') return text
  const lines = text.split(/\r?\n/)
  const kept = []
  let droppingRouteCard = false
  for (const line of lines) {
    // **Metra** · Model: Composer · language model · Cursor
    if (/^\s*\*{0,2}Metra\*{0,2}\s*[·•|]\s*Model\s*:/i.test(line)) continue
    if (/^\s*\*{0,2}Metra\*{0,2}\s*[·•]\s*.*\bmodel\b/i.test(line) && /cursor|composer|language\s+model/i.test(line)) {
      continue
    }
    // Model sometimes echoes the Classify handoff block into the answer body.
    if (/^\s*(Where|What|Why|Next|Also close|For whom)\s*:?\s*$/i.test(line)) {
      droppingRouteCard = true
      continue
    }
    if (droppingRouteCard) {
      if (/^\s*$/.test(line)) {
        droppingRouteCard = false
        continue
      }
      if (/^\s*(Where|What|Why|Next|Also close|For whom)\s*:?\s*$/i.test(line)) continue
      if (/labeled preview/i.test(line)) continue
      // Stay in drop mode while lines look like handoff values / bullets.
      if (/^\s*(-|\*|Open |Stay |Fun Committee|Regenerate |Personal )/i.test(line)) continue
      if (line.length < 120 && !/^#{1,3}\s/.test(line)) continue
      droppingRouteCard = false
    }
    if (/labeled preview\s*-/i.test(line)) continue
    kept.push(line)
  }
  return kept.join('\n').replace(/^\s+/, '').replace(/\s+$/, '')
}

/** Mirror of Metra AskSecrets.ps1 - defense in depth; PowerShell remains authoritative. */
const SECRET_PATTERNS = [
  {
    kind: 'pem',
    refuse: true,
    reason: 'pem_private_key',
    regex: /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/gi,
  },
  {
    kind: 'github',
    refuse: false,
    reason: null,
    regex: /\b(?:ghp_|gho_|ghu_|ghs_|ghr_|github_pat_)[A-Za-z0-9_]{20,}\b/gi,
  },
  {
    kind: 'aws',
    refuse: false,
    reason: null,
    regex: /\bAKIA[0-9A-Z]{16}\b/g,
  },
  {
    kind: 'slack',
    refuse: false,
    reason: null,
    regex: /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/gi,
  },
  {
    kind: 'api_key',
    refuse: false,
    reason: null,
    regex: /\bsk-[A-Za-z0-9]{20,}\b/g,
  },
  {
    kind: 'bearer',
    refuse: false,
    reason: null,
    regex: /\bBearer\s+[A-Za-z0-9\-._~+/]+=*/gi,
  },
  {
    kind: 'connection',
    refuse: false,
    reason: null,
    regex: /(?:Password|Pwd)\s*=\s*([^;"'\s][^;"']*)/gi,
  },
]

function scrubSecretsText(text) {
  const original = text == null ? '' : String(text)
  let work = original
  const counts = new Map()
  let refuse = false
  let reason = null
  let redactedChars = 0

  for (const pat of SECRET_PATTERNS) {
    const re = new RegExp(pat.regex.source, pat.regex.flags)
    const matches = [...work.matchAll(re)]
    if (matches.length === 0) continue
    const placeholder = `[REDACTED:${pat.kind}]`
    // Replace from the end so indices stay valid.
    for (let i = matches.length - 1; i >= 0; i--) {
      const m = matches[i]
      const idx = m.index ?? 0
      redactedChars += m[0].length
      work = work.slice(0, idx) + placeholder + work.slice(idx + m[0].length)
    }
    counts.set(pat.kind, (counts.get(pat.kind) || 0) + matches.length)
    if (pat.refuse) {
      refuse = true
      if (!reason) reason = pat.reason
    }
  }

  const kinds = [...counts.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([kind, count]) => ({ kind, count }))
  const ratio = original.length <= 0 ? 0 : Math.min(1, redactedChars / original.length)
  const matched = kinds.length > 0
  let notice = null
  if (refuse) {
    notice =
      'Private-key material was blocked and not sent to the Ask engine. Rephrase without the key block.'
  } else if (matched) {
    notice = `Secrets scrubbed: ${kinds.map((k) => `${k.kind}(${k.count})`).join(', ')}.`
    if (ratio > 0.75) notice += ' Large amount of sensitive content removed.'
  } else if (ratio > 0.75) {
    notice = 'Large amount of sensitive content removed.'
  }

  return { text: work, matched, refuse, reason, kinds, redactedCharsRatio: ratio, notice }
}

function scrubSecretsValue(node) {
  if (node == null) return { value: node, matched: false, refuse: false, reason: null, kinds: [] }
  if (typeof node === 'string') {
    const r = scrubSecretsText(node)
    return {
      value: r.text,
      matched: r.matched,
      refuse: r.refuse,
      reason: r.reason,
      kinds: r.kinds,
      notice: r.notice,
    }
  }
  if (typeof node !== 'object') {
    return { value: node, matched: false, refuse: false, reason: null, kinds: [] }
  }
  if (Array.isArray(node)) {
    let matched = false
    let refuse = false
    let reason = null
    const kindsMap = new Map()
    const value = node.map((item) => {
      const r = scrubSecretsValue(item)
      if (r.matched) matched = true
      if (r.refuse) {
        refuse = true
        if (!reason) reason = r.reason
      }
      for (const k of r.kinds || []) {
        kindsMap.set(k.kind, (kindsMap.get(k.kind) || 0) + k.count)
      }
      return r.value
    })
    return {
      value,
      matched,
      refuse,
      reason,
      kinds: [...kindsMap.entries()].map(([kind, count]) => ({ kind, count })),
    }
  }
  let matched = false
  let refuse = false
  let reason = null
  const kindsMap = new Map()
  const value = {}
  for (const [key, val] of Object.entries(node)) {
    const r = scrubSecretsValue(val)
    value[key] = r.value
    if (r.matched) matched = true
    if (r.refuse) {
      refuse = true
      if (!reason) reason = r.reason
    }
    for (const k of r.kinds || []) {
      kindsMap.set(k.kind, (kindsMap.get(k.kind) || 0) + k.count)
    }
  }
  return {
    value,
    matched,
    refuse,
    reason,
    kinds: [...kindsMap.entries()].map(([kind, count]) => ({ kind, count })),
  }
}

function mimeFromFileName(fileName) {
  const ext = path.extname(String(fileName || '')).toLowerCase()
  switch (ext) {
    case '.png':
      return 'image/png'
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg'
    case '.gif':
      return 'image/gif'
    case '.webp':
      return 'image/webp'
    default:
      return 'application/octet-stream'
  }
}

/**
 * Resolve Host quarantine image refs (id + path) into SDK images.
 * Never accept journal-style payloads with base64 from callers as the primary path.
 */
function loadImagesFromRefs(rawImages) {
  if (!Array.isArray(rawImages) || rawImages.length === 0) return []
  const out = []
  for (const raw of rawImages.slice(0, 3)) {
    if (!raw || typeof raw !== 'object') continue
    const filePath = String(raw.path || '').trim()
    const fileName = String(raw.fileName || path.basename(filePath) || 'image')
    if (!filePath) continue
    if (!fs.existsSync(filePath)) {
      const err = new Error(`Ask image quarantine path missing: ${fileName}`)
      err.code = 'image_missing'
      throw err
    }
    const buf = fs.readFileSync(filePath)
    if (!buf || buf.length === 0) continue
    out.push({
      data: buf.toString('base64'),
      mimeType: mimeFromFileName(fileName),
    })
  }
  return out
}

function extractRunErrorDetail(result, run) {
  let detail = ''
  if (typeof result?.result === 'string' && result.result.trim()) {
    detail = result.result.trim()
  } else if (result?.result && typeof result.result === 'object') {
    detail = String(result.result.message || result.result.error || '').trim()
  }
  // Current @cursor/sdk puts failure text on result.error.message (not result.result).
  if (!detail && result?.error) {
    if (typeof result.error === 'string' && result.error.trim()) {
      detail = result.error.trim()
    } else if (typeof result.error === 'object') {
      detail = String(result.error.message || result.error.error || '').trim()
    }
  }
  if (!detail && typeof run?.result === 'string' && run.result.trim()) {
    detail = run.result.trim()
  }
  if (!detail && result?.requestId) {
    detail = `requestId=${result.requestId}`
  }
  if (detail.length > 400) detail = `${detail.slice(0, 399)}...`
  return detail
}

async function extractRunErrorDetailAsync(result, run) {
  let detail = extractRunErrorDetail(result, run)
  if (run && run._error) {
    const err = run._error
    if ((!detail || detail.startsWith('requestId=')) && typeof err === 'string' && err.trim()) {
      detail = err.trim()
    } else if ((!detail || detail.startsWith('requestId=')) && err && typeof err.message === 'string' && err.message.trim()) {
      detail = err.message.trim()
    } else if ((!detail || detail.startsWith('requestId=')) && err && typeof err === 'object') {
      const nested = String(err.message || err.error || '').trim()
      if (nested) detail = nested
    }
  }
  if (detail && !detail.startsWith('requestId=')) return detail
  if (run && typeof run.conversation === 'function') {
    try {
      const turns = await run.conversation()
      for (let i = turns.length - 1; i >= 0; i--) {
        const turn = turns[i]
        const text = String(turn?.text || turn?.message || turn?.content || '').trim()
        if (text) {
          detail = text.length > 400 ? `${text.slice(0, 399)}...` : text
          break
        }
      }
    } catch {
      /* ignore conversation probe failures */
    }
  }
  if (!detail || detail.startsWith('requestId=')) {
    const id = result?.id || 'n/a'
    const requestId = result?.requestId || 'n/a'
    detail = `run ${id} failed with no SDK detail (requestId=${requestId})`
  }
  return detail
}

async function complete({ prompt, cwd, context, sessionId, images, model }) {
  const apiKey = process.env.CURSOR_API_KEY
  if (!apiKey) {
    const err = new Error('CURSOR_API_KEY missing')
    err.code = 'key_missing'
    throw err
  }

  let selection =
    model != null && String(model).trim()
      ? resolveModelSelection(String(model).trim())
      : MODEL_SELECTION
  selection = await resolveSdkSelection(apiKey, selection)
  let modelLabel = selection.label

  const promptScrub = scrubSecretsText(prompt)
  const ctxScrub = scrubSecretsValue(context || {})
  // Pre-SDK validation / secrets refuse must not increment consecutiveRunErrors.
  if (promptScrub.refuse || ctxScrub.refuse) {
    return {
      message:
        promptScrub.notice ||
        ctxScrub.notice ||
        'Private-key material was blocked and not sent to the Ask engine. Rephrase without the key block.',
      engine: ENGINE,
      model: modelLabel,
      sessionId: sessionId || null,
      status: 'refused',
      secretsRefuse: true,
      secretsReason: promptScrub.reason || ctxScrub.reason || 'pem_private_key',
    }
  }

  const workDir = cwd && typeof cwd === 'string' && cwd.length > 0 ? cwd : process.cwd()
  const sdkImages = loadImagesFromRefs(images)

  async function createAgentForSelection(currentSelection) {
    const opt = toSdkModelOpt(currentSelection)
    try {
      const agent = await Agent.create({
        apiKey,
        model: opt,
        local: { cwd: workDir, settingSources: [] },
      })
      return { agent, selection: currentSelection }
    } catch (err) {
      const msg = String(err?.message || '')
      const shouldFallback =
        (currentSelection.id === 'auto-smart' &&
          err instanceof CursorAgentError &&
          /cannot use this model/i.test(msg)) ||
        isRetryableModelFailure(msg)
      if (shouldFallback) {
        const available = (await getAvailableModelIds(apiKey)) || [
          'default',
          'composer-2.5',
        ]
        const fallbackId = pickFallbackExcluding(
          available,
          currentSelection.id,
          currentSelection.params?.find((p) => p.id === 'optimize_for')?.value ||
            'cost',
        )
        if (
          fallbackId &&
          fallbackId.toLowerCase() !== String(currentSelection.id).toLowerCase()
        ) {
          const fallback = {
            id: fallbackId,
            label: `${fallbackId} (${currentSelection.id} unavailable)`,
          }
          appendRunsLog(
            `createAgent fallback ${currentSelection.id} -> ${fallbackId}`,
          )
          activeModelLabel = fallback.label
          const agent = await Agent.create({
            apiKey,
            model: { id: fallback.id },
            local: { cwd: workDir, settingSources: [] },
          })
          return { agent, selection: fallback }
        }
      }
      throw err
    }
  }

  let modelKey = selectionModelKey(selection)

  let entry = null
  let agent = null
  let newSession = false
  const requestedId =
    sessionId && String(sessionId).trim() ? String(sessionId).trim() : null
  let id = requestedId

  try {
    if (requestedId) {
      const existing = getSession(requestedId)
      if (existing && existing.modelKey === modelKey && !existing.retiring) {
        entry = existing
        agent = entry.agent
        // Lease before any further await so concurrent putSession cannot dispose us.
        acquireSessionLease(entry)
      } else {
        if (existing) {
          await retireSession(requestedId, existing)
        }
        const created = await createAgentForSelection(selection)
        selection = created.selection
        modelLabel = selection.label
        modelKey = selectionModelKey(selection)
        agent = created.agent
        entry = createSessionEntry(agent, modelKey)
        acquireSessionLease(entry)
        newSession = true
        await putSession(requestedId, entry)
      }
    } else {
      const created = await createAgentForSelection(selection)
      selection = created.selection
      modelLabel = selection.label
      modelKey = selectionModelKey(selection)
      agent = created.agent
      entry = createSessionEntry(agent, modelKey)
      acquireSessionLease(entry)
      newSession = true
      id = agent.agentId || `local-${Date.now()}`
      await putSession(id, entry)
    }

    id = requestedId || agent.agentId || id || `local-${Date.now()}`

    const wrapped = buildPrompt(promptScrub.text, ctxScrub.value || {}, {
      includeJournalContinuity: newSession,
      hasImages: sdkImages.length > 0,
    })

    async function sendAndWait(activeAgent) {
      const activeRun =
        sdkImages.length > 0
          ? await activeAgent.send({ text: wrapped, images: sdkImages })
          : await activeAgent.send(wrapped)
      const activeResult = await activeRun.wait()
      return { run: activeRun, result: activeResult }
    }

    let { run, result } = await sendAndWait(agent)
    if (result.status === 'error') {
      const detail = await extractRunErrorDetailAsync(result, run)
      const scrubbed = detail ? scrubSecretsText(detail) : { text: '' }
      const classified = classifyRunError(scrubbed.text || '')
      const failedModelId = selection.id

      // Personal / restricted keys often auth-fail on pinned inspect models (e.g. gemini).
      // Retry once on a concrete catalog fallback; do not retry usage/billing limits.
      if (isRetryableModelFailure(scrubbed.text || classified.errorDetail || '')) {
        const available = (await getAvailableModelIds(apiKey)) || [
          'default',
          'composer-2.5',
        ]
        const fallbackId = pickFallbackExcluding(
          available,
          failedModelId,
          selection.params?.find((p) => p.id === 'optimize_for')?.value || 'cost',
        )
        if (
          fallbackId &&
          fallbackId.toLowerCase() !== String(failedModelId).toLowerCase()
        ) {
          appendRunsLog(
            `run fallback ${failedModelId} -> ${fallbackId} (${classified.errorCode})`,
          )
          await retireSession(id, entry)
          await releaseSessionLease(entry)
          entry = null
          const fallbackSelection = {
            id: fallbackId,
            label: `${fallbackId} (${failedModelId} unavailable)`,
          }
          const created = await createAgentForSelection(fallbackSelection)
          selection = created.selection
          modelLabel = selection.label
          activeModelLabel = modelLabel
          modelKey = selectionModelKey(selection)
          agent = created.agent
          entry = createSessionEntry(agent, modelKey)
          acquireSessionLease(entry)
          newSession = true
          id = requestedId || agent.agentId || `local-${Date.now()}`
          await putSession(id, entry)
          ;({ run, result } = await sendAndWait(agent))
        }
      }

      if (result.status === 'error') {
        recordRunError()
        const finalDetail = await extractRunErrorDetailAsync(result, run)
        const scrubbedFinal = finalDetail ? scrubSecretsText(finalDetail) : { text: '' }
        const classifiedFinal = classifyRunError(scrubbedFinal.text || '')
        const message = scrubbedFinal.text
          ? `The Ask engine run failed: ${scrubbedFinal.text}`
          : 'The Ask engine run failed. Try again, or use Classify for routing only.'
        const errLine = `[ask-cursor] run error id=${result.id || 'n/a'} requestId=${result.requestId || 'n/a'} durationMs=${result.durationMs ?? 'n/a'} detail=${scrubbedFinal.text || '(none)'} retryClass=${classifiedFinal.retryClass}`
        console.error(errLine)
        appendRunsLog(errLine)
        await retireSession(id, entry)
        return {
          message,
          engine: ENGINE,
          model: modelLabel,
          sessionId: id,
          status: 'error',
          runId: result.id || null,
          requestId: result.requestId || null,
          errorCode: classifiedFinal.errorCode,
          errorDetail: classifiedFinal.errorDetail,
          retryClass: classifiedFinal.retryClass,
        }
      }
    }

    let text = ''
    if (typeof result.result === 'string') {
      text = result.result
    } else if (result.result && typeof result.result === 'object') {
      text = result.result.text || result.result.message || JSON.stringify(result.result)
    }
    if (!text && typeof run.text === 'function') {
      try {
        text = await run.text()
      } catch {
        /* ignore */
      }
    }
    const hadModelText = Boolean(text && String(text).trim())
    const outScrub = scrubSecretsText(stripDeskChrome(hadModelText ? text : ''))
    // Output secrets refuse is post-SDK; do not treat as run-health wedge.
    if (outScrub.refuse) {
      return {
        message:
          outScrub.notice ||
          'Private-key material was blocked and not sent to the Ask engine. Rephrase without the key block.',
        engine: ENGINE,
        model: modelLabel,
        sessionId: id,
        status: 'refused',
        secretsRefuse: true,
        secretsReason: outScrub.reason || 'pem_private_key',
      }
    }

    const rawStatus = result.status && String(result.status).trim()
    let message = outScrub.text
    if (!hadModelText) {
      message =
        message ||
        'Metra answered, but the engine returned no text.'
    }
    const status = rawStatus || (hadModelText ? 'finished' : 'unknown')
    if (status === 'finished' || hadModelText) {
      recordRunFinished()
    }
    let transportResolved = null
    if (result && typeof result.model === 'string' && result.model.trim()) {
      transportResolved = result.model.trim()
    } else if (result && result.model && typeof result.model === 'object' && result.model.id) {
      transportResolved = String(result.model.id).trim()
    }
    if (transportResolved === '[object Object]') {
      transportResolved = null
    }
    const payload = {
      message,
      engine: ENGINE,
      model: modelLabel,
      sessionId: id,
      status,
    }
    if (transportResolved) {
      payload.resolvedModel = transportResolved
    }
    return payload
  } catch (err) {
    // Any SDK/transport failure after a session is in play: count toward health and retire.
    // CursorAgentError returns a structured body; other throws become HTTP 500 above.
    recordRunError()
    if (entry && id) {
      await retireSession(id, entry)
    }
    if (err instanceof CursorAgentError) {
      const scrubbed = scrubSecretsText(err.message || '')
      const classified = classifyRunError(scrubbed.text || '')
      return {
        message: `Ask engine could not start: ${scrubbed.text || err.message}`,
        engine: ENGINE,
        model: modelLabel,
        sessionId: id || requestedId || null,
        status: 'error',
        errorCode: classified.errorCode,
        errorDetail: classified.errorDetail,
        retryClass: classified.retryClass,
      }
    }
    throw err
  } finally {
    await releaseSessionLease(entry)
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '/', `http://127.0.0.1:${PORT}`)

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    })
    res.end()
    return
  }

  if (req.method === 'GET' && url.pathname === '/health') {
    // ok = operationally usable (consecutive SDK run errors under threshold), not TCP-only.
    sendJson(
      res,
      200,
      getHealthPayload({
        engine: ENGINE,
        model: activeModelLabel || MODEL,
        apiKeyPresent: Boolean(process.env.CURSOR_API_KEY),
      }),
    )
    return
  }

  if (req.method === 'POST' && url.pathname === '/v1/complete') {
    // Node http does not serialize handlers; overlapping /v1/complete is real (Inspect + Ops).
    // Session activeRuns lease is the disposal safety net (defense in depth).
    try {
      const body = await readJson(req)
      const prompt = String(body.prompt || '').trim()
      if (!prompt) {
        sendJson(res, 400, { error: 'prompt required' })
        return
      }
      const result = await complete({
        prompt,
        cwd: body.cwd,
        context: body.context,
        sessionId: body.sessionId,
        images: body.images,
        model: body.model,
      })
      sendJson(res, 200, result)
    } catch (err) {
      sendJson(res, 500, {
        ok: false,
        error: err?.message || String(err),
        engine: ENGINE,
        model: MODEL,
        status: 'error',
      })
    }
    return
  }

  sendJson(res, 404, { error: 'not found' })
})

server.on('error', (err) => {
  const code = err && err.code ? String(err.code) : ''
  const msg = err && err.message ? String(err.message) : String(err)
  const line = `[ask-cursor] listen error code=${code || 'n/a'} detail=${msg}`
  console.error(line)
  appendRunsLog(line)
  process.exit(1)
})

server.listen(PORT, '127.0.0.1', () => {
  const line = `Metra Ask engine (cursor) on http://127.0.0.1:${PORT} pid=${process.pid}`
  console.log(line)
  appendRunsLog(`[ask-cursor] listen ok ${line}`)
})

async function shutdown() {
  try {
    await disposeAllSessions()
  } catch {
    /* ignore */
  }
  server.close(() => process.exit(0))
  setTimeout(() => process.exit(0), 2000).unref()
}

process.on('SIGINT', () => {
  void shutdown()
})
process.on('SIGTERM', () => {
  void shutdown()
})
