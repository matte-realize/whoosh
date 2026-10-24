// hash.ts — keyed recipient hash (contract §9). HMAC-SHA-256 of the E.164 number with a
// server-side pepper secret, lowercase hex. A keyed hash (not a per-row salt) is required so
// cross-row rate limiting works. The pepper lives only as an Edge Function secret.

export async function recipientHash(e164: string, pepper: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(pepper),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(e164));
  return [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Last two digits of the number, for audit display only.
export function last2(e164: string): string {
  const digits = e164.replace(/\D/g, "");
  return digits.slice(-2);
}
