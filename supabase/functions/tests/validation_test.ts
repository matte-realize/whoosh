// validation_test.ts — request validation matrix (contract §5.3) and NANP checks.
// Run: deno test supabase/functions/tests/validation_test.ts

import { assertEquals } from "jsr:@std/assert@1";
import { isValidNanp, type Limits, validateRequest } from "../_shared/validation.ts";

const LIMITS: Limits = {
  minSchemaVersion: 1,
  supportedTemplateVersions: [1],
  minConsentVersion: 1,
  recipientsPerRequest: 3,
};
const NOW = new Date("2026-10-24T17:42:00Z");

// deno-lint-ignore no-explicit-any
function base(): any {
  return {
    schemaVersion: 1,
    templateVersion: 1,
    crashEventId: "5b0b6f0e-2c0a-4a35-9a54-5f3a8f6f1a11",
    kind: "crash_alert",
    riderLabel: "Alex",
    detectedAt: "2026-10-24T17:41:07Z",
    utcOffsetMinutes: -240,
    delayedSeconds: 0,
    location: {
      status: "current",
      latitude: 42.36012,
      longitude: -71.05888,
      accuracyMeters: 12,
      ageSeconds: 0,
    },
    recipients: [
      { recipientRef: "c1d4a3d2-0b87-4b9b-8b4c-1f2a3b4c5d6e", e164: "+16175550123" },
    ],
    consent: { version: 1, acceptedAt: "2026-10-20T14:02:11Z" },
    appVersion: "1.0 (42)",
  };
}

// deno-lint-ignore no-explicit-any
function code(r: any): string | null {
  const e = validateRequest(r, LIMITS, NOW);
  return e ? e.code : null;
}

Deno.test("valid request passes", () => {
  assertEquals(code(base()), null);
});

Deno.test("NANP E.164 validation", () => {
  assertEquals(isValidNanp("+16175550123"), true);
  assertEquals(isValidNanp("+11175550123"), false); // area code may not start with 1
  assertEquals(isValidNanp("+1617555012"), false); // too short
  assertEquals(isValidNanp("+447700900123"), false); // non-NANP country
});

Deno.test("validation matrix", () => {
  let r = base();
  r.kind = "bogus";
  assertEquals(code(r), "invalid_request");

  r = base();
  r.riderLabel = "Bad*Char";
  assertEquals(code(r), "invalid_label");

  r = base();
  r.riderLabel = "";
  assertEquals(code(r), "invalid_label");

  r = base();
  r.schemaVersion = 0;
  assertEquals(code(r), "client_upgrade_required");

  r = base();
  r.templateVersion = 2;
  assertEquals(code(r), "unsupported_template_version");

  r = base();
  r.recipients = [];
  assertEquals(code(r), "invalid_recipient");

  r = base();
  r.recipients = [1, 2, 3, 4].map((i) => ({
    recipientRef: `00000000-0000-4000-8000-00000000000${i}`,
    e164: `+161755501${20 + i}`,
  }));
  assertEquals(code(r), "too_many_recipients");

  r = base();
  r.recipients = [
    { recipientRef: "c1d4a3d2-0b87-4b9b-8b4c-1f2a3b4c5d6e", e164: "+16175550123" },
    { recipientRef: "9e8d7c6b-5a49-4382-9170-0a1b2c3d4e5f", e164: "+16175550123" },
  ];
  assertEquals(code(r), "invalid_recipient"); // duplicate e164

  r = base();
  r.detectedAt = "2026-10-24T18:00:00Z"; // > 5 min in the future
  assertEquals(code(r), "invalid_request");

  r = base();
  r.detectedAt = "2026-10-24T16:30:00Z"; // > 60 min old for crash_alert
  assertEquals(code(r), "event_too_old");

  r = base();
  r.kind = "test";
  delete r.location;
  assertEquals(code(r), null); // test with no location is valid

  r = base();
  r.kind = "test"; // test must not carry a location
  assertEquals(code(r), "invalid_location");

  r = base();
  r.location = { status: "unavailable", latitude: 1 }; // coords must be absent
  assertEquals(code(r), "invalid_location");

  r = base();
  r.location.latitude = 42.360123; // > 5 decimals
  assertEquals(code(r), "invalid_location");

  r = base();
  r.utcOffsetMinutes = 900; // out of -720..840
  assertEquals(code(r), "invalid_request");

  r = base();
  r.delayedSeconds = 100000; // out of 0..86400
  assertEquals(code(r), "invalid_request");

  r = base();
  r.extra = 1; // unknown field
  assertEquals(code(r), "invalid_request");

  r = base();
  r.consent.version = 0; // below min consent
  assertEquals(code(r), "client_upgrade_required");
});
