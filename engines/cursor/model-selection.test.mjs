/**
 * Node tests for Cursor Ask model selection (no SDK / no network).
 * Run: node --test engines/cursor/model-selection.test.mjs
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  adaptSelectionForAvailableModels,
  isRetryableModelFailure,
  pickFallbackExcluding,
  pickRouterFallback,
  resolveModelSelection,
} from './model-selection.mjs'

test('resolveModelSelection maps auto-cost to auto-smart/cost', () => {
  const s = resolveModelSelection('auto-cost', 'cost')
  assert.equal(s.id, 'auto-smart')
  assert.equal(s.label, 'auto-smart/cost')
  assert.equal(s.params[0].value, 'cost')
})

test('adaptSelectionForAvailableModels keeps auto-smart when listed', () => {
  const selection = resolveModelSelection('auto-smart/cost')
  const out = adaptSelectionForAvailableModels(selection, ['auto-smart', 'default'])
  assert.equal(out.adapted, false)
  assert.equal(out.selection.id, 'auto-smart')
})

test('adaptSelectionForAvailableModels falls back when auto-smart missing', () => {
  const selection = resolveModelSelection('auto-smart/cost')
  const available = [
    'default',
    'grok-4.6',
    'gemini-3.7-flash',
    'composer-2.5',
  ]
  const out = adaptSelectionForAvailableModels(selection, available)
  assert.equal(out.adapted, true)
  assert.equal(out.selection.id, 'default')
  assert.match(out.selection.label, /auto-smart unavailable/)
})

test('adaptSelectionForAvailableModels falls back when concrete pin missing', () => {
  const selection = resolveModelSelection('gemini-3.7-flash')
  const out = adaptSelectionForAvailableModels(selection, [
    'default',
    'composer-2.5',
  ])
  assert.equal(out.adapted, true)
  assert.equal(out.selection.id, 'default')
  assert.match(out.selection.label, /gemini-3\.7-flash unavailable/)
})

test('adaptSelectionForAvailableModels keeps listed concrete pin', () => {
  const selection = resolveModelSelection('gemini-3.7-flash')
  const out = adaptSelectionForAvailableModels(selection, [
    'gemini-3.7-flash',
    'composer-2.5',
  ])
  assert.equal(out.adapted, false)
  assert.equal(out.selection.id, 'gemini-3.7-flash')
})

test('pickRouterFallback prefers gemini for cost tier when default missing', () => {
  const id = pickRouterFallback(['gemini-3.7-flash', 'composer-2.5'], 'cost')
  assert.equal(id, 'gemini-3.7-flash')
})

test('pickRouterFallback uses composer for balanced tier', () => {
  const id = pickRouterFallback(['gemini-3.7-flash', 'composer-2.5'], 'balanced')
  assert.equal(id, 'composer-2.5')
})

test('pickFallbackExcluding skips failed model', () => {
  const id = pickFallbackExcluding(
    ['gemini-3.7-flash', 'composer-2.5', 'default'],
    'gemini-3.7-flash',
    'cost',
  )
  assert.equal(id, 'default')
})

test('isRetryableModelFailure treats model denials as retryable, not auth', () => {
  assert.equal(
    isRetryableModelFailure(
      'Authentication error If you are logged in, try logging out and back in.',
    ),
    false,
  )
  assert.equal(isRetryableModelFailure('Cannot use this model: gemini-3.7-flash'), true)
  assert.equal(
    isRetryableModelFailure('Your team has reached its usage limit'),
    false,
  )
})
