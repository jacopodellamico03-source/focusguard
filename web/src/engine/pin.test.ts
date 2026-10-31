import { describe, expect, it } from 'vitest'
import { ConstantTime, PINAttemptPolicy, PINPolicy, type PINValidationError } from './pin'
import { date, SECOND } from './testSupport'

describe('PINPolicy', () => {
  it('testAcceptsValidPINs', () => {
    for (const pin of ['483920', '2749163', '90317465']) {
      expect(PINPolicy.validate(pin), pin).toEqual([])
    }
  })

  it('testLengthBoundaries', () => {
    expect(PINPolicy.validate('48392')).toEqual([{ type: 'wrongLength', count: 5 }])
    expect(PINPolicy.validate('483920')).toEqual([])
    expect(PINPolicy.validate('48392017')).toEqual([])
    expect(PINPolicy.validate('483920175')).toEqual([{ type: 'wrongLength', count: 9 }])
    expect(PINPolicy.validate('')).toEqual([{ type: 'wrongLength', count: 0 }])
  })

  it('testOnlyASCIIDigits', () => {
    expect(PINPolicy.validate('48392a')).toEqual([{ type: 'notDigits' }])
    expect(PINPolicy.validate('483 20')).toEqual([{ type: 'notDigits' }])
    // Cifre arabo-indiane: non sono cifre ASCII.
    expect(PINPolicy.validate('٤٨٣٩٢٠')).toEqual([{ type: 'notDigits' }])
  })

  it('testRejectsRepeatedDigits', () => {
    for (const pin of ['000000', '111111', '99999999']) {
      expect(PINPolicy.validate(pin), pin).toEqual([{ type: 'trivial' }])
    }
  })

  it('testRejectsSequences', () => {
    for (const pin of ['123456', '654321', '12345678', '87654321', '012345', '890123', '210987']) {
      expect(PINPolicy.validate(pin), pin).toEqual([{ type: 'trivial' }])
    }
  })

  it('testRejectsRepeatedPatterns', () => {
    for (const pin of ['121212', '123123', '12341234', '909090']) {
      expect(PINPolicy.validate(pin), pin).toEqual([{ type: 'trivial' }])
    }
  })

  it('testAlmostTrivialIsAccepted', () => {
    expect(PINPolicy.validate('123457')).toEqual([])
    expect(PINPolicy.validate('121213')).toEqual([])
    expect(PINPolicy.validate('1212123')).toEqual([])
  })

  it('testMessagesAreItalian', () => {
    const describeError = (error: PINValidationError) => PINPolicy.describe(error)
    expect(describeError({ type: 'notDigits' })).toContain('cifre')
    expect(describeError({ type: 'wrongLength', count: 3 })).toContain('6')
    expect(describeError({ type: 'trivial' })).not.toBe('')
  })
})

describe('ConstantTime', () => {
  const bytes = (...values: number[]) => Uint8Array.from(values)

  it('testEquals', () => {
    expect(ConstantTime.equals(bytes(1, 2, 3), bytes(1, 2, 3))).toBe(true)
    expect(ConstantTime.equals(bytes(), bytes())).toBe(true)
    expect(ConstantTime.equals(bytes(1, 2, 3), bytes(1, 2, 4))).toBe(false)
    expect(ConstantTime.equals(bytes(0, 2, 3), bytes(1, 2, 3))).toBe(false)
    expect(ConstantTime.equals(bytes(1, 2, 3), bytes(1, 2))).toBe(false)
  })

  it('testSlicesWithNonZeroStartIndex', () => {
    const full = bytes(9, 1, 2, 3)
    expect(ConstantTime.equals(full.subarray(1), bytes(1, 2, 3))).toBe(true)
  })
})

describe('PINAttemptPolicy', () => {
  const start = date(2026, 11, 2, 10)

  /** Stato dopo `count` errori, l'ultimo dei quali a `start` (i precedenti a blocco già finito). */
  const afterFailures = (count: number): PINAttemptPolicy =>
    PINAttemptPolicy.registerFailure({ failedAttempts: count - 1, lockedUntil: null }, start)

  it('testFailuresInARowAtTheSameInstantStopAtTheLock', () => {
    let policy = PINAttemptPolicy.initial
    for (let i = 0; i < 8; i++) policy = PINAttemptPolicy.registerFailure(policy, start)
    expect(policy.failedAttempts).toBe(5)
    expect(PINAttemptPolicy.remainingLockout(policy, start)).toBe(60 * SECOND)
  })

  it('testNoLockBeforeFiveFailures', () => {
    const policy = afterFailures(4)
    expect(policy.failedAttempts).toBe(4)
    expect(PINAttemptPolicy.isLocked(policy, start)).toBe(false)
    expect(PINAttemptPolicy.remainingLockout(policy, start)).toBe(0)
  })

  it('testFifthFailureLocksForOneMinute', () => {
    const policy = afterFailures(5)
    expect(PINAttemptPolicy.remainingLockout(policy, start)).toBe(60 * SECOND)
    expect(PINAttemptPolicy.isLocked(policy, start + 59 * SECOND)).toBe(true)
    expect(PINAttemptPolicy.isLocked(policy, start + 60 * SECOND)).toBe(false)
  })

  it('testLockoutDoublesUpToOneHour', () => {
    const expected: [number, number][] = [
      [5, 60], [6, 120], [7, 240], [8, 480], [9, 960], [10, 1920], [11, 3600], [12, 3600],
    ]
    for (const [failures, duration] of expected) {
      expect(PINAttemptPolicy.remainingLockout(afterFailures(failures), start), `${failures} errori`).toBe(duration * SECOND)
    }
  })

  it('testHugeFailureCountDoesNotOverflow', () => {
    const updated = PINAttemptPolicy.registerFailure({ failedAttempts: 10_000, lockedUntil: null }, start)
    expect(PINAttemptPolicy.remainingLockout(updated, start)).toBe(3600 * SECOND)
  })

  it('testFailureDuringLockoutIsIgnored', () => {
    const policy = PINAttemptPolicy.registerFailure(afterFailures(5), start + 30 * SECOND)
    expect(policy.failedAttempts).toBe(5)
    expect(policy.lockedUntil).toBe(start + 60 * SECOND)
  })

  it('testFailureAfterLockoutDoubles', () => {
    const later = start + 60 * SECOND
    const policy = PINAttemptPolicy.registerFailure(afterFailures(5), later)
    expect(policy.failedAttempts).toBe(6)
    expect(PINAttemptPolicy.remainingLockout(policy, later)).toBe(120 * SECOND)
  })

  it('testSuccessResets', () => {
    const policy = PINAttemptPolicy.registerSuccess()
    expect(policy).toEqual(PINAttemptPolicy.initial)
    expect(PINAttemptPolicy.isLocked(policy, start)).toBe(false)
  })

  it('testCodableRoundTrip', () => {
    const policy = afterFailures(6)
    const decoded: PINAttemptPolicy = JSON.parse(JSON.stringify(policy))
    expect(decoded).toEqual(policy)
    expect(PINAttemptPolicy.isLocked(decoded, start)).toBe(true)
  })
})
