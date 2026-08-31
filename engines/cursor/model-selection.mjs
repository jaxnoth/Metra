/**
 * Cursor Ask model resolution + SDK availability adaptation.
 * auto-smart (Cursor Router) is team/router keys only; personal SDK keys use concrete ids.
 */

const ROUTER_FALLBACK_BY_TIER = {
  cost: ['default', 'gemini-3.7-flash', 'composer-2.5'],
  balanced: ['default', 'composer-2.5', 'gemini-3.7-flash'],
  intelligence: ['default', 'composer-2.5', 'claude-sonnet-5'],
}

/**
 * @param {string | null | undefined} rawIdOverride
 * @param {string | null | undefined} rawOptOverride
 */
export function resolveModelSelection(rawIdOverride, rawOptOverride) {
  const rawId = String(
    rawIdOverride != null && String(rawIdOverride).trim()
      ? rawIdOverride
      : process.env.METRA_ASK_MODEL || 'composer-2.5',
  ).trim()
  const rawOpt = String(rawOptOverride ?? process.env.METRA_ASK_OPTIMIZE_FOR ?? 'cost')
    .trim()
    .toLowerCase()
  const aliasMap = {
    'auto-cost': 'auto-smart',
    'auto cost': 'auto-smart',
    cost: 'auto-smart',
    auto: 'auto-smart',
    'auto-balance': 'auto-smart',
    'auto balance': 'auto-smart',
    balance: 'auto-smart',
    balanced: 'auto-smart',
    'auto-intelligence': 'auto-smart',
    'auto intelligence': 'auto-smart',
    intelligence: 'auto-smart',
    'composer-2.5-fast': 'composer-2.5',
  }
  const aliasOptimize = {
    'auto-cost': 'cost',
    'auto cost': 'cost',
    cost: 'cost',
    auto: 'cost',
    'auto-balance': 'balanced',
    'auto balance': 'balanced',
    balance: 'balanced',
    balanced: 'balanced',
    'auto-intelligence': 'intelligence',
    'auto intelligence': 'intelligence',
    intelligence: 'intelligence',
  }
  const rawLower = rawId.toLowerCase()
  if (rawLower.startsWith('auto-smart/')) {
    const tier = rawLower.slice('auto-smart/'.length)
    const optimizeFor = ['cost', 'balanced', 'intelligence'].includes(tier) ? tier : 'cost'
    return {
      id: 'auto-smart',
      params: [{ id: 'optimize_for', value: optimizeFor }],
      label: `auto-smart/${optimizeFor}`,
    }
  }
  const id = aliasMap[rawLower] || rawId || 'composer-2.5'
  if (id === 'auto-smart') {
    const fromAlias = aliasOptimize[rawLower]
    const optimizeFor = fromAlias
      ? fromAlias
      : ['cost', 'balanced', 'intelligence'].includes(rawOpt)
        ? rawOpt
        : 'cost'
    return {
      id: 'auto-smart',
      params: [{ id: 'optimize_for', value: optimizeFor }],
      label: `auto-smart/${optimizeFor}`,
    }
  }
  return { id, label: id }
}

/**
 * @param {string[]} availableIds
 * @param {'cost' | 'balanced' | 'intelligence' | string} optimizeFor
 */
export function pickRouterFallback(availableIds, optimizeFor = 'cost') {
  const normalized = (availableIds || [])
    .map((id) => String(id).trim())
    .filter(Boolean)
  const set = new Set(normalized.map((id) => id.toLowerCase()))
  const tier = ['cost', 'balanced', 'intelligence'].includes(optimizeFor) ? optimizeFor : 'cost'
  const order = ROUTER_FALLBACK_BY_TIER[tier] || ROUTER_FALLBACK_BY_TIER.cost
  for (const candidate of order) {
    if (set.has(candidate.toLowerCase())) return candidate
  }
  const concrete = normalized.find((id) => id.toLowerCase() !== 'auto-smart')
  return concrete || 'default'
}

/**
 * Remap unavailable selections when the API key's catalog cannot use them.
 * - auto-smart (Cursor Router) is team/router keys only on many accounts
 * - concrete pins missing from Cursor.models.list() are remapped here
 * - Auth / session failures are NOT model policy (gemini-3.7-flash is valid on personal);
 *   only "cannot use this model" triggers create/run fallback in server.mjs
 * @param {{ id: string, label?: string, params?: { id: string, value: string }[] }} selection
 * @param {string[] | null | undefined} availableIds
 */
export function adaptSelectionForAvailableModels(selection, availableIds) {
  if (!selection || !selection.id) {
    return { selection, adapted: false }
  }
  const normalized = (availableIds || [])
    .map((id) => String(id).trim())
    .filter(Boolean)
  if (normalized.length === 0) {
    return { selection, adapted: false }
  }
  const set = new Set(normalized.map((id) => id.toLowerCase()))
  const optimizeFor =
    selection.params?.find((p) => p.id === 'optimize_for')?.value || 'cost'

  if (selection.id === 'auto-smart') {
    if (set.has('auto-smart')) {
      return { selection, adapted: false }
    }
    const fallbackId = pickRouterFallback(normalized, optimizeFor)
    return {
      selection: {
        id: fallbackId,
        label: `${fallbackId} (auto-smart unavailable)`,
      },
      adapted: true,
      fallbackFrom: selection.label || 'auto-smart',
      fallbackTo: fallbackId,
    }
  }

  // Concrete pin missing from this key's catalog.
  if (!set.has(String(selection.id).toLowerCase())) {
    const withoutPin = normalized.filter(
      (id) => id.toLowerCase() !== String(selection.id).toLowerCase(),
    )
    const fallbackId = pickRouterFallback(withoutPin, optimizeFor)
    if (fallbackId && fallbackId.toLowerCase() !== String(selection.id).toLowerCase()) {
      return {
        selection: {
          id: fallbackId,
          label: `${fallbackId} (${selection.id} unavailable)`,
        },
        adapted: true,
        fallbackFrom: selection.label || selection.id,
        fallbackTo: fallbackId,
      }
    }
  }

  return { selection, adapted: false }
}

/**
 * Pick a concrete fallback excluding a failed model id.
 * @param {string[] | null | undefined} availableIds
 * @param {string | null | undefined} excludeId
 * @param {'cost' | 'balanced' | 'intelligence' | string} optimizeFor
 */
export function pickFallbackExcluding(availableIds, excludeId, optimizeFor = 'cost') {
  const exclude = String(excludeId || '')
    .trim()
    .toLowerCase()
  const filtered = (availableIds || [])
    .map((id) => String(id).trim())
    .filter(Boolean)
    .filter((id) => id.toLowerCase() !== exclude && id.toLowerCase() !== 'auto-smart')
  if (filtered.length === 0) {
    return exclude && exclude !== 'default' ? 'default' : 'composer-2.5'
  }
  return pickRouterFallback(filtered, optimizeFor)
}

/**
 * True when an SDK/create/run error should trigger one model fallback retry.
 * Usage/billing limits and auth/session errors are not model-policy failures -
 * do not relabel a pin (e.g. gemini-3.7-flash) as unavailable for those.
 * @param {string} detail
 */
export function isRetryableModelFailure(detail) {
  const lower = String(detail || '')
    .trim()
    .toLowerCase()
  if (!lower) return false
  if (
    /usage limit|usage limits|billing|quota|subscription|license|payment required|plan limit|reached its limit/.test(
      lower,
    )
  ) {
    return false
  }
  if (
    /authentication error|not authenticated|unauthorized|log(?:ging)? out and back in/.test(
      lower,
    )
  ) {
    return false
  }
  return /cannot use this model|model .* not (available|supported)/.test(lower)
}

export function selectionModelKey(selection) {
  return selection && selection.label ? String(selection.label) : ''
}

export function toSdkModelOpt(selection) {
  if (selection.params && selection.params.length > 0) {
    return { id: selection.id, params: selection.params }
  }
  return { id: selection.id }
}
