import { describe, expect, it } from 'vitest'
import { date, MINUTE, SECOND } from './testSupport'
import { UsageLedger, type PassGrant } from './usageLedger'

const pass = (grantedAt: number, minutes: number, app: PassGrant['app'] = 'instagram'): PassGrant => ({ app, grantedAt, minutes })
const ledger = (...grants: PassGrant[]): UsageLedger => ({ grants })

describe('UsageLedger', () => {
  const noon = date(2026, 11, 2, 12)

  it('testEmptyLedgerHasNoUsage', () => {
    expect(UsageLedger.usedMinutes(UsageLedger.empty, ['instagram'], noon)).toBe(0)
  })

  it('testRecordAppendsWithoutChangingTheOriginal', () => {
    const grant = pass(noon, 5)
    const updated = UsageLedger.record(UsageLedger.empty, grant)
    expect(updated.grants).toEqual([grant])
    expect(UsageLedger.empty.grants).toEqual([])
  })

  it('testExpiresAt', () => {
    expect(UsageLedger.expiresAt(pass(noon, 15))).toBe(noon + 15 * MINUTE)
  })

  it('testSumsPassesOfTheDay', () => {
    const value = ledger(pass(date(2026, 11, 2, 9), 5), pass(date(2026, 11, 2, 11), 15))
    expect(UsageLedger.usedMinutes(value, ['instagram'], noon)).toBe(20)
  })

  it('testPassIsChargedInFullFromTheMomentItIsGranted', () => {
    expect(UsageLedger.usedMinutes(ledger(pass(noon, 15)), ['instagram'], noon + SECOND)).toBe(15)
  })

  it('testCountsOnlyTheRequestedApps', () => {
    const value = ledger(pass(noon, 5, 'instagram'), pass(noon, 10, 'tiktok'), pass(noon, 15, 'youtube'))
    expect(UsageLedger.usedMinutes(value, ['tiktok'], noon)).toBe(10)
    expect(UsageLedger.usedMinutes(value, ['instagram', 'youtube'], noon)).toBe(20)
  })

  it('testOverlappingPassesAddUp', () => {
    expect(UsageLedger.usedMinutes(ledger(pass(noon, 15), pass(noon + MINUTE, 5)), ['instagram'], noon)).toBe(20)
  })

  it('testResetsAtLocalMidnight', () => {
    const value = ledger(pass(date(2026, 11, 2, 23, 0), 15))
    expect(UsageLedger.usedMinutes(value, ['instagram'], date(2026, 11, 2, 23, 59))).toBe(15)
    expect(UsageLedger.usedMinutes(value, ['instagram'], date(2026, 11, 3, 0, 0))).toBe(0)
  })

  it('testPassAcrossMidnightIsSplit', () => {
    const value = ledger(pass(date(2026, 11, 2, 23, 55), 15))
    expect(UsageLedger.usedMinutes(value, ['instagram'], date(2026, 11, 2, 23, 56))).toBe(5)
    expect(UsageLedger.usedMinutes(value, ['instagram'], date(2026, 11, 3, 0, 1))).toBe(10)
    expect(UsageLedger.usedMinutes(value, ['instagram'], date(2026, 11, 4, 0, 1))).toBe(0)
  })

  it('testPassFromTheNextDayDoesNotCountToday', () => {
    expect(UsageLedger.usedMinutes(ledger(pass(date(2026, 11, 3, 9), 15)), ['instagram'], noon)).toBe(0)
  })

  it('testSplitOnTheShortDayOfDaylightSaving', () => {
    // 29 marzo 2026 dura 23 ore: la mezzanotte dopo resta quella locale.
    const value = ledger(pass(date(2026, 3, 29, 23, 55), 15))
    expect(UsageLedger.usedMinutes(value, ['instagram'], date(2026, 3, 29, 12))).toBe(5)
    expect(UsageLedger.usedMinutes(value, ['instagram'], date(2026, 3, 30, 12))).toBe(10)
  })

  it('testSplitOnTheLongDayOfDaylightSaving', () => {
    // 25 ottobre 2026 dura 25 ore: la coda del primo pass e tutto il secondo cadono in quel giorno.
    const value = ledger(pass(date(2026, 10, 24, 23, 55), 15), pass(date(2026, 10, 25, 23, 50), 5))
    expect(UsageLedger.usedMinutes(value, ['instagram'], date(2026, 10, 24, 12))).toBe(5)
    expect(UsageLedger.usedMinutes(value, ['instagram'], date(2026, 10, 25, 12))).toBe(15)
  })

  it('testPruneKeepsPassesStillInsideThePeriod', () => {
    const now = date(2026, 11, 30, 12)
    const old = pass(date(2026, 10, 1), 15)
    const recent = pass(date(2026, 11, 29), 15)
    expect(UsageLedger.pruned(ledger(old, recent), 14, now).grants).toEqual([recent])
  })

  it('testCodableRoundTrip', () => {
    const value = ledger(pass(noon, 5), pass(noon, 10, 'youtube'))
    expect(JSON.parse(JSON.stringify(value))).toEqual(value)
  })
})
