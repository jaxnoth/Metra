/**
 * ITSM UI mining helpers for Attention ticket cards (Ops presentation only).
 * No client-side MatrixHint synthesis from rule trees or structured objects.
 */

/** Present-case fixture string for Bite 3 verify (mocked host / tests). Not used in production paths. */
export const MATRIX_HINT_FIXTURE =
  'Matched Pharos pattern: review solutions notes before portal FAQ.'

/**
 * Optional-field boundary: only a non-empty string is displayable.
 * Whitespace-only and structured objects are treated as absent (no reconstruction).
 */
export function matrixHintDisplayText(raw: unknown): string | null {
  if (typeof raw !== 'string') return null
  const trimmed = raw.trim()
  return trimmed.length > 0 ? trimmed : null
}

export type CapturedWatchOp =
  | { op: 'scan'; draft: boolean; requestId: string }
  | {
      op: 'preview' | 'confirm'
      ticketId: string
      force: boolean
      requestId: string
    }

export function newWatchRequestId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID()
  }
  return `req-${Date.now()}-${Math.random().toString(36).slice(2)}`
}

/** True when a late response must not apply (missing ids, cleared active, or mismatch). */
export function isStaleWatchResponse(
  activeRequestId: string | null | undefined,
  responseRequestId: string | null | undefined,
): boolean {
  if (!responseRequestId) return true
  if (!activeRequestId) return true
  return activeRequestId !== responseRequestId
}

/**
 * Presentation-only: first non-empty host/TT-authored operator string.
 * Does not truncate, rewrite, or heuristically classify diagnostics - that stays upstream.
 */
export function operatorReasonLine(fields: {
  operatorReason?: string | null
  nextSteps?: string | null
  whyNext?: string | null
  assessGate?: string | null
}): string | null {
  const candidates = [
    fields.operatorReason,
    fields.nextSteps,
    fields.whyNext,
    fields.assessGate,
  ]

  for (const candidate of candidates) {
    if (typeof candidate !== 'string') continue
    const text = candidate.trim()
    if (text) return text
  }

  return null
}
