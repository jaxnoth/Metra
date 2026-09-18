/**
 * Metra Loom implementer - one-shot mutating Cursor SDK run.
 * Locked CLI: node implementer-run.mjs --request <absolute-request-json-path>
 * stdout: one contract JSON object. stderr: diagnostics only.
 */
import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'
import {
  resolveModelSelection,
  toSdkModelOpt,
} from './model-selection.mjs'

const REQUIRED_REQUEST_FIELDS = ['schemaVersion', 'itemId', 'projectRoot']

function writeResult(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n')
}

function fail(message, exitCode = 1, extra = {}) {
  writeResult({
    schemaVersion: 1,
    status: 'failed',
    message: String(message || 'implementer failed'),
    exitCode,
    ...extra,
  })
  process.exitCode = exitCode
}

function parseArgs(argv) {
  const args = argv.slice(2)
  if (args.length !== 2 || args[0] !== '--request') {
    return { error: 'Usage: node implementer-run.mjs --request <absolute-request-json-path>' }
  }
  const requestPath = args[1]
  if (!requestPath || !path.isAbsolute(requestPath)) {
    return { error: 'Request path must be an absolute path.' }
  }
  return { requestPath }
}

function loadRequest(requestPath) {
  if (!fs.existsSync(requestPath)) {
    throw Object.assign(new Error(`Request file not found: ${requestPath}`), { code: 'ENOENT' })
  }
  const raw = fs.readFileSync(requestPath, 'utf8')
  let parsed
  try {
    parsed = JSON.parse(raw)
  } catch (err) {
    throw new Error(`Invalid request JSON: ${err.message}`)
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('Request JSON must be a non-array object.')
  }
  for (const field of REQUIRED_REQUEST_FIELDS) {
    if (parsed[field] === undefined || parsed[field] === null || String(parsed[field]).trim() === '') {
      throw new Error(`Required request field missing: ${field}`)
    }
  }
  return parsed
}

function buildPrompt(request) {
  const allowed = Array.isArray(request.allowedPaths) ? request.allowedPaths : []
  const forbidden = Array.isArray(request.forbiddenPaths) ? request.forbiddenPaths : []
  const doneWhen = Array.isArray(request.doneWhen) ? request.doneWhen : []
  const summary = String(request.summary || '')
  const planBody = String(request.planBody || '')
  const agentGuidance = String(request.agentGuidance || '')

  return [
    'You are the Metra Loom implementer agent.',
    'Implement the formal plan in this context package.',
    'Edit files only under the process working directory (project root).',
    'allowedPaths / forbiddenPaths / doneWhen are guidance only - Loom Runner enforces path policy after you return.',
    'Do not accept the work item, expand scope, or create git commits unless the plan explicitly requires a commit.',
    'Do not invent requirements beyond the plan body and doneWhen.',
    agentGuidance ? `\nAgent guidance:\n${agentGuidance}` : '',
    `\nSummary: ${summary}`,
    `\nallowedPaths: ${JSON.stringify(allowed)}`,
    `\nforbiddenPaths: ${JSON.stringify(forbidden)}`,
    `\ndoneWhen: ${JSON.stringify(doneWhen)}`,
    '\n--- plan body ---\n',
    planBody || '(empty plan body)',
  ].join('\n')
}

async function loadSdk() {
  const mockPath = process.env.METRA_IMPLEMENTER_SDK_MOCK
  if (mockPath && String(mockPath).trim()) {
    const abs = path.isAbsolute(mockPath) ? mockPath : path.resolve(mockPath)
    return import(pathToFileURL(abs).href)
  }
  return import('@cursor/sdk')
}

function extractResultText(result) {
  if (!result) return ''
  if (typeof result === 'string') return result
  if (result.error?.message) return String(result.error.message)
  if (typeof result.result === 'string') return result.result
  if (result.message) return String(result.message)

  try {
    return JSON.stringify(result)
  } catch {
    return String(result)
  }
}

/**
 * Success requires an explicit SDK status of ok|completed|finished (not merely non-empty text).
 * `finished` is the Cursor SDK run-end status (same family as Ask engine); map to completed.
 * Optional changed-file signals also count when status is absent but files were reported.
 * Tree delta enforcement stays with the Loom Runner (authoritative path policy).
 */
function resolveSdkSuccess(result) {
  if (!result || typeof result !== 'object' || Array.isArray(result)) {
    return { ok: false, reason: 'SDK result was not an object with an explicit success status.' }
  }

  const rawStatus = result.status === undefined || result.status === null ? '' : String(result.status).trim()
  const status = rawStatus.toLowerCase()

  if (status === 'error' || status === 'failed') {
    const detail = extractResultText(result) || 'SDK reported error status.'
    return { ok: false, reason: detail }
  }

  if (status === 'ok' || status === 'completed' || status === 'finished') {
    return { ok: true, envelopeStatus: status === 'ok' ? 'ok' : 'completed' }
  }

  const changed =
    (Array.isArray(result.changedFiles) && result.changedFiles.length > 0) ||
    (Array.isArray(result.changedPaths) && result.changedPaths.length > 0) ||
    (typeof result.changedFileCount === 'number' && result.changedFileCount > 0)

  if (changed) {
    return { ok: true, envelopeStatus: 'completed' }
  }

  if (!status) {
    return {
      ok: false,
      reason:
        'SDK did not report status=ok|completed|finished (non-empty text alone is not success).',
    }
  }

  return {
    ok: false,
    reason: `Unsupported SDK status for implementer success: ${rawStatus}`,
  }
}

async function runImplementer(request) {
  const selection = resolveModelSelection()
  if (!selection || !selection.id || !String(selection.id).trim()) {
    fail('Model selection returned no usable model.', 1)
    return
  }

  const apiKey = String(process.env.CURSOR_API_KEY || '').trim()
  if (!apiKey) {
    fail('CURSOR_API_KEY is missing (authentication error).', 1)
    return
  }

  const prompt = buildPrompt(request)
  const cwd = process.cwd()
  const sdk = await loadSdk()
  const Agent = sdk.Agent
  if (!Agent || typeof Agent.create !== 'function') {
    fail('Implementer SDK unavailable (empty SDK Agent.create).', 1)
    return
  }

  const opt = toSdkModelOpt(selection)
  let agent
  try {
    agent = await Agent.create({
      apiKey,
      model: opt,
      local: { cwd, settingSources: [] },
    })
  } catch (err) {
    const msg = String(err?.message || err || 'Agent.create failed')
    fail(msg, 1)
    return
  }

  let run
  try {
    run = await agent.send(prompt)
  } catch (err) {
    const msg = String(err?.message || err || 'agent.send failed')
    fail(msg, 1)
    return
  }

  let result
  try {
    result = typeof run?.wait === 'function' ? await run.wait() : run
  } catch (err) {
    const msg = String(err?.message || err || 'agent wait failed')
    fail(msg, 1)
    return
  }

  const detail = extractResultText(result)
  if (result?.status === 'error' || /usage limit|billing|quota|licensing|authentication error|api key/i.test(detail)) {
    // Prefer explicit failure classification before success gating.
    if (!detail || !String(detail).trim()) {
      fail('SDK reported an error with empty detail.', 1)
      return
    }
    fail(detail, 1)
    return
  }

  const success = resolveSdkSuccess(result)
  if (!success.ok) {
    fail(success.reason || 'SDK did not report implementer success.', 1)
    return
  }

  writeResult({
    schemaVersion: 1,
    status: success.envelopeStatus,
    message:
      success.envelopeStatus === 'ok'
        ? 'Implementation run ok.'
        : 'Implementation run completed.',
    exitCode: 0,
  })
  process.exitCode = 0
}

async function main() {
  const parsed = parseArgs(process.argv)
  if (parsed.error) {
    process.stderr.write(parsed.error + '\n')
    fail(parsed.error, 2)
    return
  }

  let request
  try {
    request = loadRequest(parsed.requestPath)
  } catch (err) {
    const msg = String(err?.message || err)
    process.stderr.write(msg + '\n')
    fail(msg, 2)
    return
  }

  try {
    await runImplementer(request)
  } catch (err) {
    const msg = String(err?.message || err || 'implementer unexpected error')
    process.stderr.write(msg + '\n')
    fail(msg, 1)
  }
}

await main()
