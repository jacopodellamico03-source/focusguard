/** Errori di validazione del PIN: `PINPolicy.describe` dà il messaggio per l'interfaccia. */
export type PINValidationError =
  | { readonly type: 'notDigits' }
  | { readonly type: 'wrongLength'; readonly count: number }
  | { readonly type: 'trivial' }

/** Cifre consecutive, anche passando per lo zero (890123). Il passo 9 equivale a -1 modulo 10. */
function isSequence(digits: readonly number[], step: number): boolean {
  return digits.slice(1).every((digit, index) => (digits[index]! + step) % 10 === digit)
}

/** Un blocco ripetuto per tutta la lunghezza: 111111, 121212, 123123. */
function isRepeatedPattern(digits: readonly number[]): boolean {
  for (let period = 1; period <= digits.length / 2; period++) {
    if (digits.length % period === 0 && digits.every((digit, index) => digit === digits[index % period])) {
      return true
    }
  }
  return false
}

function isTrivial(digits: readonly number[]): boolean {
  return isSequence(digits, 1) || isSequence(digits, 9) || isRepeatedPattern(digits)
}

export const PINPolicy = {
  minLength: 6,
  maxLength: 8,

  /** Restituisce tutti gli errori (lista vuota = PIN valido). */
  validate(pin: string): PINValidationError[] {
    const errors: PINValidationError[] = []

    // Solo ASCII: altre scritture hanno le loro cifre.
    const isAllDigits = /^[0-9]*$/.test(pin)
    if (!isAllDigits) errors.push({ type: 'notDigits' })

    const count = Array.from(pin).length
    const hasValidLength = count >= PINPolicy.minLength && count <= PINPolicy.maxLength
    if (!hasValidLength) errors.push({ type: 'wrongLength', count })

    if (isAllDigits && hasValidLength && isTrivial(Array.from(pin, Number))) {
      errors.push({ type: 'trivial' })
    }
    return errors
  },

  describe(error: PINValidationError): string {
    switch (error.type) {
      case 'notDigits':
        return 'Il PIN può contenere solo cifre.'
      case 'wrongLength':
        return `Il PIN deve avere da ${PINPolicy.minLength} a ${PINPolicy.maxLength} cifre.`
      case 'trivial':
        return 'PIN troppo facile: evita sequenze e ripetizioni.'
    }
  },
}

/**
 * Confronto che non si ferma al primo byte diverso: il tempo non rivela quanto è giusto l'hash.
 * In JavaScript è un'approssimazione: il motore può ottimizzare il ciclo.
 */
export const ConstantTime = {
  equals(lhs: Uint8Array, rhs: Uint8Array): boolean {
    if (lhs.length !== rhs.length) return false
    let difference = 0
    for (let index = 0; index < lhs.length; index++) {
      difference |= lhs[index]! ^ rhs[index]!
    }
    return difference === 0
  },
}

/**
 * Tentativi di PIN errati e relativo blocco. Il tempo arriva sempre da fuori,
 * e lo stato si salva: chiudere la pagina non azzera il blocco.
 */
export type PINAttemptPolicy = {
  readonly failedAttempts: number
  readonly lockedUntil: number | null
}

export const PINAttemptPolicy = {
  freeAttempts: 5,
  baseLockout: 60_000,
  maxLockout: 3_600_000,

  initial: { failedAttempts: 0, lockedUntil: null } as PINAttemptPolicy,

  isLocked(policy: PINAttemptPolicy, at: number): boolean {
    return PINAttemptPolicy.remainingLockout(policy, at) > 0
  },

  remainingLockout(policy: PINAttemptPolicy, at: number): number {
    return policy.lockedUntil === null ? 0 : Math.max(0, policy.lockedUntil - at)
  },

  /** Un errore durante il blocco non conta: in quel momento il PIN non viene nemmeno verificato. */
  registerFailure(policy: PINAttemptPolicy, at: number): PINAttemptPolicy {
    if (PINAttemptPolicy.isLocked(policy, at)) return policy
    const failedAttempts = policy.failedAttempts + 1
    if (failedAttempts < PINAttemptPolicy.freeAttempts) return { ...policy, failedAttempts }
    return { failedAttempts, lockedUntil: at + lockout(failedAttempts) }
  },

  registerSuccess(): PINAttemptPolicy {
    return PINAttemptPolicy.initial
  },
}

function lockout(failures: number): number {
  // Oltre 6 raddoppi si è già al massimo: niente potenze enormi.
  const doublings = Math.min(failures - PINAttemptPolicy.freeAttempts, 6)
  return Math.min(PINAttemptPolicy.baseLockout * 2 ** doublings, PINAttemptPolicy.maxLockout)
}
