// message_test.ts — golden-case parity with crash-alert-contract.md Appendix A (G1-G9 and the
// A.3 sub-rule cases). The expected strings are copied verbatim from the contract and are the
// single source of truth for both the backend renderer and the iOS CrashMessageBuilder.
//
// Run: deno test supabase/functions/tests/message_test.ts

import { assertEquals } from "jsr:@std/assert@1";
import {
  formatAge,
  formatLocalTime,
  formatOffset,
  renderMessage,
  sanitizeLabel,
  segmentCount,
} from "../_shared/message.ts";

// --- Golden cases G1-G9 -----------------------------------------------------

Deno.test("G1 crash_alert current fix", () => {
  const { body, segments } = renderMessage({
    kind: "crash_alert",
    riderLabel: "Alex",
    detectedAt: "2026-10-24T17:41:07Z",
    utcOffsetMinutes: -240,
    delayedSeconds: 0,
    location: { status: "current", latitude: 42.36012, longitude: -71.05888, accuracyMeters: 12, ageSeconds: 0 },
  });
  const expected = [
    "WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.",
    "Time: Sat Oct 24, 1:41 PM (UTC-4)",
    "Location (+/-12 m):",
    "Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider",
    "Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888",
    "Please try to reach them. If you can't, consider calling emergency services.",
    "Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.",
  ].join("\n");
  assertEquals(body, expected);
  assertEquals(body.length, 465);
  assertEquals(segments, 4);
});

Deno.test("G2 crash_alert last known", () => {
  const { body, segments } = renderMessage({
    kind: "crash_alert",
    riderLabel: "Alex",
    detectedAt: "2026-10-24T17:41:07Z",
    utcOffsetMinutes: -240,
    delayedSeconds: 0,
    location: { status: "last_known", latitude: 42.36012, longitude: -71.05888, accuracyMeters: 30, ageSeconds: 45 },
  });
  const expected = [
    "WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.",
    "Time: Sat Oct 24, 1:41 PM (UTC-4)",
    "Last known location (45 s old, +/-30 m):",
    "Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider",
    "Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888",
    "Please try to reach them. If you can't, consider calling emergency services.",
    "Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.",
  ].join("\n");
  assertEquals(body, expected);
  assertEquals(body.length, 486);
  assertEquals(segments, 4);
});

Deno.test("G3 crash_alert location unavailable", () => {
  const { body, segments } = renderMessage({
    kind: "crash_alert",
    riderLabel: "Alex",
    detectedAt: "2026-10-24T17:41:07Z",
    utcOffsetMinutes: -240,
    delayedSeconds: 0,
    location: { status: "unavailable" },
  });
  const expected = [
    "WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.",
    "Time: Sat Oct 24, 1:41 PM (UTC-4)",
    "Location unavailable.",
    "Please try to reach them. If you can't, consider calling emergency services.",
    "Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.",
  ].join("\n");
  assertEquals(body, expected);
  assertEquals(body.length, 321);
  assertEquals(segments, 3);
});

Deno.test("G4 crash_alert delayed", () => {
  const { body, segments } = renderMessage({
    kind: "crash_alert",
    riderLabel: "Alex",
    detectedAt: "2026-10-24T17:41:07Z",
    utcOffsetMinutes: -240,
    delayedSeconds: 1020,
    location: { status: "last_known", latitude: 42.36012, longitude: -71.05888, accuracyMeters: 30, ageSeconds: 45 },
  });
  const expected = [
    "WHOOSH ALERT: Alex may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.",
    "Time: Sat Oct 24, 1:41 PM (UTC-4). Message delayed by 17 min.",
    "Last known location (45 s old, +/-30 m):",
    "Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider",
    "Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888",
    "Please try to reach them. If you can't, consider calling emergency services.",
    "Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.",
  ].join("\n");
  assertEquals(body, expected);
  assertEquals(body.length, 514);
  assertEquals(segments, 4);
});

Deno.test("G5 worst case", () => {
  const { body, segments } = renderMessage({
    kind: "crash_alert",
    riderLabel: "Abcdefghij Klmnopqrs",
    detectedAt: "2026-12-28T18:29:00Z",
    utcOffsetMinutes: 330,
    delayedSeconds: 1740,
    location: { status: "last_known", latitude: -42.36012, longitude: -171.05888, accuracyMeters: 499, ageSeconds: 540 },
  });
  const expected = [
    "WHOOSH ALERT: Abcdefghij Klmnopqrs may have crashed while cycling. A crash was detected but an injury has NOT been confirmed.",
    "Time: Mon Dec 28, 11:59 PM (UTC+5:30). Message delayed by 29 min.",
    "Last known location (9 min old, +/-499 m):",
    "Apple Maps: https://maps.apple.com/?ll=-42.36012,-171.05888&q=Rider",
    "Google Maps: https://www.google.com/maps/search/?api=1&query=-42.36012,-171.05888",
    "Please try to reach them. If you can't, consider calling emergency services.",
    "Sent automatically by Whoosh, not an emergency service. Reply STOP to opt out.",
  ].join("\n");
  assertEquals(body, expected);
  assertEquals(body.length, 540);
  assertEquals(segments, 4);
});

Deno.test("G6 drill", () => {
  const { body, segments } = renderMessage({
    kind: "drill",
    riderLabel: "Alex",
    detectedAt: "2026-10-24T17:41:07Z",
    utcOffsetMinutes: -240,
    delayedSeconds: 0,
    location: { status: "current", latitude: 42.36012, longitude: -71.05888, accuracyMeters: 12, ageSeconds: 0 },
  });
  const expected = [
    "WHOOSH DEMO - NOT REAL: Alex is demonstrating Whoosh crash alerts. No crash happened.",
    "Time: Sat Oct 24, 1:41 PM (UTC-4)",
    "Location (+/-12 m):",
    "Apple Maps: https://maps.apple.com/?ll=42.36012,-71.05888&q=Rider",
    "Google Maps: https://www.google.com/maps/search/?api=1&query=42.36012,-71.05888",
    "Sent by Whoosh, not an emergency service. Reply STOP to opt out.",
  ].join("\n");
  assertEquals(body, expected);
  assertEquals(body.length, 350);
  assertEquals(segments, 3);
});

Deno.test("G7 test", () => {
  const { body, segments } = renderMessage({
    kind: "test",
    riderLabel: "Alex",
    detectedAt: "2026-10-24T17:41:07Z",
    utcOffsetMinutes: -240,
    delayedSeconds: 0,
  });
  const expected =
    "WHOOSH TEST: This is a test message from Alex. No crash happened. A real alert would include the time and location. Sent by Whoosh, not an emergency service. Reply STOP to opt out.";
  assertEquals(body, expected);
  assertEquals(body.length, 180);
  assertEquals(segments, 2);
});

Deno.test("G8 intro", () => {
  const { body, segments } = renderMessage({
    kind: "intro",
    riderLabel: "Alex",
    detectedAt: "2026-10-24T17:41:07Z",
    utcOffsetMinutes: -240,
    delayedSeconds: 0,
  });
  const expected =
    "WHOOSH: Alex added you as an emergency contact in the Whoosh cycling app. If their phone detects a possible crash, you may get a text like this. Nothing to do now. Reply STOP to opt out.";
  assertEquals(body, expected);
  assertEquals(body.length, 186);
  assertEquals(segments, 2);
});

Deno.test("G9 all_clear", () => {
  const { body, segments } = renderMessage({
    kind: "all_clear",
    riderLabel: "Alex",
    detectedAt: "2026-10-24T17:41:07Z",
    utcOffsetMinutes: -240,
    delayedSeconds: 0,
  });
  const expected =
    "WHOOSH UPDATE: Alex says they are OK. Please ignore the crash alert sent at Sat Oct 24, 1:41 PM (UTC-4). Sent by Whoosh, not an emergency service. Reply STOP to opt out.";
  assertEquals(body, expected);
  assertEquals(body.length, 169);
  assertEquals(segments, 2);
});

// --- A.3 sub-rule cases -----------------------------------------------------

Deno.test("A.3 offset formatting", () => {
  assertEquals(formatOffset(-570), "UTC-9:30");
  assertEquals(formatOffset(-240), "UTC-4");
  assertEquals(formatOffset(0), "UTC+0");
  assertEquals(formatOffset(330), "UTC+5:30");
  assertEquals(formatOffset(345), "UTC+5:45");
});

Deno.test("A.3 age formatting (>= 11 s)", () => {
  // <= 10 s renders as "current" header, exercised in the render tests. Here check the
  // formatAge helper for the values that produce an age string.
  assertEquals(formatAge(11), "11 s old");
  assertEquals(formatAge(59), "59 s old");
  assertEquals(formatAge(60), "1 min old");
  assertEquals(formatAge(119), "1 min old");
  assertEquals(formatAge(3599), "59 min old");
  assertEquals(formatAge(3600), "1 h old");
});

Deno.test("A.3 delay clause thresholds", () => {
  const base = {
    kind: "crash_alert" as const,
    riderLabel: "Alex",
    detectedAt: "2026-10-24T17:41:07Z",
    utcOffsetMinutes: -240,
    location: { status: "unavailable" as const },
  };
  const timeLineOf = (delayedSeconds: number) =>
    renderMessage({ ...base, delayedSeconds }).body.split("\n")[1];
  assertEquals(timeLineOf(0), "Time: Sat Oct 24, 1:41 PM (UTC-4)");
  assertEquals(timeLineOf(59), "Time: Sat Oct 24, 1:41 PM (UTC-4)");
  assertEquals(timeLineOf(60), "Time: Sat Oct 24, 1:41 PM (UTC-4). Message delayed by 1 min.");
  assertEquals(timeLineOf(119), "Time: Sat Oct 24, 1:41 PM (UTC-4). Message delayed by 1 min.");
  assertEquals(timeLineOf(120), "Time: Sat Oct 24, 1:41 PM (UTC-4). Message delayed by 2 min.");
});

Deno.test("A.3 label sanitization strips/transliterates non-GSM-7 and collapses whitespace", () => {
  // "Álex ”A”" -> transliterate Á to A, smart quotes to straight quotes, collapse spaces.
  assertEquals(sanitizeLabel("\u00C1lex  \u201DA\u201D"), 'Alex "A"');
  assertEquals(sanitizeLabel("  Alex  "), "Alex");
  // Clamp to 20 chars.
  assertEquals(sanitizeLabel("Abcdefghij Klmnopqrstuvwxyz"), "Abcdefghij Klmnopqrs");
});

Deno.test("segment rule boundaries", () => {
  assertEquals(segmentCount("x".repeat(160)), 1);
  assertEquals(segmentCount("x".repeat(161)), 2);
  assertEquals(segmentCount("x".repeat(306)), 2);
  assertEquals(segmentCount("x".repeat(307)), 3);
});

Deno.test("local time 12h clock midnight/noon", () => {
  assertEquals(formatLocalTime("2026-10-24T00:00:00Z", 0), "Sat Oct 24, 12:00 AM");
  assertEquals(formatLocalTime("2026-10-24T12:00:00Z", 0), "Sat Oct 24, 12:00 PM");
});
