# Proposal: "Share publicly" for synced rides (for the iOS owner)

Status: PROPOSAL from Role C, October 24, 2026. Nothing in `.kiro/specs/ride-recording-mvp/` has
been edited. If you accept it, the exact text to paste is in sections 2–4.

## 1. Why this is needed

The backend already has the pieces:
- `rides.share_publicly boolean not null default false`
- the `public_rides` view, which shows only rides where `share_publicly = true`, to the website

The iOS spec (Requirement 12, tasks 21–23) has only a sync toggle. Nothing sets
`share_publicly`, so every synced ride stays private and the website shows nothing from a real
phone. The backend needs no change for this proposal.

Keeping sharing separate from sync is deliberate. Sync means "my rides are backed up under my
anonymous account, and only I can read them". Sharing means "anyone who opens the website can
see this ride". Those are different promises and need separate, explicit consent.

## 2. Proposed behavior (decisions marked)

- **Per ride, default off.** Each ride has its own Share switch on its summary screen (and its
  history detail). New rides are never shared automatically.
  *Alternative:* one global "share new rides" setting. Simpler to build, but it shares rides
  the rider has not looked at. Not recommended.
- **Only when sync is on.** The switch is hidden or disabled with an explanation while sync is
  off, because sharing needs the ride to be uploaded.
- **Not retroactive.** Turning sync on does not share old rides.
- **Confirmation on first share.** A short plain-language prompt each time (see copy below).
- **Unshare is possible at any time** and removes the ride from the website's list on the next
  load. Deleting a ride removes it entirely (already in Requirement 12.6).
- **Turning sync off while rides are shared:** see the conflict in section 5. Proposed: prompt
  the rider before disabling.

## 3. Proposed requirement text (append to Requirement 12)

Matches the existing numbering (12.1–12.10).

11. Public sharing SHALL be a setting separate from cloud sync. Every ride SHALL be private by
    default, and sharing SHALL be available only while cloud sync is enabled.
12. WHEN the user turns on sharing for a ride THEN the system SHALL first state in plain text
    what becomes visible on the public website (the trimmed route, distance, time, and average
    speed; no name or account) and SHALL require explicit confirmation before uploading the
    ride with `share_publicly = true`.
13. WHEN the user turns sharing off for a ride THEN the system SHALL set `share_publicly =
    false` for that ride remotely, retrying if offline, and SHALL show the ride as pending
    until the remote value matches.
14. Each ride's sharing state (private or shared) SHALL be shown with an icon and text, not
    color alone, on the summary and in history.
15. Every upload SHALL send an explicit `share_publicly` value, which SHALL be `false` unless
    the user has turned sharing on for that ride.
16. WHEN the user turns cloud sync off while any ride is still shared THEN the system SHALL
    tell the user those rides remain public and SHALL offer to stop sharing them before
    sync is disabled.

Traceability: the privacy steering line "Public website data must be deliberate" and the
contract's `share_publicly` description.

## 4. Proposed design and task changes

**Design (`RideSyncService` section)**
- `RideRecord` gains `sharePublicly: Bool = false`.
- The upload payload includes `share_publicly`, and the field mapping follows
  `supabase-contract.md`.
- Add to the protocol: `func setSharing(id: UUID, shared: Bool) async throws` (an update of one
  column on the remote row, idempotent).
- `SyncCoordinator` treats a changed `sharePublicly` like any other pending change: retry on
  app foreground, no duplicates, never runs while sync is off, and never touches the ride
  state machine.

**Tasks**
- **Task 21:** add `sharePublicly` to the record and to the `Ride` upload model, and extend
  the `NoopRideSyncService` and fake with `setSharing`.
- **Task 22:** coordinator tests (below).
- **Task 23:** the Share switch, the confirmation prompt, the state label, and the
  disable-sync prompt (12.16). Verify on device: with sync and sharing on, the ride appears on
  the website; switching it off removes it; another anonymous user still cannot read the raw
  row.

**Unit tests (Swift Testing, with the fake `RideSyncService`)**
- New rides default to `sharePublicly == false`, and the upload payload carries `false`.
- Sharing is rejected (or the switch is unavailable) while sync is disabled.
- Turning sharing on uploads once with `true`; turning it off sends `setSharing(false)`.
- Offline: share changes stay pending and retry on foreground without duplicates.
- Sharing a ride never changes the local route, and the uploaded route is trimmed.
- Disabling sync with shared rides triggers the prompt path (12.16).

## 5. A conflict to resolve in the current spec

Requirement 9.2 says that WHILE cloud sync is disabled the app makes no network requests.
Two things need a network request when sync is off:
- Remote deletion (12.6) for a ride that was synced earlier, if the user later turned sync off.
- Unsharing a ride (this proposal) when the user turns sync off.

Proposed resolution: user-initiated deletes and unshares are the one exception. They run at
the moment the user asks, show an error they can retry if offline, and are never triggered in
the background while sync is off. Add one sentence to 9.2 and 12.6 saying so. Without this,
rides could stay public or stay in the cloud after the user has asked for them to go.

## 6. Draft screen copy

Honest-copy rules apply: say exactly what is shared and nothing about safety.

- **Switch label:** "Share this ride on the Whoosh website"
- **Subtitle when sync is off:** "Turn on cloud sync in Settings to share rides."
- **Confirmation title:** "Share this ride publicly?"
- **Confirmation body:** "Anyone who opens the Whoosh website will be able to see this ride's
  route, distance, time, and average speed. The first and last 0.1 miles of the route are
  left out. Your name and account are not shown. You can stop sharing at any time."
- **Buttons:** "Share ride" and "Cancel"
- **State labels:** "Private" with a lock icon, "Shared" with a globe icon, "Sharing pending"
  with a clock icon
- **Disable-sync prompt:** "[N] rides are shared publicly. Turning off sync does not remove
  them. Stop sharing them first?" with "Stop sharing and turn off", "Keep sharing and turn
  off", and "Cancel"

Check the "anyone who opens the website" line against how the site is actually hosted. If the
site is only on a local machine for the demo, the line is still the safe wording.

## 7. Backend follow-ups on Role C's side

- RLS test that a user can flip their own `share_publicly`, that the ride then appears or
  disappears in `public_rides` for `anon`, and that another user cannot flip it: written
  (assertions 30–34 in `supabase/tests/rls_rides.test.sql`), passing locally.
- Re-check the `public_rides` owner-rights view question in `supabase-contract.md` once real
  rides are shared.

## 8. Decisions needed from the iOS owner

1. Per-ride switch (recommended) or a global setting?
2. Accept the 9.2 / 12.6 exception for user-initiated deletes and unshares?
3. Is the disable-sync prompt (12.16) in scope for the hackathon, or documented as a known
   gap? If it is a gap, say so in the app's privacy copy.
