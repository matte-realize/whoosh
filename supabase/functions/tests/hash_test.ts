// hash_test.ts — keyed recipient hash (contract §9). Verifies HMAC-SHA-256 determinism,
// pepper sensitivity, and the last-two-digits helper. Run: deno test supabase/functions/tests/hash_test.ts

import { assert, assertEquals } from "jsr:@std/assert@1";
import { last2, recipientHash } from "../_shared/hash.ts";

Deno.test("recipientHash is deterministic for the same pepper", async () => {
  const a = await recipientHash("+16175550123", "pepper-secret");
  const b = await recipientHash("+16175550123", "pepper-secret");
  assertEquals(a, b);
  assertEquals(a.length, 64); // SHA-256 hex
});

Deno.test("recipientHash changes with the pepper", async () => {
  const a = await recipientHash("+16175550123", "pepper-secret");
  const b = await recipientHash("+16175550123", "other-pepper");
  assert(a !== b);
});

Deno.test("recipientHash differs per number", async () => {
  const a = await recipientHash("+16175550123", "p");
  const b = await recipientHash("+16175550124", "p");
  assert(a !== b);
});

Deno.test("last2 returns the final two digits", () => {
  assertEquals(last2("+16175550123"), "23");
  assertEquals(last2("+14158675309"), "09");
});
