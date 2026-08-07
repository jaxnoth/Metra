/**
 * Metra Ask engine - Cursor implementer.
 * Loopback contract only: GET /health, POST /v1/complete.
 * Answer-only: do not edit, create, or delete files; do not run mutating commands.
 */
import http from 'node:http'
import { Agent, CursorAgentError } from '@cursor/sdk'

const PORT = Number(process.env.METRA_ASK_PORT || 7381)
const MODEL = process.env.METRA_ASK_MODEL || 'composer-2.5'
const ENGINE = 'cursor'

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

function buildPrompt(userPrompt, context, options = {}) {
  const where = context?.where || 'Metra'
  const what = context?.what || ''
  const why = Array.isArray(context?.why) ? context.why.filter(Boolean).join('; ') : ''
  const forWhom = Array.isArray(context?.forWhom) ? context.forWhom.filter(Boolean).join('; ') : ''
  const includeJournal =
    Boolean(options.includeJournalContinuity) ||
    Boolean(context?.forceContinuity) ||
    Boolean(context?.recall)

  const sessionSummary = includeJournal && context?.sessionSummary
    ? String(context.sessionSummary).trim()
    : ''
  const recentBlock = includeJournal ? formatRecentTurns(context?.recentTurns) : null
  const recallBlock = context?.recall ? String(context.recall).trim() : ''
  const recallSid = context?.recallSessionId ? String(context.recallSessionId).trim() : ''

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
    'Route context from Metra (use for cwd and focus - do not reprint as labels):',
    `- Where: ${where}`,
    what ? `- What: ${what}` : null,
    why ? `- Why: ${why}` : null,
    forWhom ? `- For whom: ${forWhom}` : null,
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

async function complete({ prompt, cwd, context, sessionId }) {
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

  let agent
  let newSession = false
  if (sessionId && sessions.has(sessionId)) {
    agent = sessions.get(sessionId)
  } else {
    agent = await Agent.create({
      apiKey,
      model: { id: MODEL },
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
  })

  try {
    const run = await agent.send(wrapped)
    const result = await run.wait()
    if (result.status === 'error') {
      return {
        message: 'The Ask engine run failed. Try again, or use Classify for routing only.',
        engine: ENGINE,
        model: MODEL,
        sessionId: id,
        status: 'error',
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
