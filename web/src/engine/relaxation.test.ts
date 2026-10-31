import { describe, expect, it } from 'vitest'
import { PendingRelaxation, PendingRelaxationQueue, type PendingChange, type RelaxationTarget } from './relaxation'
import { date, limitRule, SECOND } from './testSupport'

const start = date(2026, 11, 2, 10)
const disable: PendingChange = { type: 'disableRule', ruleId: 'rule-a' }
const after = (seconds: number) => start + seconds * SECOND

describe('PendingRelaxation', () => {
  const request = PendingRelaxation.make('id', disable, start)

  it('testDurations', () => {
    expect(PendingRelaxation.cooldownDuration).toBe(600 * SECOND)
    expect(PendingRelaxation.confirmationWindow).toBe(1800 * SECOND)
  })

  it('testPhases', () => {
    expect(PendingRelaxation.phase(request, start)).toBe('waiting')
    expect(PendingRelaxation.phase(request, after(599))).toBe('waiting')
    expect(PendingRelaxation.phase(request, after(600))).toBe('confirmable')
    expect(PendingRelaxation.phase(request, after(2399))).toBe('confirmable')
    expect(PendingRelaxation.phase(request, after(2400))).toBe('expired')
  })

  it('testCanConfirmOnlyInsideWindow', () => {
    expect(PendingRelaxation.canConfirm(request, start)).toBe(false)
    expect(PendingRelaxation.canConfirm(request, after(600))).toBe(true)
    expect(PendingRelaxation.canConfirm(request, after(2400))).toBe(false)
  })

  it('testClockMovedBeforeRequestStaysWaiting', () => {
    expect(PendingRelaxation.phase(request, after(-3600))).toBe('waiting')
  })

  it('testRemaining', () => {
    expect(PendingRelaxation.remaining(request, after(100))).toBe(500 * SECOND)
    expect(PendingRelaxation.remaining(request, after(700))).toBe(0)
    expect(PendingRelaxation.confirmationRemaining(request, after(700))).toBe(1700 * SECOND)
    expect(PendingRelaxation.confirmationRemaining(request, after(9_999))).toBe(0)
  })

  it('testTargets', () => {
    const rule = limitRule(30, { id: 'rule-a' })
    const cases: [PendingChange, RelaxationTarget][] = [
      [disable, { type: 'rule', ruleId: 'rule-a' }],
      [{ type: 'deleteRule', ruleId: 'rule-a' }, { type: 'rule', ruleId: 'rule-a' }],
      [{ type: 'editRule', rule }, { type: 'rule', ruleId: 'rule-a' }],
      [{ type: 'resetPIN' }, { type: 'pinReset' }],
    ]
    for (const [change, target] of cases) {
      expect(PendingRelaxation.target(PendingRelaxation.make('id', change, start))).toEqual(target)
    }
  })

  it('testCodableRoundTrip', () => {
    const rule = limitRule(60)
    const changes: PendingChange[] = [
      { type: 'disableRule', ruleId: rule.id },
      { type: 'deleteRule', ruleId: rule.id },
      { type: 'editRule', rule },
      { type: 'resetPIN' },
    ]
    for (const change of changes) {
      const value = PendingRelaxation.make('id', change, start)
      expect(JSON.parse(JSON.stringify(value))).toEqual(value)
    }
  })

  it('testResetPINWaitsOneDayWithTheSameWindow', () => {
    expect(PendingRelaxation.pinResetCooldownDuration).toBe(86_400 * SECOND)

    const reset = PendingRelaxation.make('id', { type: 'resetPIN' }, start)
    expect(reset.cooldown.duration).toBe(86_400 * SECOND)
    expect(PendingRelaxation.remaining(reset, start)).toBe(86_400 * SECOND)
    expect(PendingRelaxation.expiresAt(reset)).toBe(start + (86_400 * SECOND) + PendingRelaxation.confirmationWindow)

    expect(PendingRelaxation.phase(reset, after(600))).toBe('waiting')
    expect(PendingRelaxation.phase(reset, after(86_399))).toBe('waiting')
    expect(PendingRelaxation.phase(reset, after(86_400))).toBe('confirmable')
    expect(PendingRelaxation.phase(reset, after(88_199))).toBe('confirmable')
    expect(PendingRelaxation.phase(reset, after(88_200))).toBe('expired')
  })

  it('testOnlyResetPINSkipsAuthentication', () => {
    const authenticated: PendingChange[] = [
      { type: 'disableRule', ruleId: 'a' },
      { type: 'deleteRule', ruleId: 'a' },
      { type: 'editRule', rule: limitRule(30) },
    ]
    for (const change of authenticated) {
      expect(PendingRelaxation.requiresAuthentication(PendingRelaxation.make('id', change, start)), change.type).toBe(true)
    }
    expect(PendingRelaxation.requiresAuthentication(PendingRelaxation.make('id', { type: 'resetPIN' }, start))).toBe(false)
  })
})

describe('PendingRelaxationQueue', () => {
  const Queue = PendingRelaxationQueue
  const ruleTarget = (ruleId: string): RelaxationTarget => ({ type: 'rule', ruleId })

  it('testEnqueueAndLookup', () => {
    const { queue, request } = Queue.enqueue(Queue.empty, disable, start, 'id-1')
    expect(Queue.pending(queue, ruleTarget('rule-a'))).toEqual(request)
    expect(Queue.pending(queue, { type: 'pinReset' })).toBeNull()
    expect(Queue.request(queue, 'id-1')).toEqual(request)
    expect(Queue.request(queue, 'altro')).toBeNull()
  })

  it('testSecondRequestOnSameTargetKeepsTheFirst', () => {
    const first = Queue.enqueue(Queue.empty, disable, start, 'id-1')
    // Il timer non riparte e la richiesta non cambia.
    const second = Queue.enqueue(first.queue, { type: 'deleteRule', ruleId: 'rule-a' }, after(300), 'id-2')
    expect(second.request).toEqual(first.request)
    expect(second.queue.items).toEqual([first.request])
  })

  it('testDifferentTargetsCoexist', () => {
    let queue = Queue.empty
    queue = Queue.enqueue(queue, { type: 'disableRule', ruleId: 'a' }, start, '1').queue
    queue = Queue.enqueue(queue, { type: 'disableRule', ruleId: 'b' }, start, '2').queue
    queue = Queue.enqueue(queue, { type: 'resetPIN' }, start, '3').queue
    expect(queue.items.length).toBe(3)
  })

  it('testResetPINDoesNotOccupyOtherTargets', () => {
    const reset = Queue.enqueue(Queue.empty, { type: 'resetPIN' }, start, '1')
    // Durante l'attesa del reset tutto il resto funziona normalmente.
    expect(Queue.pending(reset.queue, ruleTarget('rule-a'))).toBeNull()
    const both = Queue.enqueue(reset.queue, disable, start, '2')
    expect(both.queue.items).toEqual([reset.request, both.request])
  })

  it('testRepeatedResetPINKeepsTheTimer', () => {
    const first = Queue.enqueue(Queue.empty, { type: 'resetPIN' }, start, '1')
    expect(Queue.enqueue(first.queue, { type: 'resetPIN' }, after(3600), '2').request).toEqual(first.request)
  })

  it('testResetPINExpiresLaterThanOtherRequests', () => {
    const reset = Queue.enqueue(Queue.empty, { type: 'resetPIN' }, start, '1')
    const both = Queue.enqueue(reset.queue, disable, start, '2')
    const { queue, expired } = Queue.removeExpired(both.queue, after(2400))
    expect(expired).toEqual([both.request])
    expect(queue.items).toEqual([reset.request])
  })

  it('testRemove', () => {
    const first = Queue.enqueue(Queue.empty, disable, start, '1')
    const removed = Queue.remove(first.queue, '1')
    expect(removed.items).toEqual([])
    // Dopo l'annullamento si può chiedere di nuovo, con un'attesa nuova.
    const again = Queue.enqueue(removed, disable, after(60), '2')
    expect(again.request.cooldown.requestedAt).toBe(after(60))
  })

  it('testRemoveExpired', () => {
    const old = Queue.enqueue(Queue.empty, disable, start, '1')
    const recent = Queue.enqueue(old.queue, { type: 'disableRule', ruleId: 'b' }, after(1000), '2')
    const { queue, expired } = Queue.removeExpired(recent.queue, after(2400))
    expect(expired).toEqual([old.request])
    expect(queue.items).toEqual([recent.request])
  })

  it('testCancelPINResetRemovesOnlyTheReset', () => {
    let queue = Queue.empty
    const first = Queue.enqueue(queue, disable, start, '1')
    const reset = Queue.enqueue(first.queue, { type: 'resetPIN' }, start, '2')
    const last = Queue.enqueue(reset.queue, { type: 'disableRule', ruleId: 'b' }, start, '3')
    queue = last.queue

    const result = Queue.cancelPINReset(queue)
    expect(result.cancelled).toEqual(reset.request)
    expect(Queue.pending(result.queue, { type: 'pinReset' })).toBeNull()
    expect(result.queue.items).toEqual([first.request, last.request])
  })

  it('testCancelPINResetWithoutResetChangesNothing', () => {
    const { queue, request } = Queue.enqueue(Queue.empty, disable, start, '1')
    const result = Queue.cancelPINReset(queue)
    expect(result.cancelled).toBeNull()
    expect(result.queue.items).toEqual([request])
  })

  it('testCancelPINResetAlsoWorksInsideTheConfirmationWindow', () => {
    const { queue, request } = Queue.enqueue(Queue.empty, { type: 'resetPIN' }, start, '1')
    expect(PendingRelaxation.canConfirm(request, after(86_400))).toBe(true)
    const result = Queue.cancelPINReset(queue)
    expect(result.cancelled).toEqual(request)
    expect(result.queue.items).toEqual([])
  })

  it('testResetRequestedAfterCancelWaitsAgain', () => {
    const first = Queue.enqueue(Queue.empty, { type: 'resetPIN' }, start, '1')
    const { queue } = Queue.cancelPINReset(first.queue)
    const later = after(3600)
    const again = Queue.enqueue(queue, { type: 'resetPIN' }, later, '2')
    expect(PendingRelaxation.remaining(again.request, later)).toBe(86_400 * SECOND)
  })

  it('testEnqueueDoesNotChangeTheOriginalQueue', () => {
    const queue = Queue.empty
    Queue.enqueue(queue, disable, start, '1')
    expect(queue.items).toEqual([])
  })
})
