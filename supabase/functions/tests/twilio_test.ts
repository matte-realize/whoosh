// twilio_test.ts — status/error mapping, monotonic/sticky status rules (contract §5.6, §7),
// and Twilio X-Twilio-Signature validation against Twilio's documented example vector.
// Run: deno test supabase/functions/tests/twilio_test.ts

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  canApplyStatus,
  constantTimeEquals,
  isValidTwilioSignature,
  mapProviderErrorCode,
  mapProviderStatus,
} from "../_shared/twilio.ts";

Deno.test("provider status mapping", () => {
  assertEquals(mapProviderStatus("accepted"), "queued");
  assertEquals(mapProviderStatus("queued"), "queued");
  assertEquals(mapProviderStatus("sending"), "queued");
  assertEquals(mapProviderStatus("sent"), "sent");
  assertEquals(mapProviderStatus("delivered"), "delivered");
  assertEquals(mapProviderStatus("undelivered"), "undelivered");
  assertEquals(mapProviderStatus("failed"), "failed");
  assertEquals(mapProviderStatus("read"), null); // ignored/logged
});

Deno.test("provider error-code mapping", () => {
  assertEquals(mapProviderErrorCode(21610), "recipient_opted_out");
  assertEquals(mapProviderErrorCode(21211), "recipient_invalid");
  assertEquals(mapProviderErrorCode(21614), "recipient_invalid");
  assertEquals(mapProviderErrorCode(30003), "recipient_unreachable");
  assertEquals(mapProviderErrorCode(30006), "recipient_landline");
  assertEquals(mapProviderErrorCode(30007), "carrier_filtered");
  assertEquals(mapProviderErrorCode(21608), "trial_recipient_unverified");
  assertEquals(mapProviderErrorCode(21408), "region_not_enabled");
  assertEquals(mapProviderErrorCode(99999), "provider_error");
  assertEquals(mapProviderErrorCode(undefined), null);
});

Deno.test("monotonic / sticky status rules", () => {
  assertEquals(canApplyStatus("queued", "sent"), true);
  assertEquals(canApplyStatus("sent", "delivered"), true);
  assertEquals(canApplyStatus("sent", "queued"), false); // never regress
  assertEquals(canApplyStatus("delivered", "failed"), false); // terminal is sticky
  assertEquals(canApplyStatus("rejected", "delivered"), false);
  assertEquals(canApplyStatus("queued", "queued"), false); // equal rank, no change
});

Deno.test("constant-time compare", () => {
  assert(constantTimeEquals("abc", "abc"));
  assert(!constantTimeEquals("abc", "abd"));
  assert(!constantTimeEquals("ab", "abc"));
});

Deno.test("Twilio signature matches the documented example vector", async () => {
  // From Twilio's security documentation: AuthToken '12345', the URL plus sorted POST params
  // produce the signature below. This locks our algorithm to Twilio's.
  const url = "https://mycompany.com/myapp.php?foo=1&bar=2";
  const params: Record<string, string> = {
    Digits: "1234",
    To: "+18005551212",
    From: "+14158675309",
    Caller: "+14158675309",
    CallSid: "CA1234567890ABCDE",
  };
  const good = "RSOYDt4T1cUTdK1PDd93/VVr8B8=";
  assert(await isValidTwilioSignature("12345", url, params, good));
  assert(!(await isValidTwilioSignature("12345", url, params, "WRONGSIG")));
});
