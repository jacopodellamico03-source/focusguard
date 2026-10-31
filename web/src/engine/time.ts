// Il tempo è sempre passato come parametro, in millisecondi epoch.
// Giorni e ore sono quelli del fuso locale del dispositivo.

/** Ora del giorno (ore e minuti), indipendente dalla data. */
export type TimeOfDay = { readonly hour: number; readonly minute: number }

export const TimeOfDay = {
  /** Restituisce null se ore o minuti sono fuori intervallo. */
  make(hour: number, minute: number): TimeOfDay | null {
    const valid = Number.isInteger(hour) && Number.isInteger(minute)
      && hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59
    return valid ? { hour, minute } : null
  },

  /** Minuti trascorsi dalla mezzanotte (0...1439). */
  minutesFromMidnight(time: TimeOfDay): number {
    return time.hour * 60 + time.minute
  },

  fromMinutes(minutes: number): TimeOfDay | null {
    return TimeOfDay.make(Math.floor(minutes / 60), minutes % 60)
  },

  /** Estrae l'ora del giorno da una data nel fuso locale. */
  at(at: number): TimeOfDay {
    const date = new Date(at)
    return { hour: date.getHours(), minute: date.getMinutes() }
  },

  describe(time: TimeOfDay): string {
    return `${String(time.hour).padStart(2, '0')}:${String(time.minute).padStart(2, '0')}`
  },
}

/** Giorno della settimana con la stessa numerazione del motore Swift (1 = domenica ... 7 = sabato). */
export type Weekday = 1 | 2 | 3 | 4 | 5 | 6 | 7

export const Weekday = {
  sunday: 1,
  monday: 2,
  tuesday: 3,
  wednesday: 4,
  thursday: 5,
  friday: 6,
  saturday: 7,

  all: [1, 2, 3, 4, 5, 6, 7],
  /** Ordine lunedì → domenica, comodo per l'interfaccia italiana. */
  mondayFirst: [2, 3, 4, 5, 6, 7, 1],

  at(at: number): Weekday {
    return (new Date(at).getDay() + 1) as Weekday
  },
} as const

/** Mezzanotte locale del giorno di `at`. */
export function startOfDay(at: number): number {
  const date = new Date(at)
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime()
}

/** Mezzanotte locale del giorno dopo: un giorno può durare 23 o 25 ore. */
export function startOfNextDay(at: number): number {
  const date = new Date(at)
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1).getTime()
}

/** Mezzanotte locale del giorno prima. */
export function startOfPreviousDay(at: number): number {
  const date = new Date(at)
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() - 1).getTime()
}
