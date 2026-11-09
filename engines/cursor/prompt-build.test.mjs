/**
 * Node tests for Ask prompt journal-inclusion gate.
 * Run: node --test engines/cursor/prompt-build.test.mjs
 */
import assert from 'node:assert/strict'
import test from 'node:test'
import { shouldIncludeJournalContinuity } from './prompt-build.mjs'

test('omits journal when agent has history even if hasJournalContext is true', () => {
  const ctx = {
    continuity: {
      hasJournalContext: true,
      sessionSummary: '- Turn 1: hello',
      recentTurns: [{ turnIndex: 2, prompt: 'x', message: 'y' }],
    },
  }
  assert.equal(shouldIncludeJournalContinuity(ctx, { includeJournalContinuity: false }), false)
})

test('includes journal on new session / cache miss', () => {
  const ctx = {
    continuity: { hasJournalContext: true, sessionSummary: '- Turn 1: hello' },
  }
  assert.equal(shouldIncludeJournalContinuity(ctx, { includeJournalContinuity: true }), true)
})

test('includes journal on forceContinuity', () => {
  assert.equal(
    shouldIncludeJournalContinuity({ forceContinuity: true, continuity: { hasJournalContext: true } }, {}),
    true,
  )
})

test('includes journal on explicit recall object', () => {
  assert.equal(
    shouldIncludeJournalContinuity({ recall: 'prior disk alert', continuity: { hasJournalContext: true } }, {}),
    true,
  )
})

test('hasJournalContext alone never includes journal', () => {
  assert.equal(
    shouldIncludeJournalContinuity({ continuity: { hasJournalContext: true } }, {}),
    false,
  )
})
