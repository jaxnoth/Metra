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

function buildPrompt(userPrompt, context) {
  const where = context?.where || 'Metra'
  const what = context?.what || ''
  const why = Array.isArray(context?.why) ? context.why.filter(Boolean).join('; ') : ''
  const forWhom = Array.isArray(context?.forWhom) ? context.forWhom.filter(Boolean).join('; ') : ''

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

async function complete({ prompt, cwd, context, sessionId }) {
  const apiKey = process.env.CURSOR_API_KEY
  if (!apiKey) {
    const err = new Error('CURSOR_API_KEY missing')
    err.code = 'key_missing'
    throw err
  }

  const workDir = cwd && typeof cwd === 'string' && cwd.length > 0 ? cwd : process.cwd()
  const wrapped = buildPrompt(prompt, context || {})

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

  const id = sessionId && sessions.has(sessionId) ? sessionId : agent.agentId || `local-${Date.now()}`
  if (newSession) {
    sessions.set(id, agent)
  }

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

    return {
      message: stripDeskChrome(text),
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
