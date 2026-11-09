/**
 * Node tests for Ask prompt journal-inclusion gate.
 * Run: node --test engines/cursor/prompt-build.test.mjs
 */
import assert from 'node:assert/strict'
import test from 'node:test'
import {
  resolveProjectBriefForPrompt,
  shouldIncludeIdentity,
  shouldIncludeJournalContinuity,
} from './prompt-build.mjs'

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

test('project brief slot is included when present and capped at 1500', () => {
  const long = 'x'.repeat(1600)
  const resolved = resolveProjectBriefForPrompt({
    projectBrief: long,
    projectBriefMeta: { project: 'Metra', staleness: 'fresh', derived: true },
  })
  assert.equal(resolved.charCount, 1500)
  assert.equal(resolved.staleness, 'fresh')
  assert.equal(resolved.text.length, 1500)
})

test('project brief resolves from continuity nest', () => {
  const resolved = resolveProjectBriefForPrompt({
    continuity: {
      projectBrief: 'staleness: fresh\n- (thread) FRIDAY reboot',
      projectBriefMeta: { staleness: 'likely_stale' },
    },
  })
  assert.match(resolved.text, /FRIDAY reboot/)
  assert.equal(resolved.staleness, 'likely_stale')
})

test('identity included on new session', () => {
  assert.equal(
    shouldIncludeIdentity({
      newSession: true,
      identityPrefix: 'You are Metra.',
      identityHash: 'abc',
      lastIdentityHash: 'abc',
    }),
    true,
  )
})

test('reused session with same hash omits identity', () => {
  assert.equal(
    shouldIncludeIdentity({
      newSession: false,
      identityPrefix: 'You are Metra.',
      identityHash: 'abc',
      lastIdentityHash: 'abc',
    }),
    false,
  )
})

test('hash change resends identity on reused session', () => {
  assert.equal(
    shouldIncludeIdentity({
      newSession: false,
      identityPrefix: 'You are Metra.',
      identityHash: 'def',
      lastIdentityHash: 'abc',
    }),
    true,
  )
})

test('empty identity prefix never includes', () => {
  assert.equal(
    shouldIncludeIdentity({
      newSession: true,
      identityPrefix: '',
      identityHash: 'abc',
    }),
    false,
  )
})
