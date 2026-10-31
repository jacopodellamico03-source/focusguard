import { startOfPreviousDay, TimeOfDay, Weekday } from './time'

export const APP_IDS = ['instagram', 'tiktok', 'youtube'] as const
export type AppId = (typeof APP_IDS)[number]

/** Tipo di regola. */
export type RuleKind =
  /** Le app scelte si bloccano dopo `minutes` minuti nella giornata. Più app condividono il budget. */
  | { readonly type: 'dailyLimit'; readonly minutes: number }
  /** Le app scelte sono bloccate tra `start` e `end` (anche a cavallo della mezzanotte). */
  | { readonly type: 'schedule'; readonly start: TimeOfDay; readonly end: TimeOfDay }

/** Una regola di blocco. */
export type Rule = {
  readonly id: string
  readonly name: string
  readonly kind: RuleKind
  readonly apps: readonly AppId[]
  readonly weekdays: readonly Weekday[]
  readonly isEnabled: boolean
}

export const Rule = {
  /** La regola vale nel giorno della settimana di `at`? */
  appliesOn(rule: Rule, at: number): boolean {
    return rule.weekdays.includes(Weekday.at(at))
  },

  /**
   * Per una regola a orario: `at` cade dentro la finestra di blocco?
   * Per le finestre notturne (es. 22:00–07:00) il giorno che conta è quello in cui la finestra inizia.
   */
  isScheduleActive(rule: Rule, at: number): boolean {
    if (!rule.isEnabled || rule.kind.type !== 'schedule') return false
    const now = TimeOfDay.minutesFromMidnight(TimeOfDay.at(at))
    const start = TimeOfDay.minutesFromMidnight(rule.kind.start)
    const end = TimeOfDay.minutesFromMidnight(rule.kind.end)

    if (start < end) {
      return now >= start && now < end && Rule.appliesOn(rule, at)
    }

    // Finestra a cavallo della mezzanotte.
    if (now >= start) return Rule.appliesOn(rule, at)
    if (now < end) return Rule.appliesOn(rule, startOfPreviousDay(at))
    return false
  },
}

/** Errori di validazione: `RuleValidator.describe` dà il messaggio per l'interfaccia. */
export type RuleValidationError =
  | { readonly type: 'emptyName' }
  | { readonly type: 'noWeekdays' }
  | { readonly type: 'noApps' }
  | { readonly type: 'limitOutOfRange'; readonly minutes: number }
  | { readonly type: 'scheduleEmpty' }

export const RuleValidator = {
  maxLimitMinutes: 1439,

  /** Durata in minuti della finestra, gestendo il passaggio della mezzanotte. */
  durationMinutes(start: TimeOfDay, end: TimeOfDay): number {
    const diff = TimeOfDay.minutesFromMidnight(end) - TimeOfDay.minutesFromMidnight(start)
    return diff >= 0 ? diff : diff + 1440
  },

  /** Restituisce tutti gli errori (lista vuota = regola valida). */
  validate(rule: Rule): RuleValidationError[] {
    const errors: RuleValidationError[] = []

    if (rule.name.trim() === '') errors.push({ type: 'emptyName' })
    if (rule.weekdays.length === 0) errors.push({ type: 'noWeekdays' })
    if (rule.apps.length === 0) errors.push({ type: 'noApps' })

    if (rule.kind.type === 'dailyLimit') {
      const { minutes } = rule.kind
      if (!Number.isInteger(minutes) || minutes < 1 || minutes > RuleValidator.maxLimitMinutes) {
        errors.push({ type: 'limitOutOfRange', minutes })
      }
    } else if (RuleValidator.durationMinutes(rule.kind.start, rule.kind.end) === 0) {
      errors.push({ type: 'scheduleEmpty' })
    }
    return errors
  },

  describe(error: RuleValidationError): string {
    switch (error.type) {
      case 'emptyName':
        return 'Dai un nome alla regola.'
      case 'noWeekdays':
        return 'Scegli almeno un giorno della settimana.'
      case 'noApps':
        return 'Scegli almeno un\'app.'
      case 'limitOutOfRange':
        return `Il limite deve essere tra 1 e ${RuleValidator.maxLimitMinutes} minuti (ora: ${error.minutes}).`
      case 'scheduleEmpty':
        return 'Inizio e fine coincidono.'
    }
  },
}
