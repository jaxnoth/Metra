/** Fail-closed Attention list density (Settings + render + putPreferences). */
export const DEFAULT_ATTENTION_VISIBLE_COUNT = 1

export function normalizeAttentionVisibleCount(value: unknown): number {
  const parsed = Number(value)
  if (!Number.isFinite(parsed)) return DEFAULT_ATTENTION_VISIBLE_COUNT
  return Math.max(1, Math.min(10, Math.trunc(parsed)))
}
