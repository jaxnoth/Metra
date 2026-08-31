/**
 * Cursor Ask sidecar session cache + run-health counters.
 * Lease/retire-then-dispose so agents are never disposed mid-run.
 * HTTP /v1/complete may overlap (phone + Inspect); activeRuns is the lease.
 */

export const MAX_SESSIONS = 8
export const HEALTH_ERROR_THRESHOLD = 2

/**
 * @typedef {{
 *   agent: object,
 *   modelKey: string | null,
 *   lastUsedAt: number,
 *   activeRuns: number,
 *   retiring: boolean,
 *   insertSeq: number,
 * }} SessionEntry
 */

/** @type {Map<string, SessionEntry>} */
export const sessions = new Map()

let insertSeqCounter = 0
let consecutiveRunErrors = 0
/** @type {string | null} */
let lastRunStatus = null
/** @type {string | null} */
let lastRunAt = null

export function resetSessionCacheForTests() {
  sessions.clear()
  insertSeqCounter = 0
  consecutiveRunErrors = 0
  lastRunStatus = null
  lastRunAt = null
}

/**
 * Prefer asyncDispose, else close. One mechanism only. Never throws.
 * @param {object | null | undefined} agent
 */
export async function disposeAgent(agent) {
  if (!agent) return
  try {
    if (typeof agent[Symbol.asyncDispose] === 'function') {
      await agent[Symbol.asyncDispose]()
    } else if (typeof agent.close === 'function') {
      await agent.close()
    }
  } catch (error) {
    console.warn('[ask-cursor] agent disposal failed', {
      message: error?.message ?? String(error),
    })
  }
}

/**
 * Accepts legacy bare-agent values and upgrades them.
 * When raw is already a complete SessionEntry, return the SAME object reference
 * so activeRuns leases stay synchronized across concurrent callers.
 * @param {unknown} raw
 * @returns {SessionEntry | null}
 */
export function normalizeSessionEntry(raw) {
  if (!raw) return null
  if (typeof raw === 'object' && raw !== null && 'agent' in raw && raw.agent) {
    const e = /** @type {Partial<SessionEntry> & { agent: object }} */ (raw)
    const complete =
      typeof e.lastUsedAt === 'number' &&
      typeof e.activeRuns === 'number' &&
      typeof e.insertSeq === 'number' &&
      typeof e.retiring === 'boolean'
    if (complete) {
      if (e.modelKey != null) e.modelKey = String(e.modelKey)
      return /** @type {SessionEntry} */ (e)
    }
    return {
      agent: e.agent,
      modelKey: e.modelKey != null ? String(e.modelKey) : null,
      lastUsedAt: typeof e.lastUsedAt === 'number' ? e.lastUsedAt : Date.now(),
      activeRuns: typeof e.activeRuns === 'number' ? e.activeRuns : 0,
      retiring: Boolean(e.retiring),
      insertSeq: typeof e.insertSeq === 'number' ? e.insertSeq : ++insertSeqCounter,
    }
  }
  return {
    agent: /** @type {object} */ (raw),
    modelKey: null,
    lastUsedAt: Date.now(),
    activeRuns: 0,
    retiring: false,
    insertSeq: ++insertSeqCounter,
  }
}

/**
 * @param {object} agent
 * @param {string} modelKey
 * @returns {SessionEntry}
 */
export function createSessionEntry(agent, modelKey) {
  return {
    agent,
    modelKey: modelKey != null ? String(modelKey) : null,
    lastUsedAt: Date.now(),
    activeRuns: 0,
    retiring: false,
    insertSeq: ++insertSeqCounter,
  }
}

/**
 * Remove from map immediately; dispose only when not leased.
 * @param {string} sessionId
 * @param {SessionEntry} entry
 */
export async function retireSession(sessionId, entry) {
  if (!entry) return
  sessions.delete(sessionId)
  entry.retiring = true
  if (entry.activeRuns === 0) {
    await disposeAgent(entry.agent)
  }
}

/**
 * After a run finishes (success or failure path that leased the entry).
 * @param {SessionEntry} entry
 */
export async function releaseSessionLease(entry) {
  if (!entry) return
  entry.activeRuns = Math.max(0, (entry.activeRuns || 0) - 1)
  if (entry.retiring && entry.activeRuns === 0) {
    await disposeAgent(entry.agent)
  }
}

/**
 * Mark selected for a run (updates LRU clock + lease).
 * @param {SessionEntry} entry
 */
export function acquireSessionLease(entry) {
  if (!entry) return
  entry.activeRuns = (entry.activeRuns || 0) + 1
  entry.lastUsedAt = Date.now()
}

/**
 * Evict oldest idle (activeRuns === 0) entries until size <= MAX_SESSIONS.
 * Never evicts excludeSessionId. Deletes from map before awaiting dispose.
 * @param {string | null} excludeSessionId
 */
export async function enforceSessionCap(excludeSessionId = null) {
  while (sessions.size > MAX_SESSIONS) {
    let victimId = null
    /** @type {SessionEntry | null} */
    let victim = null
    for (const [id, raw] of sessions) {
      if (excludeSessionId && id === excludeSessionId) continue
      const entry = normalizeSessionEntry(raw)
      if (!entry || entry.activeRuns > 0 || entry.retiring) continue
      if (
        !victim ||
        entry.lastUsedAt < victim.lastUsedAt ||
        (entry.lastUsedAt === victim.lastUsedAt && entry.insertSeq < victim.insertSeq)
      ) {
        victimId = id
        victim = entry
      }
    }
    if (!victimId || !victim) {
      // All remaining are active or protected; stop to avoid disposing mid-run.
      break
    }
    await retireSession(victimId, victim)
  }
}

/**
 * Store or replace a session entry, retiring the previous agent if present.
 * @param {string} sessionId
 * @param {SessionEntry} entry
 */
export async function putSession(sessionId, entry) {
  const prior = sessions.get(sessionId)
  if (prior) {
    const priorEntry = normalizeSessionEntry(prior)
    if (priorEntry && priorEntry.agent !== entry.agent) {
      await retireSession(sessionId, priorEntry)
    }
  }
  sessions.set(sessionId, entry)
  await enforceSessionCap(sessionId)
}

/**
 * @param {string} sessionId
 * @returns {SessionEntry | null}
 */
export function getSession(sessionId) {
  if (!sessionId || !sessions.has(sessionId)) return null
  const entry = normalizeSessionEntry(sessions.get(sessionId))
  if (entry && sessions.has(sessionId)) {
    // Upgrade legacy bare entries in place.
    sessions.set(sessionId, entry)
  }
  return entry
}

export function recordRunFinished() {
  consecutiveRunErrors = 0
  lastRunStatus = 'finished'
  lastRunAt = new Date().toISOString()
}

export function recordRunError() {
  consecutiveRunErrors += 1
  lastRunStatus = 'error'
  lastRunAt = new Date().toISOString()
}

/**
 * Health ok means operationally usable (consecutive SDK errors under threshold).
 * @param {{ engine: string, model: string, apiKeyPresent: boolean }} base
 */
export function getHealthPayload(base) {
  return {
    ok: consecutiveRunErrors < HEALTH_ERROR_THRESHOLD,
    engine: base.engine,
    model: base.model,
    apiKeyPresent: Boolean(base.apiKeyPresent),
    consecutiveRunErrors,
    lastRunStatus,
    lastRunAt,
  }
}

export function getConsecutiveRunErrors() {
  return consecutiveRunErrors
}

/**
 * Classify a run failure for Ask-path recovery (sanitized detail only).
 * @param {string} detailScrubbed
 */
export function classifyRunError(detailScrubbed) {
  const detail = detailScrubbed && String(detailScrubbed).trim() ? String(detailScrubbed).trim() : ''
  const lower = detail.toLowerCase()
  if (
    /usage limit|usage limits|billing|quota|subscription|license|payment required|plan limit|reached its limit/.test(
      lower,
    )
  ) {
    return {
      errorCode: 'cursor_usage_limit',
      errorDetail: detail,
      retryClass: 'licensing_error',
    }
  }
  if (/cannot use this model/i.test(lower)) {
    return {
      errorCode: 'cursor_model_unavailable',
      errorDetail: detail,
      retryClass: 'model_error',
    }
  }
  if (
    /authentication error|not authenticated|unauthorized|log(?:ging)? out and back in/.test(
      lower,
    )
  ) {
    return {
      errorCode: 'cursor_auth_error',
      errorDetail: detail,
      retryClass: 'model_error',
    }
  }
  const opaque =
    !detail ||
    detail.startsWith('requestId=') ||
    /failed with no SDK detail/i.test(detail)
  return {
    errorCode: 'cursor_sdk_run_error',
    errorDetail: detail || '',
    retryClass: opaque ? 'opaque_sdk_failure' : 'sdk_run_error',
  }
}

/**
 * Dispose every remaining session (shutdown).
 */
export async function disposeAllSessions() {
  const ids = [...sessions.keys()]
  for (const id of ids) {
    const entry = normalizeSessionEntry(sessions.get(id))
    if (entry) await retireSession(id, entry)
  }
  sessions.clear()
}
