/**
 * Node tests for Loom implementer-run.mjs (mocked SDK; no live network).
 * Run: node --test engines/cursor/implementer-run.test.mjs
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const runner = path.join(here, 'implementer-run.mjs')
const mockSdk = path.join(here, 'implementer-mock-sdk.mjs')

function writeRequest(dir, overrides = {}) {
  const req = {
    schemaVersion: 1,
    itemId: 'AP-TEST-0001',
    projectRoot: dir,
    summary: 'test',
    planBody: '# plan\nDo nothing harmful.',
    allowedPaths: ['docs'],
    forbiddenPaths: [],
    doneWhen: ['ok'],
    ...overrides,
  }
  const p = path.join(dir, 'request.json')
  fs.writeFileSync(p, JSON.stringify(req, null, 2), 'utf8')
  return p
}

function runNode(args, envExtra = {}) {
  const env = {
    ...process.env,
    CURSOR_API_KEY: envExtra.CURSOR_API_KEY ?? 'test-key-not-real',
    METRA_IMPLEMENTER_SDK_MOCK: mockSdk,
    METRA_IMPLEMENTER_MOCK_MODE: envExtra.METRA_IMPLEMENTER_MOCK_MODE || 'success',
    METRA_ASK_MODEL: envExtra.METRA_ASK_MODEL || 'composer-2.5',
    METRA_ASK_OPTIMIZE_FOR: envExtra.METRA_ASK_OPTIMIZE_FOR || 'cost',
    ...envExtra,
  }
  delete env.METRA_IMPLEMENTER_SDK_MOCK_OVERRIDE
  return spawnSync(process.execPath, [runner, ...args], {
    encoding: 'utf8',
    env,
    cwd: here,
  })
}

function parseStdoutJson(stdout) {
  const text = String(stdout || '').trim()
  assert.ok(text, 'stdout must not be empty')
  const lines = text.split(/\r?\n/).filter((l) => l.trim())
  assert.equal(lines.length, 1, 'stdout must contain only the result envelope')
  return JSON.parse(lines[0])
}

test('missing --request fails', () => {
  const r = runNode([])
  assert.notEqual(r.status, 0)
  const body = parseStdoutJson(r.stdout)
  assert.equal(body.status, 'failed')
  assert.match(body.message, /Usage:/i)
})

test('missing request file fails', () => {
  const missing = path.join(os.tmpdir(), `metra-impl-missing-${Date.now()}.json`)
  const r = runNode(['--request', missing])
  assert.notEqual(r.status, 0)
  const body = parseStdoutJson(r.stdout)
  assert.equal(body.status, 'failed')
  assert.match(body.message, /not found/i)
})

test('invalid JSON fails', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'metra-impl-'))
  const p = path.join(dir, 'bad.json')
  fs.writeFileSync(p, '{not-json', 'utf8')
  const r = runNode(['--request', p])
  assert.notEqual(r.status, 0)
  const body = parseStdoutJson(r.stdout)
  assert.equal(body.status, 'failed')
  assert.match(body.message, /Invalid request JSON/i)
})

test('required request fields absent fails', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'metra-impl-'))
  const p = path.join(dir, 'request.json')
  fs.writeFileSync(p, JSON.stringify({ schemaVersion: 1 }), 'utf8')
  const r = runNode(['--request', p])
  assert.notEqual(r.status, 0)
  const body = parseStdoutJson(r.stdout)
  assert.equal(body.status, 'failed')
  assert.match(body.message, /Required request field missing/i)
})

test('SDK success with status=ok returns ok envelope', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'metra-impl-'))
  const p = writeRequest(dir)
  const r = runNode(['--request', p], { METRA_IMPLEMENTER_MOCK_MODE: 'success' })
  assert.equal(r.status, 0)
  const body = parseStdoutJson(r.stdout)
  assert.equal(body.schemaVersion, 1)
  assert.equal(body.status, 'ok')
  assert.match(body.message, /ok/i)
})

test('SDK success with status=completed returns completed envelope', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'metra-impl-'))
  const p = writeRequest(dir)
  const r = runNode(['--request', p], { METRA_IMPLEMENTER_MOCK_MODE: 'success-completed' })
  assert.equal(r.status, 0)
  const body = parseStdoutJson(r.stdout)
  assert.equal(body.status, 'completed')
})

test('SDK success with status=finished returns completed envelope', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'metra-impl-'))
  const p = writeRequest(dir)
  const r = runNode(['--request', p], { METRA_IMPLEMENTER_MOCK_MODE: 'success-finished' })
  assert.equal(r.status, 0)
  const body = parseStdoutJson(r.stdout)
  assert.equal(body.status, 'completed')
})

test('SDK changedFiles without status still succeeds', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'metra-impl-'))
  const p = writeRequest(dir)
  const r = runNode(['--request', p], { METRA_IMPLEMENTER_MOCK_MODE: 'changed-files' })
  assert.equal(r.status, 0)
  const body = parseStdoutJson(r.stdout)
  assert.equal(body.status, 'completed')
})

test('SDK text without status=ok|completed|finished fails', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'metra-impl-'))
  const p = writeRequest(dir)
  const r = runNode(['--request', p], { METRA_IMPLEMENTER_MOCK_MODE: 'text-only' })
  assert.notEqual(r.status, 0)
  const body = parseStdoutJson(r.stdout)
  assert.equal(body.status, 'failed')
  assert.match(body.message, /status=ok\|completed\|finished|non-empty text alone/i)
})

test('SDK empty response fails', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'metra-impl-'))
  const p = writeRequest(dir)
  const r = runNode(['--request', p], { METRA_IMPLEMENTER_MOCK_MODE: 'empty' })
  assert.notEqual(r.status, 0)
  const body = parseStdoutJson(r.stdout)
  assert.equal(body.status, 'failed')
  assert.match(body.message, /status=ok\|completed\|finished|not an object|explicit success/i)
})

test('authentication response fails', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'metra-impl-'))
  const p = writeRequest(dir)
  const r = runNode(['--request', p], { METRA_IMPLEMENTER_MOCK_MODE: 'auth' })
  assert.notEqual(r.status, 0)
  const body = parseStdoutJson(r.stdout)
  assert.match(body.message, /authentication error/i)
})

test('licensing response fails', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'metra-impl-'))
  const p = writeRequest(dir)
  const r = runNode(['--request', p], { METRA_IMPLEMENTER_MOCK_MODE: 'licensing' })
  assert.notEqual(r.status, 0)
  const body = parseStdoutJson(r.stdout)
  assert.match(body.message, /usage limit|billing|quota/i)
})

test('transient SDK error fails with transient text', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'metra-impl-'))
  const p = writeRequest(dir)
  const r = runNode(['--request', p], { METRA_IMPLEMENTER_MOCK_MODE: 'transient' })
  assert.notEqual(r.status, 0)
  const body = parseStdoutJson(r.stdout)
  assert.match(body.message, /transient|connection reset/i)
})
