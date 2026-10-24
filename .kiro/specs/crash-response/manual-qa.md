# Whoosh — Crash Response Manual QA Checklist (iPhone 14, iOS 17)

This checklist covers the device verifications that unit tests, the integration
tests, and the `build-for-testing` pass cannot prove for the **opt-in crash-
response feature** (`.kiro/specs/crash-response/`). It collects every
`_Pending device check:_` note from `tasks.md` (tasks 11, 16, 19, 20, 21, 22,
24, 26, 27) plus the resilience / accessibility / privacy flows from task 29 and
the **Tier 0 demo script** (tasks.md "Demo tiers"). Walk through it on the
primary demo device (iPhone 14) before the demo.

This feature is **off by default** and **not part of the MVP** (see the MVP list
in `ride-recording-mvp/manual-qa.md`). Tier 1 (a real SMS via the backend) is a
separate run in task 28 and is **not** covered here; Tier 0 works fully in
airplane mode with the native-composer fallback and no backend.

Legend: `[ ]` not yet verified · `[x]` verified on device.

---

## Pre-flight

- [ ] App builds and launches on the iPhone 14 with the Apple Developer signing
      team and the **Time Sensitive Notifications** capability (no provisioning
      errors; the `Config/Whoosh.entitlements` entitlement resolves).
- [ ] Full `xcodebuild test` suite passes (orchestrator runs it once).
- [ ] With crash alerts **off** (fresh install), the app behaves exactly like the
      MVP: no sign-in, no network, and **no notification permission prompt**
      (PRIV-1 / Requirement 1.5).

## Setup, contacts, and consent (tasks 11, 16, 17)

- [ ] Settings → "Crash alerts" opens the Emergency setup hub; the feature shows
      as **Off** with a plain reason.
- [ ] Add a contact via the **system contact picker** — it opens with **no
      Contacts permission prompt** (Requirement 2.1).
- [ ] Add a contact by typing a name + US/CA number; an invalid number shows an
      inline, actionable error and is not saved; a non-US/CA number is refused
      with "not supported yet".
- [ ] A fourth contact is refused with a plain cost/abuse explanation (max 3).
- [ ] Editing a contact's number resets it to **unverified**.
- [ ] Rider label is required before alerts can be enabled; the 20-char /
      restricted-charset limit holds.
- [ ] Consent screen reads the exact "what is / isn't sent", precise-location
      (not privacy-zone trimmed) notice, SMS-not-encrypted notice, STOP note, and
      the **foreground-only** limitation; the **live message preview** matches the
      golden template.
- [ ] Enabling alerts requires **both** the data-use consent and the separate
      not-a-guarantee acknowledgement.
- [ ] Enabling alerts requests **notification authorization** only here, after the
      in-app explanation; **denying** it degrades to "no backup prompt" with a
      documented note (not a dead-end).
- [ ] Revoke consent → alerts disable immediately, any queued alert is cancelled
      with a visible note, and "Delete my contacts" is offered.

## Keychain persistence (task 11 / Requirement 2.7, 2.8)

- [ ] Add a contact, delete-and-reinstall the app ⇒ **contacts are gone** (fresh-
      install purge of orphaned Keychain items).
- [ ] Lock the phone (after first unlock) ⇒ the app can still read contacts
      (`AfterFirstUnlockThisDeviceOnly`); contacts never appear in iCloud or a
      backup that leaves the device.

## Countdown feedback — audio, speech, haptics (tasks 19, 20)

- [ ] Trigger a drill (below). The countdown is **audible with the silent switch
      ON** (AVAudioSession `.playback`) and **ducks** other audio.
- [ ] A spoken prompt plays at the start; a tone plays each second in the final
      10 s; a warning **haptic** fires each second (foreground only).
- [ ] Audio is **never the only** signal — the high-contrast visual countdown and
      haptics accompany it.
- [ ] The audio session is **released** when the countdown ends or is cancelled
      (other audio returns to full volume).
- [ ] If audio/haptics fail, the **visual** countdown still runs (degrade
      silently).

## Countdown takeover (task 20 / Requirement 8, 18)

- [ ] The takeover appears **above every screen**: trigger a drill from **Home**
      and again from the **active-ride screen** — both show the full-screen
      countdown over the ride cover.
- [ ] It **cannot be swiped away** or dismissed by a system gesture; the only
      exits are **I'm OK — Cancel**, **Send now**, or expiry.
- [ ] The **"I'm OK — Cancel"** button is ≥ 80 pt, full width, in the one-handed
      thumb zone, and cancels with a **single tap**.
- [ ] The screen stays **awake** for the whole countdown.
- [ ] **Reduce Motion** on ⇒ the background is static (no pulse / no flashing);
      with it off there is at most one slow pulse per second (flashing-safe).
- [ ] **VoiceOver**: focus lands on Cancel first; the screen is modal; the number
      is announced at start, every 10 s, and each of the last 5 s.
- [ ] Contrast of the red background / white numeral passes the Accessibility
      Inspector (≥ 7:1 for the large numeral).
- [ ] **Dynamic Type**: the sentence and labels scale; the big numeral uses a
      fixed scale and does not clip.

## Status screen, composer fallback, 911, notifications (tasks 21, 26)

- [ ] After a drill expires (Tier 0, Noop notifier), the status screen shows an
      **"Alert not sent" / failed banner** and the **"Tap to text <contact> now"**
      composer fallback.
- [ ] The composer opens **pre-filled** with the exact golden message (and delay
      wording when delayed) and **never sends without the rider tapping Send**.
- [ ] On a device that can't send text (no SIM) the fallback offers **Copy
      message** and **Share** instead (`canSendText == false`).
- [ ] Per-contact status is shown as **icon + text**, never colour alone.
- [ ] **Backgrounding mid-countdown**: a **time-sensitive local notification**
      fires at the deadline even with the app backgrounded; tapping it opens the
      **status screen** (it never sends or cancels by itself).
- [ ] The manual **"Call 911"** button shows iOS's own call confirmation (do NOT
      place a real call in rehearsal); it is spatially separated from Cancel.
- [ ] **Call 911 is hidden / replaced by an inert "Demo" label for drills**
      (Requirement 17.3) — verify it never appears during a drill.

## Crash alert log and chips (task 22)

- [ ] Settings → "Crash alerts" → log lists records **most-recent-first** with
      icon + text status; a drill is labelled a demo.
- [ ] Delete one / delete all is a **real** local deletion (verified after
      relaunch).
- [ ] The small **"Crash alerts on/off" chip** appears on Home and on the ride
      screen (icon + text) when set up, and adds **no fourth number** to the ride
      screen.

## Connectivity / offline (task 24 / Requirement 12)

- [ ] **Airplane mode** on: trigger a drill and let it expire ⇒ the alert is
      **queued offline** with the "Alert not sent yet" banner, an "I'm OK — cancel
      alert" action, the composer fallback, and a local not-sent notice.
- [ ] Turn airplane mode **off** within the stale limit ⇒ (Tier 1) the alert
      retries; in **Tier 0** the composer fallback remains the path (no backend).
- [ ] Toggling airplane mode flips the connectivity state (retry trigger) without
      the monitor itself generating traffic.

## Container change (task 26 / Requirement 13.4)

- [ ] **Existing rides still load** after the SwiftData container gained the crash
      record entity (open the app with pre-existing history; History is intact).
- [ ] The full MVP ride flow (start → record → stop → summary → history) is
      **unchanged** with crash alerts both off and on.
- [ ] Launch reconciliation: force-quit during a drill countdown, relaunch ⇒ the
      app **prompts** ("Your app closed during a crash countdown — send the alert?
      / I'm OK") and **never auto-sends** (Requirement 13.5).

---

## Tier 0 demo script (judges)

Rehearse this exact sequence; it demonstrates the entire safety workflow with
**no backend**, in airplane mode.

1. [ ] Open Settings → **Crash alerts**. Add a contact ("Mom") via the picker
       (no permission prompt). Set the rider label ("Alex").
2. [ ] Open **Consent**, read the plain-language "what is / isn't sent" and the
       live message preview, accept **both** controls (data-use + not-a-guarantee).
       Grant the notification prompt.
3. [ ] Send a **test** to the contact and show the per-contact status progression
       (Tier 0: it explains testing needs a connection / backend — honest "not
       connected" fallback).
4. [ ] Turn on **Developer / demo tools**; the **"Simulate crash"** control
       appears.
5. [ ] Start a **ride** (or stay on Home for a drill). Tap **Simulate crash**.
6. [ ] The **full-screen countdown** takes over (audible with silent switch on,
       visible, haptic). Show the big **I'm OK — Cancel** and that **Call 911** is
       hidden (it's a drill).
7. [ ] **Cancel once** to show a false alarm is trivial to dismiss (nothing sent;
       log shows a cancelled drill).
8. [ ] Simulate again and **let it expire**. The status screen shows **"Alert not
       sent"** and the **"Tap to text <contact> now"** composer fallback,
       pre-filled with the exact `WHOOSH DEMO - NOT REAL` message. Open the
       composer to show it is pre-filled and **requires a tap to send** (do not
       send).
9. [ ] Open the **Crash alert log** and show the recorded drill with its status.
10. [ ] Note aloud: Whoosh is **not a guaranteed emergency service**, **cannot
        guarantee detection or delivery**, and **never contacts emergency
        services**.

---

## Resilience (task 29 / Requirement 11, 13)

- [ ] **Keychain read error** (hard to force): the feature treats it as "no
      contacts" and disarms; setup shows a plain error, no crash.
- [ ] **Persistence error on a transition** (hard to force): the countdown / send
      is never blocked by a save failure; state is kept in memory and persistence
      retried.
- [ ] **Audio-session failure**: visual + haptic continue; the countdown is
      unaffected.
- [ ] **Notification permission denied**: the backup prompt is unavailable; setup
      documents the limitation; everything else still works.
- [ ] **Session expired while offline** (Tier 1): token refresh on reconnect; a
      refused refresh degrades to the composer fallback. (Tier 0: N/A — no
      network.)
- [ ] A crash-alert failure **never affects ride recording** (start a ride,
      trigger and fail a drill, confirm recording continues).

## Accessibility (task 29 / Requirement 18)

- [ ] **VoiceOver** on every emergency screen (setup, contact editor, consent,
      test, countdown, status, log): every control has a meaningful label/trait.
- [ ] Countdown **announcements** at start, every 10 s, and the final 5 s.
- [ ] **Dynamic Type** at accessibility sizes on the setup / consent / test
      screens: text scales without clipping; the countdown numeral uses a fixed
      scale.
- [ ] **Reduce Motion** honored on the countdown (static high-contrast state).
- [ ] **Increase Contrast** / colour contrast verified with the Accessibility
      Inspector.
- [ ] Touch targets: primary emergency controls ≥ 60 pt; **I'm OK — Cancel** ≥
      80 pt.
- [ ] Every status is **icon + text**, never colour alone.

## Privacy (task 29 / Requirement 1, 16)

- [ ] With **both** ride sync and crash alerts **off**, the app makes **no network
      requests** (verify via Console/Instruments if convenient).
- [ ] Contacts live **only** in the Keychain — never in SwiftData, UserDefaults,
      logs, or a backup that leaves the device.
- [ ] No full phone number or message body appears in any log.
- [ ] Copy everywhere is honest: no claim of reliable detection, guaranteed
      delivery, that help is on the way, or that emergency services were notified;
      disclaimers use **"cannot guarantee detection or delivery"** (passes
      `scripts/privacy-check.sh`).
- [ ] Delete paths (contacts, consent, crash records) are **real** local
      deletions (confirmed after relaunch).
- [ ] No provider credential appears anywhere in the app or repo.
- [ ] No camera permission is requested by this feature.
