import type { AppId, Rule } from './rule'
import { TimeOfDay, Weekday } from './time'

export const SECOND = 1000
export const MINUTE = 60 * SECOND
export const HOUR = 60 * MINUTE

/** Data locale: nei test il fuso è Europe/Rome. 2026-11-02 è un lunedì. */
export function date(year: number, month: number, day: number, hour = 12, minute = 0): number {
  return new Date(year, month - 1, day, hour, minute).getTime()
}

export function t(hour: number, minute = 0): TimeOfDay {
  const value = TimeOfDay.make(hour, minute)
  if (value === null) throw new Error(`Ora non valida: ${hour}:${minute}`)
  return value
}

type RuleOptions = {
  weekdays?: readonly Weekday[]
  enabled?: boolean
  apps?: readonly AppId[]
  id?: string
}

let nextID = 0

export function limitRule(minutes: number, options: RuleOptions = {}): Rule {
  return {
    id: options.id ?? `rule-${++nextID}`,
    name: 'Social',
    kind: { type: 'dailyLimit', minutes },
    apps: options.apps ?? ['instagram'],
    weekdays: options.weekdays ?? Weekday.all,
    isEnabled: options.enabled ?? true,
  }
}

export function scheduleRule(start: TimeOfDay, end: TimeOfDay, options: RuleOptions = {}): Rule {
  return {
    id: options.id ?? `rule-${++nextID}`,
    name: 'Notte',
    kind: { type: 'schedule', start, end },
    apps: options.apps ?? ['instagram'],
    weekdays: options.weekdays ?? Weekday.all,
    isEnabled: options.enabled ?? true,
  }
}
