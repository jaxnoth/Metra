/**
 * Node tests for Cursor Ask session-cache (no SDK / no network).
 * Run: node --test engines/cursor/session-cache.test.mjs
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  MAX_SESSIONS,
  acquireSessionLease,
  classifyRunError,
  createSessionEntry,
  disposeAgent,
  disposeAllSessions,
  getConsecutiveRunErrors,
  getHealthPayload,
  getSession,
  normalizeSessionEntry,
  putSession,
  recordRunError,
  recordRunFinished,
  releaseSessionLease,
  resetSessionCacheForTests,
  retireSession,
  sessions,
} from './session-cache.mjs'

function mockAgent(label) {
  let disposed = 0
  return {
    label,
    get disposedCount() {
      return disposed
    },
    async [Symbol.asyncDispose]() {
      disposed += 1
    },
  }
}

test('normalize upgrades legacy bare agent', () => {
  resetSessionCacheForTests()
  const agent = mockAgent('legacy')
  const entry = normalizeSessionEntry(agent)
  assert.equal(entry.agent, agent)
  assert.equal(entry.modelKey, null)
  assert.equal(entry.activeRuns, 0)
})

test('retire then dispose when idle', async () => {
  resetSessionCacheForTests()
  const agent = mockAgent('a')
  const entry = createSessionEntry(agent, 'm')
  await putSession('s1', entry)
  await retireSession('s1', entry)
  assert.equal(sessions.has('s1'), false)
  assert.equal(agent.disposedCount, 1)
})

test('retire does not dispose while leased; release does', async () => {
  resetSessionCacheForTests()
  const agent = mockAgent('leased')
  const entry = createSessionEntry(agent, 'm')
  await putSession('s1', entry)
  acquireSessionLease(entry)
  await retireSession('s1', entry)
  assert.equal(agent.disposedCount, 0)
  await releaseSessionLease(entry)
  assert.equal(agent.disposedCount, 1)
})

test('replacement retires prior agent', async () => {
  resetSessionCacheForTests()
  const a1 = mockAgent('old')
  const a2 = mockAgent('new')
  await putSession('s1', createSessionEntry(a1, 'm1'))
  await putSession('s1', createSessionEntry(a2, 'm2'))
  assert.equal(a1.disposedCount, 1)
  assert.equal(sessions.get('s1').agent, a2)
})

test('LRU evicts oldest idle on ninth unique session', async () => {
  resetSessionCacheForTests()
  const agents = []
  for (let i = 0; i < MAX_SESSIONS; i++) {
    const a = mockAgent(`a${i}`)
    agents.push(a)
    await putSession(`s${i}`, createSessionEntry(a, 'm'))
    // Stagger lastUsedAt via touch order
    acquireSessionLease(sessions.get(`s${i}`))
    await releaseSessionLease(sessions.get(`s${i}`))
  }
  assert.equal(sessions.size, MAX_SESSIONS)
  const ninth = mockAgent('ninth')
  await putSession('s9', createSessionEntry(ninth, 'm'))
  assert.ok(sessions.size <= MAX_SESSIONS)
  assert.equal(sessions.has('s9'), true)
  // At least one of the first agents was disposed
  assert.ok(agents.some((a) => a.disposedCount >= 1))
})

test('health counter and ok gate', () => {
  resetSessionCacheForTests()
  let h = getHealthPayload({ engine: 'cursor', model: 'x', apiKeyPresent: true })
  assert.equal(h.ok, true)
  assert.equal(h.consecutiveRunErrors, 0)
  assert.equal(h.lastRunStatus, null)

  recordRunError()
  h = getHealthPayload({ engine: 'cursor', model: 'x', apiKeyPresent: true })
  assert.equal(h.ok, true)
  assert.equal(h.consecutiveRunErrors, 1)
  assert.equal(h.lastRunStatus, 'error')
  assert.ok(h.lastRunAt)

  recordRunError()
  h = getHealthPayload({ engine: 'cursor', model: 'x', apiKeyPresent: true })
  assert.equal(h.ok, false)
  assert.equal(h.consecutiveRunErrors, 2)

  recordRunFinished()
  h = getHealthPayload({ engine: 'cursor', model: 'x', apiKeyPresent: true })
  assert.equal(h.ok, true)
  assert.equal(getConsecutiveRunErrors(), 0)
  assert.equal(h.lastRunStatus, 'finished')
})

test('classifyRunError opaque vs nonempty', () => {
  assert.equal(classifyRunError('').retryClass, 'opaque_sdk_failure')
  assert.equal(classifyRunError('requestId=abc').retryClass, 'opaque_sdk_failure')
  assert.equal(classifyRunError('rate limited').retryClass, 'sdk_run_error')
})

test('disposeAgent tolerates null and prefer asyncDispose once', async () => {
  await disposeAgent(null)
  let closed = 0
  let asyncDisposed = 0
  const both = {
    async [Symbol.asyncDispose]() {
      asyncDisposed += 1
    },
    async close() {
      closed += 1
    },
  }
  await disposeAgent(both)
  assert.equal(asyncDisposed, 1)
  assert.equal(closed, 0)
})

test('disposeAllSessions clears map', async () => {
  resetSessionCacheForTests()
  const a = mockAgent('all')
  await putSession('x', createSessionEntry(a, 'm'))
  await disposeAllSessions()
  assert.equal(sessions.size, 0)
  assert.equal(a.disposedCount, 1)
})

test('getSession upgrades legacy entry in place', () => {
  resetSessionCacheForTests()
  const agent = mockAgent('bare')
  sessions.set('legacy', agent)
  const entry = getSession('legacy')
  assert.equal(entry.agent, agent)
  assert.ok(sessions.get('legacy').agent)
})
