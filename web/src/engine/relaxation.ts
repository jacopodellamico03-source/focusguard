import type { Rule } from './rule'

/** Attesa obbligatoria prima di confermare una modifica che allenta le regole. */
export type Cooldown = {
  readonly requestedAt: number
  readonly duration: number
}

export const Cooldown = {
  unlocksAt(cooldown: Cooldown): number {
    return cooldown.requestedAt + cooldown.duration
  },

  canConfirm(cooldown: Cooldown, at: number): boolean {
    return at >= Cooldown.unlocksAt(cooldown)
  },

  remaining(cooldown: Cooldown, at: number): number {
    return Math.max(0, Cooldown.unlocksAt(cooldown) - at)
  },
}

export type PendingChange =
  | { readonly type: 'disableRule'; readonly ruleId: string }
  | { readonly type: 'deleteRule'; readonly ruleId: string }
  /** `rule` è la regola come sarà dopo la conferma. */
  | { readonly type: 'editRule'; readonly rule: Rule }
  /** PIN dimenticato: cancella il PIN, le regole restano come sono. */
  | { readonly type: 'resetPIN' }

/** Ciò che la richiesta tiene occupato: una sola richiesta per volta su ciascun bersaglio. */
export type RelaxationTarget =
  | { readonly type: 'rule'; readonly ruleId: string }
  | { readonly type: 'pinReset' }

export type RelaxationPhase = 'waiting' | 'confirmable' | 'expired'

/** Richiesta di una modifica che allenta le regole: si conferma col PIN dopo l'attesa, si può annullare. */
export type PendingRelaxation = {
  readonly id: string
  readonly change: PendingChange
  readonly cooldown: Cooldown
}

export const PendingRelaxation = {
  cooldownDuration: 600_000,
  /** Il reset salta il PIN: l'unico freno è un'attesa molto più lunga. */
  pinResetCooldownDuration: 86_400_000,
  /**
   * Finita l'attesa la conferma vale per poco: altrimenti una richiesta tenuta "armata"
   * permetterebbe di togliere la regola all'istante, in qualsiasi momento.
   */
  confirmationWindow: 1_800_000,

  make(id: string, change: PendingChange, requestedAt: number): PendingRelaxation {
    const duration = change.type === 'resetPIN'
      ? PendingRelaxation.pinResetCooldownDuration
      : PendingRelaxation.cooldownDuration
    return { id, change, cooldown: { requestedAt, duration } }
  },

  /** La conferma chiede il PIN? Non il reset: chi lo chiede il PIN non lo ricorda. */
  requiresAuthentication(request: PendingRelaxation): boolean {
    return request.change.type !== 'resetPIN'
  },

  target(request: PendingRelaxation): RelaxationTarget {
    const { change } = request
    switch (change.type) {
      case 'disableRule':
      case 'deleteRule':
        return { type: 'rule', ruleId: change.ruleId }
      case 'editRule':
        return { type: 'rule', ruleId: change.rule.id }
      case 'resetPIN':
        return { type: 'pinReset' }
    }
  },

  expiresAt(request: PendingRelaxation): number {
    return Cooldown.unlocksAt(request.cooldown) + PendingRelaxation.confirmationWindow
  },

  phase(request: PendingRelaxation, at: number): RelaxationPhase {
    if (!Cooldown.canConfirm(request.cooldown, at)) return 'waiting'
    return at < PendingRelaxation.expiresAt(request) ? 'confirmable' : 'expired'
  },

  canConfirm(request: PendingRelaxation, at: number): boolean {
    return PendingRelaxation.phase(request, at) === 'confirmable'
  },

  /** Attesa che manca prima di poter confermare. */
  remaining(request: PendingRelaxation, at: number): number {
    return Cooldown.remaining(request.cooldown, at)
  },

  /** Tempo che manca alla scadenza della richiesta. */
  confirmationRemaining(request: PendingRelaxation, at: number): number {
    return Math.max(0, PendingRelaxation.expiresAt(request) - at)
  },
}

function sameTarget(lhs: RelaxationTarget, rhs: RelaxationTarget): boolean {
  if (lhs.type === 'rule' && rhs.type === 'rule') return lhs.ruleId === rhs.ruleId
  return lhs.type === rhs.type
}

/** Le richieste in corso. */
export type PendingRelaxationQueue = {
  readonly items: readonly PendingRelaxation[]
}

export const PendingRelaxationQueue = {
  empty: { items: [] } as PendingRelaxationQueue,

  pending(queue: PendingRelaxationQueue, target: RelaxationTarget): PendingRelaxation | null {
    return queue.items.find((item) => sameTarget(PendingRelaxation.target(item), target)) ?? null
  },

  request(queue: PendingRelaxationQueue, id: string): PendingRelaxation | null {
    return queue.items.find((item) => item.id === id) ?? null
  },

  /**
   * Se il bersaglio ha già una richiesta restituisce quella: l'attesa non riparte
   * e non si può cambiare ciò che si sta aspettando.
   */
  enqueue(
    queue: PendingRelaxationQueue,
    change: PendingChange,
    at: number,
    id: string,
  ): { queue: PendingRelaxationQueue; request: PendingRelaxation } {
    const request = PendingRelaxation.make(id, change, at)
    const existing = PendingRelaxationQueue.pending(queue, PendingRelaxation.target(request))
    if (existing !== null) return { queue, request: existing }
    return { queue: { items: [...queue.items, request] }, request }
  },

  remove(queue: PendingRelaxationQueue, id: string): PendingRelaxationQueue {
    return { items: queue.items.filter((item) => item.id !== id) }
  },

  /** PIN cambiato: chi ha appena inserito quello attuale lo ricorda, il reset non serve più. */
  cancelPINReset(queue: PendingRelaxationQueue): { queue: PendingRelaxationQueue; cancelled: PendingRelaxation | null } {
    const cancelled = PendingRelaxationQueue.pending(queue, { type: 'pinReset' })
    return { queue: cancelled === null ? queue : PendingRelaxationQueue.remove(queue, cancelled.id), cancelled }
  },

  /** Toglie le richieste scadute e le restituisce. */
  removeExpired(queue: PendingRelaxationQueue, at: number): { queue: PendingRelaxationQueue; expired: PendingRelaxation[] } {
    const isExpired = (item: PendingRelaxation) => PendingRelaxation.phase(item, at) === 'expired'
    return { queue: { items: queue.items.filter((item) => !isExpired(item)) }, expired: queue.items.filter(isExpired) }
  },
}
