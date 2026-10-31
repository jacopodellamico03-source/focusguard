import { describe, expect, it } from 'vitest'
import { EventLogCodec, type EventLogEntry } from './eventLog'
import { date } from './testSupport'

describe('EventLog', () => {
  it('testRoundTripAndCorruptLines', () => {
    const entries: EventLogEntry[] = [
      { at: date(2026, 11, 2, 22), app: 'instagram', ruleId: 'rule-a', type: 'blocked' },
      { at: date(2026, 11, 3, 7), app: null, ruleId: null, type: 'passGranted', note: 'test' },
    ]
    const data = EventLogCodec.encodeAll(entries) + '{riga rotta\n'
    expect(EventLogCodec.decode(data)).toEqual(entries)
  })

  it('testValidJSONWithTheWrongShapeIsSkipped', () => {
    const good: EventLogEntry = { at: 1, app: null, ruleId: null, type: 'blocked' }
    const data = ['42', 'null', '{"at":"ieri","type":"blocked"}', '{"at":1,"type":"altro"}', '{"type":"blocked"}']
      .join('\n')
    expect(EventLogCodec.decode(`${data}\n${EventLogCodec.encodeLine(good)}`)).toEqual([good])
  })

  it('testEncodeLineEndsWithNewline', () => {
    const line = EventLogCodec.encodeLine({ at: 1, app: null, ruleId: null, type: 'blocked' })
    expect(line.endsWith('\n')).toBe(true)
    expect(line.indexOf('\n')).toBe(line.length - 1)
  })

  it('testPrune', () => {
    const now = date(2026, 11, 30, 12)
    const old: EventLogEntry = { at: date(2026, 10, 1), app: null, ruleId: null, type: 'blocked' }
    const recent: EventLogEntry = { at: date(2026, 11, 29), app: null, ruleId: null, type: 'blocked' }
    expect(EventLogCodec.pruned([old, recent], 14, now)).toEqual([recent])
  })
})
