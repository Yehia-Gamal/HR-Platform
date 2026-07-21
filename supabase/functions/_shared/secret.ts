// Constant-time secret comparison helper (audit ESI-03).
// A plain `a !== b` on strings short-circuits on the first differing byte and
// leaks timing. Compare fixed-length SHA-256 digests instead so the comparison
// time is independent of where the mismatch occurs.

async function sha256Bytes(value: string): Promise<Uint8Array> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return new Uint8Array(digest);
}

/**
 * Timing-safe equality for two secrets. Returns false when either side is empty
 * so callers still fail closed on an unset secret.
 */
export async function timingSafeEqual(a: string | null | undefined, b: string | null | undefined): Promise<boolean> {
  if (!a || !b) return false;
  const [da, db] = await Promise.all([sha256Bytes(a), sha256Bytes(b)]);
  // Digests are always 32 bytes; XOR-accumulate so no early return on mismatch.
  let diff = 0;
  for (let i = 0; i < da.length; i++) diff |= da[i] ^ db[i];
  return diff === 0;
}
