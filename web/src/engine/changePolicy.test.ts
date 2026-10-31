import { describe, expect, it } from 'vitest'
import { ChangePolicy } from './changePolicy'
import { Cooldown } from './relaxation'
import type { Rule } from './rule'
import { date, limitRule, scheduleRule, SECOND, t } from './testSupport'
import { Weekday } from './time'

describe('ChangePolicy', () => {
  it('testCreateAndDelete', () => {
    const rule = limitRule(30)
    expect(ChangePolicy.impact(null, rule)).toBe('tightening')
    expect(ChangePolicy.impact(rule, null)).toBe('relaxing')
    expect(ChangePolicy.impact(limitRule(30, { enabled: false }), null)).toBe('neutral')
  })

  it('testToggle', () => {
    const on = limitRule(30)
    const off: Rule = { ...on, isEnabled: false }
    expect(ChangePolicy.impact(on, off)).toBe('relaxing')
    expect(ChangePolicy.impact(off, on)).toBe('tightening')
  })

  it('testLimitMinutes', () => {
    const old = limitRule(30)
    const more: Rule = { ...old, kind: { type: 'dailyLimit', minutes: 60 } }
    const less: Rule = { ...old, kind: { type: 'dailyLimit', minutes: 15 } }
    expect(ChangePolicy.impact(old, more)).toBe('relaxing')
    expect(ChangePolicy.impact(old, less)).toBe('tightening')
  })

  it('testNameOnlyIsNeutral', () => {
    const old = limitRule(30)
    expect(ChangePolicy.impact(old, { ...old, name: 'Altro nome' })).toBe('neutral')
  })

  // In Swift i token erano opachi e ogni cambio era "relaxing". Qui le app si vedono.
  it('testSelectionChangeIsRelaxing', () => {
    const old = limitRule(30, { apps: ['instagram', 'tiktok'] })
    expect(ChangePolicy.impact(old, { ...old, apps: ['instagram'] })).toBe('relaxing')
  })

  it('testAddingAnAppIsTightening', () => {
    const old = limitRule(30, { apps: ['instagram'] })
    expect(ChangePolicy.impact(old, { ...old, apps: ['instagram', 'youtube'] })).toBe('tightening')
  })

  it('testSwappingAppsIsRelaxing', () => {
    const old = limitRule(30, { apps: ['instagram'] })
    expect(ChangePolicy.impact(old, { ...old, apps: ['youtube'] })).toBe('relaxing')
  })

  it('testSameAppsInAnotherOrderIsNeutral', () => {
    const old = limitRule(30, { apps: ['instagram', 'youtube'] })
    expect(ChangePolicy.impact(old, { ...old, apps: ['youtube', 'instagram'] })).toBe('neutral')
  })

  it('testRelaxingWinsOverTightening', () => {
    const old = limitRule(30, { apps: ['instagram', 'youtube'] })
    const mixed: Rule = { ...old, apps: ['instagram'], kind: { type: 'dailyLimit', minutes: 10 } }
    expect(ChangePolicy.impact(old, mixed)).toBe('relaxing')
  })

  it('testWeekdays', () => {
    const old = limitRule(30, { weekdays: [Weekday.monday, Weekday.tuesday] })
    const fewer: Rule = { ...old, weekdays: [Weekday.monday] }
    const more: Rule = { ...old, weekdays: [Weekday.monday, Weekday.tuesday, Weekday.friday] }
    expect(ChangePolicy.impact(old, fewer)).toBe('relaxing')
    expect(ChangePolicy.impact(old, more)).toBe('tightening')
  })

  it('testScheduleWindow', () => {
    const old = scheduleRule(t(22), t(7))
    const wider: Rule = { ...old, kind: { type: 'schedule', start: t(21), end: t(7) } }
    const narrower: Rule = { ...old, kind: { type: 'schedule', start: t(23), end: t(7) } }
    const shifted: Rule = { ...old, kind: { type: 'schedule', start: t(23), end: t(8) } }
    expect(ChangePolicy.impact(old, wider)).toBe('tightening')
    expect(ChangePolicy.impact(old, narrower)).toBe('relaxing')
    expect(ChangePolicy.impact(old, shifted)).toBe('relaxing')
  })

  it('testKindChangeIsRelaxing', () => {
    const old = limitRule(30)
    expect(ChangePolicy.impact(old, { ...old, kind: { type: 'schedule', start: t(0), end: t(23, 59) } })).toBe('relaxing')
  })

  it('testDisabledBeforeAndAfterIsNeutral', () => {
    const old = limitRule(30, { enabled: false })
    expect(ChangePolicy.impact(old, { ...old, apps: ['youtube'] })).toBe('neutral')
  })
})

describe('Cooldown', () => {
  it('testCooldown', () => {
    const start = date(2026, 11, 2, 10)
    const cooldown: Cooldown = { requestedAt: start, duration: 600 * SECOND }
    expect(Cooldown.canConfirm(cooldown, start + 599 * SECOND)).toBe(false)
    expect(Cooldown.canConfirm(cooldown, start + 600 * SECOND)).toBe(true)
    expect(Cooldown.remaining(cooldown, start + 100 * SECOND)).toBe(500 * SECOND)
    expect(Cooldown.remaining(cooldown, start + 9_999 * SECOND)).toBe(0)
  })
})
