import { describe, expect, it } from 'vitest'
import { createPINRecord, derive, PBKDF2_ITERATIONS, randomSalt, toHex, verifyPIN } from './pinHash'

const ascii = (text: string) => new TextEncoder().encode(text)
const salt = ascii('sale-di-prova-16')

describe('pinHash', () => {
  // Vettori noti di PBKDF2-HMAC-SHA256.
  it('testKnownVectors', async () => {
    expect(toHex(await derive('password', ascii('salt'), 1)))
      .toBe('120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b')
    expect(toHex(await derive('password', ascii('salt'), 4096)))
      .toBe('c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a')
  })

  it('testRecordKeepsSaltAndIterations', async () => {
    const record = await createPINRecord('483920', salt, 10)
    expect(record.salt).toBe(toHex(salt))
    expect(record.iterations).toBe(10)
    expect(record.hash).toHaveLength(64)
    expect(record.hash).not.toContain('483920')
  })

  it('testDefaultIterations', async () => {
    expect(PBKDF2_ITERATIONS).toBe(600_000)
    expect((await createPINRecord('483920', salt)).iterations).toBe(600_000)
  })

  it('testVerify', async () => {
    const record = await createPINRecord('483920', salt, 10)
    expect(await verifyPIN(record, '483920')).toBe(true)
    expect(await verifyPIN(record, '483921')).toBe(false)
    expect(await verifyPIN(record, '')).toBe(false)
  })

  it('testVerifyUsesTheSavedIterations', async () => {
    // Alzare il valore predefinito non deve invalidare i PIN già salvati.
    const record = await createPINRecord('483920', salt, 7)
    expect(await verifyPIN(record, '483920')).toBe(true)
  })

  it('testDifferentSaltsGiveDifferentHashes', async () => {
    const first = await createPINRecord('483920', ascii('sale-numero-uno!'), 10)
    const second = await createPINRecord('483920', ascii('sale-numero-due!'), 10)
    expect(first.hash).not.toBe(second.hash)
  })

  it('testCorruptRecordDoesNotVerify', async () => {
    const record = await createPINRecord('483920', salt, 10)
    expect(await verifyPIN({ ...record, hash: 'abc' }, '483920')).toBe(false)
    expect(await verifyPIN({ ...record, hash: 'zz'.repeat(32) }, '483920')).toBe(false)
    expect(await verifyPIN({ ...record, salt: 'non-esadecimale' }, '483920')).toBe(false)
    expect(await verifyPIN({ ...record, iterations: 0 }, '483920')).toBe(false)
  })

  it('testRandomSalt', () => {
    expect(randomSalt()).toHaveLength(16)
    expect(toHex(randomSalt())).not.toBe(toHex(randomSalt()))
  })
})
