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
