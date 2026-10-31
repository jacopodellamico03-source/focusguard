import type { AppId } from './rule'

const EVENT_TYPES = ['blocked', 'passGranted', 'changeRequested', 'changeConfirmed', 'changeCancelled', 'pinReset'] as const
export type EventType = (typeof EVENT_TYPES)[number]

/** Una riga del registro eventi. */
export type EventLogEntry = {
  readonly at: number
  readonly app: AppId | null
  readonly ruleId: string | null
  readonly type: EventType
  readonly note?: string
}

function isEntry(value: unknown): value is EventLogEntry {
  if (typeof value !== 'object' || value === null) return false
  const { at, type } = value as { at?: unknown; type?: unknown }
  return typeof at === 'number' && EVENT_TYPES.includes(type as EventType)
}

function parseLine(line: string): EventLogEntry | null {
  try {
    const value: unknown = JSON.parse(line)
    return isEntry(value) ? value : null
  } catch {
    return null
  }
}

/** Formato JSON Lines: una riga JSON per evento. Appendere costa poco. */
export const EventLogCodec = {
  /** Una riga terminata da "\n". */
  encodeLine(entry: EventLogEntry): string {
    return `${JSON.stringify(entry)}\n`
  },

  encodeAll(entries: readonly EventLogEntry[]): string {
    return entries.map(EventLogCodec.encodeLine).join('')
  },

  /** Decodifica il testo intero, saltando le righe corrotte (es. scrittura interrotta). */
  decode(data: string): EventLogEntry[] {
    return data
      .split('\n')
      .filter((line) => line !== '')
      .map(parseLine)
      .filter((entry) => entry !== null)
  },

  /** Tiene solo gli eventi degli ultimi `days` giorni, per non far crescere i dati. */
  pruned(entries: readonly EventLogEntry[], days: number, now: number): EventLogEntry[] {
    const cutoff = now - days * 86_400_000
    return entries.filter((entry) => entry.at >= cutoff)
  },
}
