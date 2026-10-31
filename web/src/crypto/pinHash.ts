import { ConstantTime } from '../engine/pin'

export const PBKDF2_ITERATIONS = 600_000
const SALT_BYTES = 16
const HASH_BITS = 256

/** Ciò che si salva del PIN. Le iterazioni restano nel record: alzarle non invalida i PIN esistenti. */
export type PINRecord = {
  readonly salt: string
  readonly hash: string
  readonly iterations: number
}

export function randomSalt(): Uint8Array<ArrayBuffer> {
  return crypto.getRandomValues(new Uint8Array(SALT_BYTES))
}

export function toHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('')
}

function fromHex(text: string): Uint8Array<ArrayBuffer> | null {
  if (!/^(?:[0-9a-f]{2})*$/.test(text)) return null
  return Uint8Array.from(text.match(/../g) ?? [], (pair) => Number.parseInt(pair, 16))
}

/** PBKDF2-SHA256 via WebCrypto. */
export async function derive(pin: string, salt: Uint8Array<ArrayBuffer>, iterations: number): Promise<Uint8Array<ArrayBuffer>> {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(pin), 'PBKDF2', false, ['deriveBits'])
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations }, key, HASH_BITS)
  return new Uint8Array(bits)
}

export async function createPINRecord(
  pin: string,
  salt: Uint8Array<ArrayBuffer>,
  iterations: number = PBKDF2_ITERATIONS,
): Promise<PINRecord> {
  return { salt: toHex(salt), hash: toHex(await derive(pin, salt, iterations)), iterations }
}

/** Un record corrotto non verifica nessun PIN. */
export async function verifyPIN(record: PINRecord, pin: string): Promise<boolean> {
  const salt = fromHex(record.salt)
  const expected = fromHex(record.hash)
  if (salt === null || expected === null) return false
  if (!Number.isInteger(record.iterations) || record.iterations < 1) return false
  return ConstantTime.equals(await derive(pin, salt, record.iterations), expected)
}
