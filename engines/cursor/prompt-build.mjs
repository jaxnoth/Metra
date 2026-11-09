/**
 * Ask prompt builders for the Cursor sidecar (testable without SDK).
 */

/**
 * Whether to inject Session Journal continuity into the agent prompt.
 * Sidecar owns this: only on new session (cache miss / restart / eviction),
 * forceContinuity, or explicit recall payload - not merely because PowerShell set
 * continuity.hasJournalContext (agent already has history).
 */
export function shouldIncludeJournalContinuity(context, options = {}) {
  return (
    Boolean(options.includeJournalContinuity) ||
    Boolean(context?.forceContinuity) ||
    Boolean(context?.recall) ||
    Boolean(context?.continuity?.recall)
  )
}

/**
 * Whether to prepend Conversation Identity to this Cursor agent send.
 * Once per agent (newSession), or again when IdentityHash changes (persona edit / posture packs).
 * Empty identityPrefix never includes.
 */
export function shouldIncludeIdentity(options = {}) {
  const prefix = options.identityPrefix != null ? String(options.identityPrefix).trim() : ''
  if (!prefix) return false
  if (Boolean(options.newSession)) return true
  const hash = options.identityHash != null ? String(options.identityHash).trim() : ''
  if (!hash) return false
  const last = options.lastIdentityHash != null ? String(options.lastIdentityHash).trim() : ''
  return hash !== last
}

/**
 * Derived MDR project brief Ask slot (max 1500). Independent of journal inclusion.
 */
export function resolveProjectBriefForPrompt(context, maxChars = 1500) {
  let text = context?.projectBrief || context?.continuity?.projectBrief
    ? String(context.projectBrief || context.continuity.projectBrief).trim()
    : ''
  if (text.length > maxChars) text = text.slice(0, maxChars)
  const meta = context?.projectBriefMeta || context?.continuity?.projectBriefMeta || null
  const staleness = meta?.staleness ? String(meta.staleness) : ''
  return { text, staleness, charCount: text.length }
}
