import { describe, expect, it } from 'vitest'
import { AccessDecision, MAX_PASS_MINUTES, PASS_OPTIONS } from './accessDecision'
import type { Rule } from './rule'
import { date, limitRule, MINUTE, scheduleRule, SECOND, t } from './testSupport'
import { Weekday } from './time'
import { UsageLedger, type PassGrant } from './usageLedger'

const { decide } = AccessDecision
const noon = date(2026, 11, 2, 12) // lunedì
const none = UsageLedger.empty
const ledger = (...grants: PassGrant[]): UsageLedger => ({ grants })
/** `minutes` già consumati oggi prima di mezzogiorno. */
const used = (minutes: number, app: PassGrant['app'] = 'instagram'): UsageLedger =>
  ledger({ app, grantedAt: date(2026, 11, 2, 9), minutes })

function blockedUntil(decision: AccessDecision): number | null {
  if (decision.kind !== 'blocked') throw new Error('atteso blocked')
  return decision.until
}

function passes(decision: AccessDecision): readonly number[] {
  if (decision.kind !== 'allowed') throw new Error('atteso allowed')
  return decision.passes
}

function minutesLeft(decision: AccessDecision): number | null {
  if (decision.kind !== 'allowed') throw new Error('atteso allowed')
  return decision.minutesLeftToday
}

describe('nessuna configurazione', () => {
  it('testMissingRulesAreBlockedWithoutPasses', () => {
    expect(decide('instagram', noon, null, none)).toEqual({ kind: 'blocked', reason: { type: 'notConfigured' }, until: null })
  })

  it('testMissingUsageIsBlockedToo', () => {
    // Senza registro il budget ripartirebbe da zero.
    expect(decide('instagram', noon, [limitRule(30)], null)).toEqual({ kind: 'blocked', reason: { type: 'notConfigured' }, until: null })
  })

  it('testEmptyRulesAreAConfigurationNotAMissingOne', () => {
    expect(decide('instagram', noon, [], none)).toEqual({ kind: 'allowed', minutesLeftToday: null, passes: [5, 10, 15] })
  })
})

describe('blocco a orario', () => {
  it('testBlockedInsideTheWindow', () => {
    const rule = scheduleRule(t(9), t(13), { id: 'orario' })
    expect(decide('instagram', noon, [rule], none)).toEqual({
      kind: 'blocked',
      reason: { type: 'schedule', ruleId: 'orario', ruleName: 'Notte' },
      until: date(2026, 11, 2, 13),
    })
  })

  it('testOvernightEndsTheNextMorning', () => {
    const rule = scheduleRule(t(22), t(7))
    expect(blockedUntil(decide('instagram', date(2026, 11, 2, 23, 30), [rule], none))).toBe(date(2026, 11, 3, 7))
    expect(blockedUntil(decide('instagram', date(2026, 11, 3, 6, 30), [rule], none))).toBe(date(2026, 11, 3, 7))
  })

  it('testEndIsNotTheCurrentMinute', () => {
    const rule = scheduleRule(t(9), t(13))
    expect(blockedUntil(decide('instagram', date(2026, 11, 2, 12, 59) + 30 * SECOND, [rule], none))).toBe(date(2026, 11, 2, 13))
  })

  it('testOtherAppIsNotBlocked', () => {
    expect(decide('tiktok', noon, [scheduleRule(t(9), t(13))], none).kind).toBe('allowed')
  })

  it('testDisabledRuleIsIgnored', () => {
    expect(decide('instagram', noon, [scheduleRule(t(9), t(13), { enabled: false })], none).kind).toBe('allowed')
  })

  it('testInvalidRuleIsIgnored', () => {
    expect(decide('instagram', noon, [scheduleRule(t(9), t(13), { weekdays: [] })], none).kind).toBe('allowed')
  })

  it('testOtherWeekdayIsNotBlocked', () => {
    expect(decide('instagram', noon, [scheduleRule(t(9), t(13), { weekdays: [Weekday.sunday] })], none).kind).toBe('allowed')
  })
})

describe('limite giornaliero', () => {
  it('testExhaustedLimitBlocksUntilMidnight', () => {
    const rule = limitRule(30, { id: 'limite' })
    expect(decide('instagram', noon, [rule], used(30))).toEqual({
      kind: 'blocked',
      reason: { type: 'limit', ruleId: 'limite', ruleName: 'Social' },
      until: date(2026, 11, 3, 0),
    })
  })

  it('testMinutesLeft', () => {
    expect(minutesLeft(decide('instagram', noon, [limitRule(30)], used(10)))).toBe(20)
    expect(minutesLeft(decide('instagram', noon, [limitRule(30)], none))).toBe(30)
  })

  it('testNoLimitMeansNoCount', () => {
    expect(minutesLeft(decide('instagram', noon, [scheduleRule(t(22), t(7))], none))).toBeNull()
  })

  it('testLimitOnAnotherWeekdayDoesNotCount', () => {
    const rule = limitRule(30, { weekdays: [Weekday.sunday] })
    expect(minutesLeft(decide('instagram', noon, [rule], used(30)))).toBeNull()
  })

  it('testDisabledLimitIsIgnored', () => {
    expect(minutesLeft(decide('instagram', noon, [limitRule(30, { enabled: false })], used(30)))).toBeNull()
  })

  it('testBudgetPerAppIsIndependent', () => {
    const rules = [limitRule(30, { apps: ['instagram'] }), limitRule(30, { apps: ['tiktok'] })]
    expect(decide('instagram', noon, rules, used(30, 'instagram')).kind).toBe('blocked')
    expect(minutesLeft(decide('tiktok', noon, rules, used(30, 'instagram')))).toBe(30)
  })

  it('testSharedBudgetCountsEveryApp', () => {
    const rules = [limitRule(30, { apps: ['instagram', 'tiktok'] })]
    const usage = ledger(
      { app: 'instagram', grantedAt: date(2026, 11, 2, 9), minutes: 15 },
      { app: 'tiktok', grantedAt: date(2026, 11, 2, 10), minutes: 10 },
    )
    expect(minutesLeft(decide('instagram', noon, rules, usage))).toBe(5)
    expect(minutesLeft(decide('tiktok', noon, rules, usage))).toBe(5)
    expect(decide('youtube', noon, rules, usage).kind).toBe('allowed')
  })

  it('testSharedBudgetExhaustedBlocksEveryApp', () => {
    const rules = [limitRule(30, { apps: ['instagram', 'tiktok'] })]
    expect(decide('instagram', noon, rules, used(30, 'tiktok')).kind).toBe('blocked')
    expect(decide('tiktok', noon, rules, used(30, 'tiktok')).kind).toBe('blocked')
  })

  it('testTightestLimitWins', () => {
    const rules = [limitRule(60), limitRule(20, { apps: ['instagram', 'tiktok'] })]
    expect(minutesLeft(decide('instagram', noon, rules, used(5)))).toBe(15)
  })

  it('testResetsAtLocalMidnight', () => {
    const usage = ledger({ app: 'instagram', grantedAt: date(2026, 11, 2, 22), minutes: 30 })
    expect(decide('instagram', date(2026, 11, 2, 23, 59), [limitRule(30)], usage).kind).toBe('blocked')
    expect(minutesLeft(decide('instagram', date(2026, 11, 3, 0, 0), [limitRule(30)], usage))).toBe(30)
  })

  it('testPassAcrossMidnightChargesTomorrow', () => {
    const usage = ledger({ app: 'instagram', grantedAt: date(2026, 11, 2, 23, 55), minutes: 15 })
    expect(minutesLeft(decide('instagram', date(2026, 11, 2, 23, 58), [limitRule(30)], usage))).toBe(25)
    expect(minutesLeft(decide('instagram', date(2026, 11, 3, 0, 5), [limitRule(30)], usage))).toBe(20)
  })

  it('testLessThanAMinuteLeftIsExhausted', () => {
    // 90 secondi caricati su oggi con un pass a cavallo della mezzanotte: resta mezzo minuto di 2.
    const usage = ledger({ app: 'instagram', grantedAt: date(2026, 11, 2, 23, 58) + 30 * SECOND, minutes: 15 })
    expect(decide('instagram', date(2026, 11, 2, 23, 59), [limitRule(2)], usage).kind).toBe('blocked')
  })
})

describe('pass offerti', () => {
  it('testFullBudgetOffersEveryPass', () => {
    expect(passes(decide('instagram', noon, [limitRule(30)], none))).toEqual([5, 10, 15])
    expect(passes(decide('instagram', noon, [limitRule(30)], used(15)))).toEqual([5, 10, 15])
  })

  it('testPassesNeverExceedTheBudget', () => {
    expect(passes(decide('instagram', noon, [limitRule(30)], used(18)))).toEqual([5, 10])
    expect(passes(decide('instagram', noon, [limitRule(30)], used(25)))).toEqual([5])
  })

  it('testLessThanFiveMinutesOffersTheExactRest', () => {
    expect(passes(decide('instagram', noon, [limitRule(30)], used(27)))).toEqual([3])
    expect(passes(decide('instagram', noon, [limitRule(30)], used(29)))).toEqual([1])
  })

  it('testPassesEndBeforeTheNextBlock', () => {
    // Alle 21:48 il blocco delle 22:00 è tra 12 minuti: un pass da 15 lo scavalcherebbe.
    const rule = scheduleRule(t(22), t(7))
    expect(passes(decide('instagram', date(2026, 11, 2, 21, 48), [rule], none))).toEqual([5, 10])
    expect(passes(decide('instagram', date(2026, 11, 2, 21, 45), [rule], none))).toEqual([5, 10, 15])
    expect(passes(decide('instagram', date(2026, 11, 2, 21, 57), [rule], none))).toEqual([3])
  })

  it('testUnderAMinuteBeforeABlockOffersNothing', () => {
    const rule = scheduleRule(t(22), t(7))
    const decision = decide('instagram', date(2026, 11, 2, 21, 59) + 30 * SECOND, [rule], none)
    expect(decision.kind).toBe('allowed')
    expect(passes(decision)).toEqual([])
  })

  it('testBudgetAndNextBlockBothLimit', () => {
    const rules = [scheduleRule(t(22), t(7)), limitRule(30)]
    expect(passes(decide('instagram', date(2026, 11, 2, 21, 48), rules, used(27)))).toEqual([3])
    expect(passes(decide('instagram', date(2026, 11, 2, 21, 57), rules, used(10)))).toEqual([3])
  })

  it('testBlockOnAnotherDayDoesNotLimit', () => {
    // Regola solo di domenica: lunedì sera non c'è alcun blocco alle 22.
    const rule = scheduleRule(t(22), t(7), { weekdays: [Weekday.sunday] })
    expect(passes(decide('instagram', date(2026, 11, 2, 21, 57), [rule], none))).toEqual([5, 10, 15])
  })

  it('testBlockAfterMidnightLimitsToo', () => {
    const rule = scheduleRule(t(0, 5), t(7))
    expect(passes(decide('instagram', date(2026, 11, 2, 23, 58), [rule], none))).toEqual([5])
  })
})

describe('tetto di 30 minuti', () => {
  it('testMaximumIsThirtyMinutes', () => {
    expect(MAX_PASS_MINUTES).toBe(30)
    expect(Math.max(...PASS_OPTIONS)).toBeLessThanOrEqual(MAX_PASS_MINUTES)
  })

  it('testNoPassExceedsTheMaximumWhateverTheBudget', () => {
    for (const limit of [1, 2, 4, 5, 29, 30, 31, 60, 600, 1439]) {
      for (const consumed of [0, 1, 10]) {
        const decision = decide('instagram', noon, [limitRule(limit)], used(consumed))
        if (decision.kind === 'allowed') {
          for (const minutes of decision.passes) {
            expect(minutes, `limite ${limit}, usati ${consumed}`).toBeLessThanOrEqual(MAX_PASS_MINUTES)
          }
        }
      }
    }
  })

  it('testNoPassExceedsTheMaximumWithoutRules', () => {
    expect(Math.max(...passes(decide('instagram', noon, [], none)))).toBeLessThanOrEqual(MAX_PASS_MINUTES)
  })
})

describe('blocchi concatenati', () => {
  it('testAdjacentWindowsAreFollowed', () => {
    const rules = [scheduleRule(t(9), t(13)), scheduleRule(t(13), t(15))]
    expect(blockedUntil(decide('instagram', noon, rules, none))).toBe(date(2026, 11, 2, 15))
  })

  it('testOverlappingWindowsAreFollowed', () => {
    const rules = [scheduleRule(t(9), t(13)), scheduleRule(t(12, 30), t(14))]
    expect(blockedUntil(decide('instagram', noon, rules, none))).toBe(date(2026, 11, 2, 14))
  })

  it('testGapBetweenWindowsStopsTheChain', () => {
    const rules = [scheduleRule(t(9), t(13)), scheduleRule(t(13, 1), t(15))]
    expect(blockedUntil(decide('instagram', noon, rules, none))).toBe(date(2026, 11, 2, 13))
  })

  it('testLimitThenNightWindow', () => {
    const rules = [limitRule(30), scheduleRule(t(0), t(7))]
    expect(blockedUntil(decide('instagram', date(2026, 11, 2, 20), rules, used(30)))).toBe(date(2026, 11, 3, 7))
  })

  it('testReasonIsTheRuleThatLastsLonger', () => {
    const limit = limitRule(30, { id: 'limite' })
    const night = scheduleRule(t(23), t(1), { id: 'notte' })
    const decision = decide('instagram', date(2026, 11, 2, 23, 30), [limit, night], used(30))
    expect(decision).toMatchObject({ reason: { type: 'schedule', ruleId: 'notte' }, until: date(2026, 11, 3, 1) })
  })

  it('testReasonWithTheSameEndIsTheFirstRule', () => {
    const rules = [scheduleRule(t(9), t(13), { id: 'prima' }), scheduleRule(t(10), t(13), { id: 'seconda' })]
    expect(decide('instagram', noon, rules, none)).toMatchObject({ reason: { ruleId: 'prima' } })
  })

  it('testWindowsCoveringTheWholeWeekStopAtSevenDays', () => {
    const rules = [scheduleRule(t(0), t(12)), scheduleRule(t(12), t(0))]
    expect(blockedUntil(decide('instagram', noon, rules, none))).toBe(noon + 7 * 1440 * MINUTE)
  })
})

describe('cambio ora', () => {
  it('testOvernightAcrossTheShortNight', () => {
    // 29 marzo 2026: alle 02:00 si passa alle 03:00.
    expect(blockedUntil(decide('instagram', date(2026, 3, 28, 23), [scheduleRule(t(22), t(7))], none))).toBe(date(2026, 3, 29, 7))
  })

  it('testOvernightAcrossTheLongNight', () => {
    // 25 ottobre 2026: alle 03:00 si torna alle 02:00.
    expect(blockedUntil(decide('instagram', date(2026, 10, 24, 23), [scheduleRule(t(22), t(7))], none))).toBe(date(2026, 10, 25, 7))
  })

  it('testWindowInTheRepeatedHourEndsInTheSameHour', () => {
    // Le 02:35 si presentano due volte: alla seconda la fine è il secondo 02:45, non il primo già passato.
    const rule = scheduleRule(t(2, 30), t(2, 45))
    const second0235 = Date.UTC(2026, 9, 25, 1, 35)
    expect(blockedUntil(decide('instagram', second0235, [rule], none))).toBe(Date.UTC(2026, 9, 25, 1, 45))
  })

  it('testWindowStartingInTheSkippedHourLimitsPasses', () => {
    // Le 02:30 non esistono: la finestra 02:30–03:15 scatta di fatto alle 03:00, cioè dopo le 01:59.
    const rule = scheduleRule(t(2, 30), t(3, 15))
    expect(passes(decide('instagram', date(2026, 3, 29, 1, 50), [rule], none))).toEqual([5, 10])
    expect(blockedUntil(decide('instagram', date(2026, 3, 29, 3, 0), [rule], none))).toBe(date(2026, 3, 29, 3, 15))
  })

  it('testLimitOnTheLongDayEndsAtLocalMidnight', () => {
    const usage = ledger({ app: 'instagram', grantedAt: date(2026, 10, 25, 1), minutes: 30 })
    expect(blockedUntil(decide('instagram', date(2026, 10, 25, 12), [limitRule(30)], usage))).toBe(date(2026, 10, 26, 0))
  })
})

describe('purezza', () => {
  it('testDecideDoesNotChangeItsInputs', () => {
    const rules: Rule[] = [limitRule(30), scheduleRule(t(22), t(7))]
    const usage = used(10)
    const before = JSON.stringify({ rules, usage })
    decide('instagram', noon, rules, usage)
    expect(JSON.stringify({ rules, usage })).toBe(before)
  })
})
