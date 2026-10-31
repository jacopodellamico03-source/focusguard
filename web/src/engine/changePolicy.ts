import { RuleValidator, type Rule } from './rule'
import { TimeOfDay } from './time'

/**
 * Effetto di una modifica sulle restrizioni:
 * `tightening` non chiede nulla, `relaxing` chiede attesa e PIN, `neutral` non cambia i blocchi.
 */
export type ChangeImpact = 'tightening' | 'relaxing' | 'neutral'

function isSuperset<T>(set: ReadonlySet<T>, other: ReadonlySet<T>): boolean {
  return [...other].every((value) => set.has(value))
}

/** Minuti del giorno coperti dalla finestra (gestisce la mezzanotte). */
function minuteSet(start: TimeOfDay, end: TimeOfDay): Set<number> {
  const duration = RuleValidator.durationMinutes(start, end)
  const first = TimeOfDay.minutesFromMidnight(start)
  return new Set(Array.from({ length: duration }, (_, index) => (first + index) % 1440))
}

/** Quanto cambia un insieme: toglie qualcosa o ne aggiunge soltanto? */
function compareSets<T>(oldValues: Iterable<T>, newValues: Iterable<T>): { relaxes: boolean; tightens: boolean } {
  const oldSet = new Set(oldValues)
  const newSet = new Set(newValues)
  const keepsAll = isSuperset(newSet, oldSet)
  return { relaxes: !keepsAll, tightens: keepsAll && newSet.size > oldSet.size }
}

function compare(old: Rule, updated: Rule): ChangeImpact {
  // Regole spente prima e dopo: niente cambia nei blocchi.
  if (!old.isEnabled && !updated.isEnabled) return 'neutral'
  if (old.isEnabled && !updated.isEnabled) return 'relaxing'
  if (!old.isEnabled && updated.isEnabled) return 'tightening'

  const comparisons = [compareSets(old.apps, updated.apps), compareSets(old.weekdays, updated.weekdays)]

  if (old.kind.type === 'dailyLimit' && updated.kind.type === 'dailyLimit') {
    comparisons.push({ relaxes: updated.kind.minutes > old.kind.minutes, tightens: updated.kind.minutes < old.kind.minutes })
  } else if (old.kind.type === 'schedule' && updated.kind.type === 'schedule') {
    comparisons.push(compareSets(minuteSet(old.kind.start, old.kind.end), minuteSet(updated.kind.start, updated.kind.end)))
  } else {
    // Cambio di tipo: non confrontabile, quindi prudenza.
    return 'relaxing'
  }

  if (comparisons.some((comparison) => comparison.relaxes)) return 'relaxing'
  if (comparisons.some((comparison) => comparison.tightens)) return 'tightening'
  return 'neutral'
}

/** Classifica le modifiche per decidere quando chiedere il PIN. Principio: nel dubbio è "relaxing". */
export const ChangePolicy = {
  /**
   * @param old regola esistente, null se nuova.
   * @param updated regola dopo la modifica, null se eliminata.
   */
  impact(old: Rule | null, updated: Rule | null): ChangeImpact {
    if (old === null) return updated === null ? 'neutral' : 'tightening'
    if (updated === null) return old.isEnabled ? 'relaxing' : 'neutral'
    return compare(old, updated)
  },
}
