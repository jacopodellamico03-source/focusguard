import type { AppId } from './rule'
import { startOfDay, startOfNextDay } from './time'

const MINUTE = 60_000

/** Un pass concesso: i suoi minuti scalano dal budget appena concesso, usati o no. */
export type PassGrant = {
  readonly app: AppId
  readonly grantedAt: number
  readonly minutes: number
}

/** I pass concessi. */
export type UsageLedger = {
  readonly grants: readonly PassGrant[]
}

export const UsageLedger = {
  empty: { grants: [] } as UsageLedger,

  record(ledger: UsageLedger, grant: PassGrant): UsageLedger {
    return { grants: [...ledger.grants, grant] }
  },

  expiresAt(grant: PassGrant): number {
    return grant.grantedAt + grant.minutes * MINUTE
  },

  /**
   * Minuti usati dalle app indicate nel giorno locale di `at`.
   * Un pass a cavallo della mezzanotte scala da ciascun giorno la sua parte; i pass sovrapposti si sommano.
   */
  usedMinutes(ledger: UsageLedger, apps: readonly AppId[], at: number): number {
    const dayStart = startOfDay(at)
    const dayEnd = startOfNextDay(at)
    let total = 0
    for (const grant of ledger.grants) {
      if (!apps.includes(grant.app)) continue
      const overlap = Math.min(UsageLedger.expiresAt(grant), dayEnd) - Math.max(grant.grantedAt, dayStart)
      if (overlap > 0) total += overlap
    }
    return total / MINUTE
  },

  /** Tiene solo i pass degli ultimi `days` giorni, per non far crescere i dati. */
  pruned(ledger: UsageLedger, days: number, now: number): UsageLedger {
    const cutoff = now - days * 86_400_000
    return { grants: ledger.grants.filter((grant) => UsageLedger.expiresAt(grant) >= cutoff) }
  },
}
