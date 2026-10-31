import { describe, expect, it } from 'vitest'
import { Rule, RuleValidator, type RuleValidationError } from './rule'
import { limitRule, scheduleRule, t, date } from './testSupport'
import { TimeOfDay, Weekday } from './time'

describe('fuso orario dei test', () => {
  it('testTimeZoneIsEuropeRome', () => {
    expect(new Date(2026, 10, 2, 10).toISOString()).toBe('2026-11-02T09:00:00.000Z')
    expect(new Date(2026, 6, 2, 10).toISOString()).toBe('2026-07-02T08:00:00.000Z')
  })
})

describe('TimeOfDay', () => {
  it('testRejectsOutOfRange', () => {
    expect(TimeOfDay.make(24, 0)).toBeNull()
    expect(TimeOfDay.make(10, 60)).toBeNull()
    expect(TimeOfDay.make(-1, 0)).toBeNull()
    expect(TimeOfDay.make(1.5, 0)).toBeNull()
    expect(TimeOfDay.make(23, 59)).not.toBeNull()
  })

  it('testMinutesRoundTrip', () => {
    expect(TimeOfDay.minutesFromMidnight(t(1, 30))).toBe(90)
    expect(TimeOfDay.fromMinutes(90)).toEqual(t(1, 30))
    expect(TimeOfDay.fromMinutes(1440)).toBeNull()
  })

  it('testDescription', () => {
    expect(TimeOfDay.describe(t(7, 5))).toBe('07:05')
  })

  it('testFromDate', () => {
    expect(TimeOfDay.at(date(2026, 11, 2, 22, 45))).toEqual(t(22, 45))
  })
})

describe('RuleSchedule', () => {
  it('testWeekdayFromDate', () => {
    expect(Weekday.at(date(2026, 11, 2))).toBe(Weekday.monday)
    expect(Weekday.at(date(2026, 11, 8))).toBe(Weekday.sunday)
  })

  it('testDaytimeWindow', () => {
    const rule = scheduleRule(t(9), t(13))
    expect(Rule.isScheduleActive(rule, date(2026, 11, 2, 8, 59))).toBe(false)
    expect(Rule.isScheduleActive(rule, date(2026, 11, 2, 9, 0))).toBe(true)
    expect(Rule.isScheduleActive(rule, date(2026, 11, 2, 12, 59))).toBe(true)
    expect(Rule.isScheduleActive(rule, date(2026, 11, 2, 13, 0))).toBe(false)
  })

  it('testOvernightWindow', () => {
    const rule = scheduleRule(t(22), t(7))
    expect(Rule.isScheduleActive(rule, date(2026, 11, 2, 23, 30))).toBe(true)
    expect(Rule.isScheduleActive(rule, date(2026, 11, 3, 6, 59))).toBe(true)
    expect(Rule.isScheduleActive(rule, date(2026, 11, 3, 7, 0))).toBe(false)
    expect(Rule.isScheduleActive(rule, date(2026, 11, 3, 15, 0))).toBe(false)
  })

  it('testOvernightUsesStartDay', () => {
    // Solo domenica sera: lunedì 06:00 è ancora dentro la finestra iniziata domenica.
    const rule = scheduleRule(t(22), t(7), { weekdays: [Weekday.sunday] })
    expect(Rule.isScheduleActive(rule, date(2026, 11, 8, 23, 0))).toBe(true)
    expect(Rule.isScheduleActive(rule, date(2026, 11, 9, 6, 0))).toBe(true)
    // Domenica mattina appartiene alla finestra di sabato sera: non attiva.
    expect(Rule.isScheduleActive(rule, date(2026, 11, 8, 6, 0))).toBe(false)
  })

  it('testWeekdayFilterDaytime', () => {
    const weekdays = [Weekday.monday, Weekday.tuesday, Weekday.wednesday, Weekday.thursday, Weekday.friday]
    const rule = scheduleRule(t(9), t(17), { weekdays })
    expect(Rule.isScheduleActive(rule, date(2026, 11, 6, 10))).toBe(true) // venerdì
    expect(Rule.isScheduleActive(rule, date(2026, 11, 7, 10))).toBe(false) // sabato
  })

  it('testDisabledOrLimitNeverActive', () => {
    expect(Rule.isScheduleActive(scheduleRule(t(0), t(23, 59), { enabled: false }), date(2026, 11, 2))).toBe(false)
    expect(Rule.isScheduleActive(limitRule(30), date(2026, 11, 2))).toBe(false)
  })

  it('testCodableRoundTrip', () => {
    const rules = [limitRule(45, { weekdays: [Weekday.monday] }), scheduleRule(t(22), t(7))]
    expect(JSON.parse(JSON.stringify(rules))).toEqual(rules)
  })
})

describe('RuleValidator', () => {
  it('testValidRules', () => {
    expect(RuleValidator.validate(limitRule(30))).toEqual([])
    expect(RuleValidator.validate(scheduleRule(t(22), t(7)))).toEqual([])
  })

  it('testEmptyNameAndWeekdays', () => {
    const rule: Rule = { ...limitRule(10, { weekdays: [] }), name: '  ' }
    expect(RuleValidator.validate(rule)).toEqual([{ type: 'emptyName' }, { type: 'noWeekdays' }])
  })

  it('testLimitRange', () => {
    expect(RuleValidator.validate(limitRule(0))).toEqual([{ type: 'limitOutOfRange', minutes: 0 }])
    expect(RuleValidator.validate(limitRule(1440))).toEqual([{ type: 'limitOutOfRange', minutes: 1440 }])
    expect(RuleValidator.validate(limitRule(1439))).toEqual([])
  })

  it('testLimitMustBeWholeMinutes', () => {
    expect(RuleValidator.validate(limitRule(1.5))).toEqual([{ type: 'limitOutOfRange', minutes: 1.5 }])
  })

  it('testScheduleDuration', () => {
    expect(RuleValidator.durationMinutes(t(22), t(7))).toBe(540)
    expect(RuleValidator.durationMinutes(t(23, 50), t(0, 5))).toBe(15)
    // Il minimo di 15 minuti era un vincolo di iOS: qui non vale.
    expect(RuleValidator.validate(scheduleRule(t(10), t(10, 10)))).toEqual([])
    expect(RuleValidator.validate(scheduleRule(t(10), t(10, 1)))).toEqual([])
    expect(RuleValidator.validate(scheduleRule(t(10), t(10)))).toEqual([{ type: 'scheduleEmpty' }])
  })

  it('testRuleNeedsAtLeastOneApp', () => {
    expect(RuleValidator.validate(limitRule(30, { apps: [] }))).toEqual([{ type: 'noApps' }])
  })

  it('testMessagesAreItalian', () => {
    const errors: RuleValidationError[] = [
      { type: 'emptyName' },
      { type: 'noWeekdays' },
      { type: 'noApps' },
      { type: 'limitOutOfRange', minutes: 0 },
      { type: 'scheduleEmpty' },
    ]
    expect(errors.map(RuleValidator.describe)).toEqual([
      'Dai un nome alla regola.',
      'Scegli almeno un giorno della settimana.',
      'Scegli almeno un\'app.',
      'Il limite deve essere tra 1 e 1439 minuti (ora: 0).',
      'Inizio e fine coincidono.',
    ])
  })
})
