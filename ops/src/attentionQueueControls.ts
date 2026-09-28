import type { AttentionItem } from './types'

export type AttentionSourceFilter = 'all' | string
export type AttentionPriorityFilter = 'all' | string
export type AttentionSortMode = 'default' | 'priority' | 'dateAddedNewest' | 'dateAddedOldest'

const PRIORITY_WORD_RANK: Record<string, number> = {
  critical: 0,
  high: 1,
  medium: 2,
  low: 3,
}

/** Lower number = higher urgency. Missing priority sorts last. */
export function attentionPriorityRank(item: AttentionItem): number {
  const blob = `${item.detail || ''} ${item.content || ''} ${item.summary || ''}`
  const num = blob.match(/\bPriority\s+(\d+)\b/i)
  if (num) {
    const n = Number.parseInt(num[1], 10)
    if (Number.isFinite(n)) return Math.max(0, Math.min(99, n))
  }
  const word = blob.match(/\b(Critical|High|Medium|Low)\s+priority\b/i)
  if (word) {
    const rank = PRIORITY_WORD_RANK[word[1].toLowerCase()]
    if (typeof rank === 'number') return rank
  }
  return 100
}

export function attentionPriorityLabel(item: AttentionItem): string | null {
  const blob = `${item.detail || ''} ${item.content || ''} ${item.summary || ''}`
  const num = blob.match(/\bPriority\s+(\d+)\b/i)
  if (num) return `Priority ${num[1]}`
  const word = blob.match(/\b(Critical|High|Medium|Low)\s+priority\b/i)
  if (word) {
    return `${word[1][0].toUpperCase()}${word[1].slice(1).toLowerCase()} priority`
  }
  return null
}

export function attentionAddedMs(item: AttentionItem): number {
  const raw = item.firstSeenAt || item.lastSeenAt || ''
  if (!raw) return 0
  const ms = Date.parse(raw)
  return Number.isFinite(ms) ? ms : 0
}

export function uniqueAttentionKinds(items: AttentionItem[]): string[] {
  const set = new Set<string>()
  for (const item of items) {
    const k = (item.kind || '').trim().toLowerCase()
    if (k) set.add(k)
  }
  return Array.from(set).sort((a, b) => a.localeCompare(b))
}

export function uniqueAttentionPriorityLabels(items: AttentionItem[]): string[] {
  const set = new Set<string>()
  for (const item of items) {
    const label = attentionPriorityLabel(item)
    if (label) set.add(label)
  }
  return Array.from(set).sort((a, b) => {
    const ra = attentionPriorityRank({ detail: a } as AttentionItem)
    const rb = attentionPriorityRank({ detail: b } as AttentionItem)
    return ra - rb || a.localeCompare(b)
  })
}

export function filterAndSortAttentionItems(
  items: AttentionItem[],
  opts: {
    source: AttentionSourceFilter
    priority: AttentionPriorityFilter
    sort: AttentionSortMode
  },
): AttentionItem[] {
  let next = items.slice()
  if (opts.source !== 'all') {
    const want = opts.source.trim().toLowerCase()
    next = next.filter((i) => (i.kind || '').trim().toLowerCase() === want)
  }
  if (opts.priority !== 'all') {
    next = next.filter((i) => attentionPriorityLabel(i) === opts.priority)
  }
  if (opts.sort === 'priority') {
    next = next.slice().sort((a, b) => {
      const d = attentionPriorityRank(a) - attentionPriorityRank(b)
      if (d !== 0) return d
      return attentionAddedMs(b) - attentionAddedMs(a)
    })
  } else if (opts.sort === 'dateAddedNewest') {
    next = next.slice().sort((a, b) => attentionAddedMs(b) - attentionAddedMs(a))
  } else if (opts.sort === 'dateAddedOldest') {
    next = next.slice().sort((a, b) => {
      const am = attentionAddedMs(a)
      const bm = attentionAddedMs(b)
      // Unknown dates last when sorting oldest-first.
      if (am === 0 && bm === 0) return 0
      if (am === 0) return 1
      if (bm === 0) return -1
      return am - bm
    })
  }
  return next
}
