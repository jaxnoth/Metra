/**
 * Metra Ask engine - Cursor implementer.
 * Loopback contract only: GET /health, POST /v1/complete.
 * Answer-only: do not edit, create, or delete files; do not run mutating commands.
 */
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import { Agent, CursorAgentError } from '@cursor/sdk'

const PORT = Number(process.env.METRA_ASK_PORT || 7381)
const ENGINE = 'cursor'

/**
 * Cursor Ask defaults to Auto Cost (Cursor Router) - legacy Auto behavior on the
 * Cursor Models pool. Balance/Intelligence remain available via optimize_for.
 * Wire: auto-smart + optimize_for=cost.
 */
function resolveModelSelection() {
  const rawId = String(process.env.METRA_ASK_MODEL || 'auto-smart').trim()
  const rawOpt = String(process.env.METRA_ASK_OPTIMIZE_FOR || 'cost')
    .trim()
    .toLowerCase()
  const aliasMap = {
    'auto-cost': 'auto-smart',
    'auto cost': 'auto-smart',
    cost: 'auto-smart',
    auto: 'auto-smart',
    'auto-balance': 'auto-smart',
    'auto balance': 'auto-smart',
    balance: 'auto-smart',
    balanced: 'auto-smart',
    'auto-intelligence': 'auto-smart',
    'auto intelligence': 'auto-smart',
    intelligence: 'auto-smart',
  }
  const aliasOptimize = {
    'auto-cost': 'cost',
    'auto cost': 'cost',
    cost: 'cost',
    auto: 'cost',
    'auto-balance': 'balanced',
    'auto balance': 'balanced',
    balance: 'balanced',
    balanced: 'balanced',
    'auto-intelligence': 'intelligence',
    'auto intelligence': 'intelligence',
    intelligence: 'intelligence',
  }
  const rawLower = rawId.toLowerCase()
  const id = aliasMap[rawLower] || rawId || 'auto-smart'
  if (id === 'auto-smart') {
    const fromAlias = aliasOptimize[rawLower]
    const optimizeFor = fromAlias
      ? fromAlias
      : ['cost', 'balanced', 'intelligence'].includes(rawOpt)
        ? rawOpt
        : 'cost'
    return {
      id: 'auto-smart',
      params: [{ id: 'optimize_for', value: optimizeFor }],
      label: `auto-smart/${optimizeFor}`,
    }
  }
  return { id, label: id }
}

const MODEL_SELECTION = resolveModelSelection()
const MODEL = MODEL_SELECTION.label

/** @type {Map<string, Awaited<ReturnType<typeof Agent.create>>>} */
const sessions = new Map()

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

async function complete({ prompt, cwd, context, sessionId, images }) {
  const apiKey = process.env.CURSOR_API_KEY
  if (!apiKey) {
    const err = new Error('CURSOR_API_KEY missing')
    err.code = 'key_missing'
    throw err
  }

  const promptScrub = scrubSecretsText(prompt)
  const ctxScrub = scrubSecretsValue(context || {})
  if (promptScrub.refuse || ctxScrub.refuse) {
    return {
      message:
        promptScrub.notice ||
        ctxScrub.notice ||
        'Private-key material was blocked and not sent to the Ask engine. Rephrase without the key block.',
      engine: ENGINE,
      model: MODEL,
      sessionId: sessionId || null,
      status: 'refused',
      secretsRefuse: true,
      secretsReason: promptScrub.reason || ctxScrub.reason || 'pem_private_key',
    }
  }

  const workDir = cwd && typeof cwd === 'string' && cwd.length > 0 ? cwd : process.cwd()
  const sdkImages = loadImagesFromRefs(images)

  let agent
  let newSession = false
  if (sessionId && sessions.has(sessionId)) {
    agent = sessions.get(sessionId)
  } else {
    const modelOpt =
      MODEL_SELECTION.params && MODEL_SELECTION.params.length > 0
        ? { id: MODEL_SELECTION.id, params: MODEL_SELECTION.params }
        : { id: MODEL_SELECTION.id }
    agent = await Agent.create({
      apiKey,
      model: modelOpt,
      local: { cwd: workDir, settingSources: [] },
    })
    newSession = true
  }

  const id =
    sessionId && String(sessionId).trim()
      ? String(sessionId).trim()
      : agent.agentId || `local-${Date.now()}`
  if (newSession) {
    sessions.set(id, agent)
  }

  const wrapped = buildPrompt(promptScrub.text, ctxScrub.value || {}, {
    includeJournalContinuity: newSession,
    hasImages: sdkImages.length > 0,
  })

  try {
    const run =
      sdkImages.length > 0
        ? await agent.send({ text: wrapped, images: sdkImages })
        : await agent.send(wrapped)
    const result = await run.wait()
    if (result.status === 'error') {
      // Prefer SDK error text when present; otherwise keep the desk-safe fallback.
      let detail = ''
      if (typeof result.result === 'string' && result.result.trim()) {
        detail = result.result.trim()
      } else if (result.result && typeof result.result === 'object') {
        detail = String(result.result.message || result.result.error || '').trim()
      }
      if (detail.length > 400) detail = `${detail.slice(0, 399)}...`
      const scrubbed = detail ? scrubSecretsText(detail) : { text: '' }
      const message = scrubbed.text
        ? `The Ask engine run failed: ${scrubbed.text}`
        : 'The Ask engine run failed. Try again, or use Classify for routing only.'
      console.error(
        `[ask-cursor] run error id=${result.id || 'n/a'} requestId=${result.requestId || 'n/a'} durationMs=${result.durationMs ?? 'n/a'} detail=${scrubbed.text || '(none)'}`,
      )
      return {
        message,
        engine: ENGINE,
        model: MODEL,
        sessionId: id,
        status: 'error',
        runId: result.id || null,
        requestId: result.requestId || null,
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
    if (!text) {
      text = 'Metra answered, but the engine returned no text.'
    }

    const outScrub = scrubSecretsText(stripDeskChrome(text))
    return {
      message: outScrub.text,
      engine: ENGINE,
      model: MODEL,
      sessionId: id,
      status: result.status || 'finished',
    }
  } catch (err) {
    if (err instanceof CursorAgentError) {
      return {
        message: `Ask engine could not start: ${err.message}`,
        engine: ENGINE,
        model: MODEL,
        sessionId: id,
        status: 'error',
      }
    }
    throw err
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
    sendJson(res, 200, {
      ok: true,
      engine: ENGINE,
      model: MODEL,
    })
    return
  }

  if (req.method === 'POST' && url.pathname === '/v1/complete') {
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

server.listen(PORT, '127.0.0.1', () => {
  console.log(`Metra Ask engine (cursor) on http://127.0.0.1:${PORT}`)
})

function shutdown() {
  for (const agent of sessions.values()) {
    try {
      if (typeof agent[Symbol.asyncDispose] === 'function') {
        void agent[Symbol.asyncDispose]()
      } else if (typeof agent.close === 'function') {
        agent.close()
      }
    } catch {
      /* ignore */
    }
  }
  sessions.clear()
  server.close(() => process.exit(0))
  setTimeout(() => process.exit(0), 2000).unref()
}

process.on('SIGINT', shutdown)
process.on('SIGTERM', shutdown)
