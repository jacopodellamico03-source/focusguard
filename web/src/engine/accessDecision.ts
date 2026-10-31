import { Rule, RuleValidator, type AppId } from './rule'
import { UsageLedger } from './usageLedger'

const MINUTE = 60_000

export const PASS_OPTIONS = [5, 10, 15] as const
/** FG Pass rifiuta scadenze oltre questo limite: i pass offerti non lo superano mai. */
export const MAX_PASS_MINUTES = 30
/** Regole che coprono tutto il tempo: la fine del blocco non si cerca oltre. */
const BLOCK_HORIZON_MINUTES = 7 * 1440

export type BlockReason =
  /** Mancano i dati (prima installazione o dati di Safari cancellati): nessun pass. */
  | { readonly type: 'notConfigured' }
  | { readonly type: 'schedule' | 'limit'; readonly ruleId: string; readonly ruleName: string }

export type AccessDecision =
  | { readonly kind: 'blocked'; readonly reason: { readonly type: 'notConfigured' }; readonly until: null }
  | { readonly kind: 'blocked'; readonly reason: Exclude<BlockReason, { type: 'notConfigured' }>; readonly until: number }
  /** `minutesLeftToday` è null se nessun limite vale oggi. `passes` può essere vuoto, a un minuto da un blocco. */
  | { readonly kind: 'allowed'; readonly minutesLeftToday: number | null; readonly passes: readonly number[] }

function minutesLeft(rule: Rule, limit: number, usage: UsageLedger, at: number): number {
  return Math.max(0, Math.floor(limit - UsageLedger.usedMinutes(usage, rule.apps, at)))
}

function isBlocking(rule: Rule, usage: UsageLedger, at: number): boolean {
  if (rule.kind.type === 'schedule') return Rule.isScheduleActive(rule, at)
  return Rule.appliesOn(rule, at) && minutesLeft(rule, rule.kind.minutes, usage, at) === 0
}

/**
 * Il primo minuto dopo `now` che soddisfa la condizione, entro `steps` minuti.
 * Si scorre minuto per minuto invece di calcolare la data: così i cambi d'ora,
 * le finestre concatenate e il reset di mezzanotte non hanno casi a parte.
 */
function firstMinuteAfter(now: number, steps: number, condition: (at: number) => boolean): number | null {
  const currentMinute = now - (now % MINUTE)
  for (let step = 1; step <= steps; step++) {
    const at = currentMinute + step * MINUTE
    if (condition(at)) return at
  }
  return null
}

function blocked(blocking: readonly Rule[], rules: readonly Rule[], usage: UsageLedger, now: number): AccessDecision {
  const endOf = (condition: (at: number) => boolean) =>
    firstMinuteAfter(now, BLOCK_HORIZON_MINUTES, condition) ?? now - (now % MINUTE) + BLOCK_HORIZON_MINUTES * MINUTE

  // Il motivo mostrato è quello che dura di più; a parità, la prima regola.
  let reason = blocking[0]!
  let reasonEnd = endOf((at) => !isBlocking(reason, usage, at))
  for (const rule of blocking.slice(1)) {
    const end = endOf((at) => !isBlocking(rule, usage, at))
    if (end > reasonEnd) {
      reason = rule
      reasonEnd = end
    }
  }

  return {
    kind: 'blocked',
    reason: { type: reason.kind.type === 'schedule' ? 'schedule' : 'limit', ruleId: reason.id, ruleName: reason.name },
    until: endOf((at) => !rules.some((rule) => isBlocking(rule, usage, at))),
  }
}

function allowed(rules: readonly Rule[], usage: UsageLedger, now: number): AccessDecision {
  const budgets = rules.flatMap((rule) =>
    rule.kind.type === 'dailyLimit' && Rule.appliesOn(rule, now) ? [minutesLeft(rule, rule.kind.minutes, usage, now)] : [],
  )
  const minutesLeftToday = budgets.length > 0 ? Math.min(...budgets) : null

  // Un pass non deve scavalcare il prossimo blocco: FG Controllo guarda solo il pass.
  const nextBlock = firstMinuteAfter(now, MAX_PASS_MINUTES, (at) => rules.some((rule) => isBlocking(rule, usage, at)))
  const minutesToBlock = nextBlock === null ? MAX_PASS_MINUTES : Math.floor((nextBlock - now) / MINUTE)

  const cap = Math.min(MAX_PASS_MINUTES, minutesToBlock, minutesLeftToday ?? MAX_PASS_MINUTES)
  const fitting = PASS_OPTIONS.filter((minutes) => minutes <= cap)
  // Sotto il pass più piccolo si offre il tempo esatto, altrimenti quel residuo andrebbe perso.
  const passes = fitting.length === 0 && cap > 0 ? [cap] : fitting

  return { kind: 'allowed', minutesLeftToday, passes }
}

export const AccessDecision = {
  /**
   * @param rules null se la configurazione manca.
   * @param usage null se il registro manca: il budget ripartirebbe da zero.
   */
  decide(app: AppId, now: number, rules: readonly Rule[] | null, usage: UsageLedger | null): AccessDecision {
    if (rules === null || usage === null) {
      return { kind: 'blocked', reason: { type: 'notConfigured' }, until: null }
    }

    // Le regole non valide vengono scartate: l'interfaccia impedisce di salvarle, qui è una difesa in più.
    const relevant = rules.filter((rule) =>
      rule.isEnabled && rule.apps.includes(app) && RuleValidator.validate(rule).length === 0,
    )
    const blocking = relevant.filter((rule) => isBlocking(rule, usage, now))
    return blocking.length > 0 ? blocked(blocking, relevant, usage, now) : allowed(relevant, usage, now)
  },
}
