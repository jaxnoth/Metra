/**
 * Mock Cursor SDK for implementer-run.mjs Node tests (no network).
 * Controlled by METRA_IMPLEMENTER_MOCK_MODE:
 *   success | success-completed | text-only | changed-files | empty | auth | licensing | transient | missing-create
 */
function mode() {
  return String(process.env.METRA_IMPLEMENTER_MOCK_MODE || 'success').trim().toLowerCase()
}

export const Agent = {
  async create(_opts) {
    if (mode() === 'missing-create') {
      return {}
    }
    return {
      agentId: 'mock-agent',
      async send(_prompt) {
        const m = mode()
        if (m === 'auth') {
          return {
            async wait() {
              return { status: 'error', error: { message: 'authentication error: invalid API key' } }
            },
          }
        }
        if (m === 'licensing') {
          return {
            async wait() {
              return { status: 'error', error: { message: 'Your team has reached its usage limit / billing quota' } }
            },
          }
        }
        if (m === 'transient') {
          return {
            async wait() {
              return { status: 'error', error: { message: 'connection reset by peer (transient)' } }
            },
          }
        }
        if (m === 'empty') {
          return {
            async wait() {
              return {}
            },
          }
        }
        if (m === 'text-only') {
          return {
            async wait() {
              return { result: 'implemented something (no status field)' }
            },
          }
        }
        if (m === 'changed-files') {
          return {
            async wait() {
              return { changedFiles: ['docs/scout-last-run.md'] }
            },
          }
        }
        if (m === 'success-completed') {
          return {
            async wait() {
              return { status: 'completed', result: 'implemented fixture changes' }
            },
          }
        }
        return {
          async wait() {
            return { status: 'ok', result: 'implemented fixture changes' }
          },
        }
      },
    }
  },
}
