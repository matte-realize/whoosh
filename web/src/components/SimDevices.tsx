"use client";

/**
 * The devices beside the 3D simulation: the rider's phone (the Whoosh ride screen and the crash
 * countdown), a paired Watch, the emergency contact's phone, and the ride's near-miss log.
 * Layout, colors and copy follow the iOS app (Whoosh/Support/Theme/Theme.swift,
 * ActiveRideView.swift) and the crash-response spec. Everything here is an illustration.
 */

import type { ReactNode } from "react";
import {
  CONTACT,
  CRASH,
  ROUTE_POINTS,
  clockTime,
  routePoint,
  type CrashPhase,
  type NearMiss,
  type PositionHint,
  type SimEvent,
} from "@/lib/sim/engine";
import { MPH_PER_MPS, METERS_PER_MILE, formatDuration } from "@/lib/units";

export interface DeviceSnapshot {
  t: number;
  recording: boolean;
  rideStartsAt: number;
  rideTime: number;
  riderDistance: number;
  riderSpeed: number;
  cue: boolean;
  lastCue: SimEvent | null;
  nearMisses: NearMiss[];
  toast: boolean;
  crash: {
    phase: CrashPhase;
    remaining: number | null;
    detectedAt: number;
    sentAt: number | null;
    endedAt: number | null;
  };
  message: string | null;
  messageTime: string | null;
}

export function hintText(hint: PositionHint | null): string {
  if (hint === null) return "behind you";
  return hint === "center" ? "directly behind" : `on your ${hint}`;
}

function miles(meters: number): string {
  return (meters / METERS_PER_MILE).toFixed(2);
}

function mph(metersPerSecond: number): string {
  return (Math.max(0, metersPerSecond) * MPH_PER_MPS).toFixed(1);
}

/** True while the "Glad you're OK" screen shows after a cancel. */
function showingCancelled(snap: DeviceSnapshot): boolean {
  return snap.crash.phase === "cancelled" && snap.crash.endedAt !== null && snap.t < snap.crash.endedAt + CRASH.getUpSeconds;
}

// ---------- Route map (follows the rider, like the app's live map) ----------

const LAT0 = ROUTE_POINTS[0][1];
const LON0 = ROUTE_POINTS[0][0];
const M_LAT = 111_132;
const M_LON = 111_320 * Math.cos((LAT0 * Math.PI) / 180);
const toXY = (lon: number, lat: number): [number, number] => [(lon - LON0) * M_LON, -(lat - LAT0) * M_LAT];

function RouteMap({ distance, nearMisses, crashed }: { distance: number; nearMisses: NearMiss[]; crashed: boolean }) {
  const span = 260; // meters shown top to bottom
  const width = span * 1.15;
  const here = routePoint(distance);
  const [cx, cy] = toXY(here.lon, here.lat);
  const viewBox = `${cx - width / 2} ${cy - span * 0.62} ${width} ${span}`;

  const all = ROUTE_POINTS.map(([lon, lat]) => toXY(lon, lat));
  const ridden: [number, number][] = [toXY(ROUTE_POINTS[0][0], ROUTE_POINTS[0][1])];
  for (let m = 6; m < distance; m += 6) {
    const p = routePoint(m);
    ridden.push(toXY(p.lon, p.lat));
  }
  ridden.push([cx, cy]);
  const path = (pts: [number, number][]) => pts.map(([x, y], i) => `${i === 0 ? "M" : "L"}${x.toFixed(1)} ${y.toFixed(1)}`).join(" ");

  // Cross streets at the route's vertices (they sit at the real intersections).
  const cross = all.slice(1, -1).map(([x, y], i) => {
    const [px, py] = all[i];
    const [nx, ny] = all[i + 2];
    const dx = nx - px;
    const dy = ny - py;
    const l = Math.hypot(dx, dy) || 1;
    const ox = (-dy / l) * 160;
    const oy = (dx / l) * 160;
    return `M${(x - ox).toFixed(1)} ${(y - oy).toFixed(1)} L${(x + ox).toFixed(1)} ${(y + oy).toFixed(1)}`;
  });

  return (
    <svg className="rider-phone__map" viewBox={viewBox} preserveAspectRatio="xMidYMid slice" aria-hidden="true">
      <rect x={cx - 2000} y={cy - 2000} width={4000} height={4000} fill="#141a22" />
      {cross.map((d) => (
        <path key={d} d={d} stroke="#1f2833" strokeWidth={7} fill="none" />
      ))}
      <path d={path(all)} stroke="#2a3542" strokeWidth={13} fill="none" strokeLinecap="round" strokeLinejoin="round" />
      <text x={all[3][0] + 14} y={all[3][1]} fill="#6b7888" fontSize={9} fontFamily="system-ui, sans-serif">
        Mass Ave
      </text>
      <path d={path(ridden)} stroke="#0b0f14" strokeWidth={9} fill="none" strokeLinecap="round" strokeLinejoin="round" />
      <path d={path(ridden)} stroke="#c8f135" strokeWidth={5} fill="none" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx={ridden[0][0]} cy={ridden[0][1]} r={6} fill="#fff" stroke="#0b0f14" strokeWidth={2.5} />
      {nearMisses.map((n) => {
        const [x, y] = toXY(n.lon, n.lat);
        const fill = n.source === "rider_reported" ? "#c8f135" : "#f5a524";
        return <rect key={n.id} x={x - 5} y={y - 5} width={10} height={10} fill={fill} stroke="#0b0f14" strokeWidth={2} transform={`rotate(45 ${x} ${y})`} />;
      })}
      <circle cx={cx} cy={cy} r={18} fill={crashed ? "#e5484d" : "#c8f135"} opacity={0.18} />
      <circle cx={cx} cy={cy} r={8} fill="#fff" />
      <circle cx={cx} cy={cy} r={5} fill={crashed ? "#e5484d" : "#c8f135"} />
    </svg>
  );
}

// ---------- Rider's phone ----------

interface RiderPhoneProps {
  snap: DeviceSnapshot;
  onStart: () => void;
  onMarkCloseCall: () => void;
  onCancelCrash: () => void;
  onSendNow: () => void;
}

export function RiderPhone({ snap, onStart, onMarkCloseCall, onCancelCrash, onSendNow }: RiderPhoneProps) {
  return (
    <div className="device rider-phone">
      <div className="rider-phone__screen">
        <div className="rider-phone__island" aria-hidden="true" />
        <PhoneStatusBar dark={snap.recording} t={snap.t} />
        {!snap.recording ? (
          <HomeScreen snap={snap} onStart={onStart} />
        ) : snap.crash.phase === "countdown" ? (
          <CountdownScreen snap={snap} onCancel={onCancelCrash} onSendNow={onSendNow} />
        ) : snap.crash.phase === "sending" || snap.crash.phase === "sent" ? (
          <AlertStatusScreen snap={snap} />
        ) : (
          <RideScreen snap={snap} onMarkCloseCall={onMarkCloseCall} />
        )}
      </div>
      <p className="device__caption">Rider&apos;s iPhone · Whoosh</p>
    </div>
  );
}

function PhoneStatusBar({ dark, t }: { dark: boolean; t: number }) {
  return (
    <div className={`status-bar${dark ? " status-bar--dark" : ""}`} aria-hidden="true">
      <span>{clockTime(t).replace(/ [AP]M$/, "")}</span>
      <span className="status-bar__icons">●●●● ▮</span>
    </div>
  );
}

function HomeScreen({ snap, onStart }: { snap: DeviceSnapshot; onStart: () => void }) {
  const pressing = snap.rideStartsAt - snap.t < 0.45 && snap.rideStartsAt > snap.t;
  return (
    <div className="home-screen">
      <div className="home-screen__header">
        <div>
          <p className="home-screen__wordmark">whoosh</p>
          <p className="home-screen__sub">Ready to ride?</p>
        </div>
        <span className="home-screen__gear" aria-hidden="true">⚙</span>
      </div>
      <div className="home-screen__card">
        <p className="home-screen__label">THIS WEEK</p>
        <p className="home-screen__big">
          12.4 <small>mi</small>
        </p>
        <p className="home-screen__sub">3 rides · 1h 02m</p>
      </div>
      <p className="home-screen__section">Recent rides</p>
      <div className="home-screen__row">
        <span className="home-screen__glyph" aria-hidden="true" />
        <div>
          <p>Thu, Oct 22 · 5:48 PM</p>
          <p className="home-screen__sub">5.32 mi · 24:18 · 13.1 mph</p>
        </div>
      </div>
      <div className="home-screen__row home-screen__row--on">
        <span aria-hidden="true">◉</span>
        <div>
          <p>Rear vehicle detection</p>
          <p className="home-screen__sub">On · experimental</p>
        </div>
      </div>
      <div className="home-screen__row home-screen__row--on">
        <span aria-hidden="true">✚</span>
        <div>
          <p>Crash alerts</p>
          <p className="home-screen__sub">On · texts {CONTACT.contactName}</p>
        </div>
      </div>
      <button type="button" className={`app-pill app-pill--lime${pressing ? " is-pressed" : ""}`} onClick={onStart}>
        ▶ Start Ride
      </button>
      <p className="app-chip app-chip--light">
        <span className="app-chip__gps" aria-hidden="true">◉</span> GPS ready
      </p>
    </div>
  );
}

function RideScreen({ snap, onMarkCloseCall }: { snap: DeviceSnapshot; onMarkCloseCall: () => void }) {
  const latest = snap.nearMisses[0];
  const cancelled = showingCancelled(snap);
  return (
    <div className="ride-screen">
      <RouteMap distance={snap.riderDistance} nearMisses={snap.nearMisses} crashed={false} />
      <div className="ride-screen__top">
        {snap.cue ? (
          <div className="app-banner app-banner--cue" role="status">
            <strong>⚠ Vehicle behind</strong>
            <span>{hintText(snap.lastCue?.hint ?? null)} · caution</span>
          </div>
        ) : cancelled ? (
          <div className="app-banner app-banner--ok" role="status">
            <strong>✓ Glad you&apos;re OK</strong>
            <span>No alert was sent.</span>
          </div>
        ) : (
          <p className="app-chip">
            <span className="app-chip__rec" aria-hidden="true" /> Recording
          </p>
        )}
        {snap.toast && latest !== undefined ? (
          <div className="app-toast" role="status">
            ◆ {latest.source === "rider_reported" ? "Close call marked" : "Near miss logged"}
            <span>{latest.source === "detected" ? ` · vehicle ${hintText(latest.hint)}` : " · saved with location"}</span>
          </div>
        ) : null}
      </div>
      <div className="ride-screen__chips">
        <p className="app-chip">
          <span className="app-chip__eye" aria-hidden="true">◉</span> Rear detection on
        </p>
        <p className="app-chip">◆ {snap.nearMisses.length}</p>
      </div>
      <div className="ride-sheet">
        <span className="ride-sheet__grabber" aria-hidden="true" />
        <p className="ride-sheet__label">RIDE TIME</p>
        <p className="ride-sheet__time">{formatDuration(snap.rideTime)}</p>
        <div className="ride-sheet__metrics">
          <div>
            <p className="ride-sheet__value">
              {miles(snap.riderDistance)} <small>mi</small>
            </p>
            <p className="ride-sheet__label">DISTANCE</p>
          </div>
          <span className="ride-sheet__divider" aria-hidden="true" />
          <div>
            <p className="ride-sheet__value">
              {snap.riderSpeed > 0.2 ? mph(snap.riderSpeed) : "—"} <small>mph</small>
            </p>
            <p className="ride-sheet__label">SPEED</p>
          </div>
        </div>
        <div className="ride-sheet__controls">
          <button type="button" className="app-pill app-pill--amber" onClick={onMarkCloseCall}>
            ◆ Mark close call
          </button>
          <span className="ride-sheet__stop" aria-hidden="true">
            <span />
            Hold
          </span>
        </div>
        <p className="ride-sheet__hint">Hold Stop to end ride</p>
      </div>
    </div>
  );
}

function CountdownScreen({ snap, onCancel, onSendNow }: { snap: DeviceSnapshot; onCancel: () => void; onSendNow: () => void }) {
  const seconds = Math.ceil(snap.crash.remaining ?? 0);
  return (
    <div className="crash-screen" role="alertdialog" aria-label="Crash detected">
      <p className="crash-screen__drill">DRILL · SIMULATED CRASH</p>
      <button type="button" className="crash-screen__send-now" onClick={onSendNow}>
        Send now
      </button>
      <p className="crash-screen__title">Crash detected</p>
      <p className="crash-screen__number" aria-live="off">
        {seconds}
      </p>
      <p className="crash-screen__text">
        Sending an alert to {CONTACT.contactName} in {seconds} {seconds === 1 ? "second" : "seconds"}.
      </p>
      <p className="crash-screen__note">
        Whoosh is not an emergency service. It can&apos;t guarantee an alert is sent or read.
      </p>
      <button type="button" className="crash-screen__ok" onClick={onCancel}>
        I&apos;m OK — Cancel
      </button>
    </div>
  );
}

function AlertStatusScreen({ snap }: { snap: DeviceSnapshot }) {
  const sent = snap.crash.phase === "sent";
  return (
    <div className="crash-screen crash-screen--status" role="status">
      <p className="crash-screen__drill">DRILL · SIMULATED CRASH</p>
      <p className="crash-screen__icon" aria-hidden="true">
        {sent ? "✓" : "…"}
      </p>
      <p className="crash-screen__title">{sent ? `Alert sent to ${CONTACT.contactName}` : `Sending to ${CONTACT.contactName}…`}</p>
      <p className="crash-screen__text">
        {sent
          ? `${CONTACT.contactName} got a text at ${snap.messageTime} with your location on Mass Ave.`
          : "Your location is attached. This takes a moment."}
      </p>
      <p className="crash-screen__note">Your ride is still recording. Hold Stop to finish.</p>
    </div>
  );
}

// ---------- Watch ----------

export function WatchMock({ snap, onCancelCrash }: { snap: DeviceSnapshot; onCancelCrash: () => void }) {
  const phase = snap.crash.phase;
  let face: ReactNode;
  let tone = "";
  if (!snap.recording) {
    face = (
      <>
        <p className="watch__brand">whoosh</p>
        <p className="watch__small">Start on iPhone</p>
      </>
    );
  } else if (phase === "countdown") {
    tone = " is-crash";
    face = (
      <>
        <p className="watch__small">Crash detected</p>
        <p className="watch__big">{Math.ceil(snap.crash.remaining ?? 0)}</p>
        <button type="button" className="watch__ok" onClick={onCancelCrash}>
          I&apos;m OK
        </button>
      </>
    );
  } else if (phase === "sending" || phase === "sent") {
    tone = " is-crash";
    face = (
      <>
        <p className="watch__big watch__big--icon">{phase === "sent" ? "✓" : "…"}</p>
        <p className="watch__small">{phase === "sent" ? `Alert sent to ${CONTACT.contactName}` : "Sending…"}</p>
      </>
    );
  } else if (snap.cue) {
    tone = " is-cue";
    face = (
      <>
        <p className="watch__tap">TAP</p>
        <p className="watch__small">Vehicle {hintText(snap.lastCue?.hint ?? null)}</p>
      </>
    );
  } else {
    face = (
      <>
        <p className="watch__rec">
          <span aria-hidden="true" /> {formatDuration(snap.rideTime)}
        </p>
        <p className="watch__metric">
          {miles(snap.riderDistance)}
          <small> mi</small>
        </p>
        <p className="watch__metric">
          {snap.riderSpeed > 0.2 ? mph(snap.riderSpeed) : "—"}
          <small> mph</small>
        </p>
      </>
    );
  }
  return (
    <div className="device">
      <div className={`watch${tone}`}>
        <span className="watch__crown" aria-hidden="true" />
        <div className="watch__face">{face}</div>
      </div>
      <p className="device__caption">Paired Watch</p>
    </div>
  );
}

// ---------- Contact's phone ----------

function linkify(text: string) {
  return text.split("\n").map((line, i) => {
    const match = line.match(/^(.*?)(https:\/\/\S+)$/);
    return (
      <span key={i} className="msg__line">
        {match ? (
          <>
            {match[1]}
            <u>{match[2]}</u>
          </>
        ) : (
          line
        )}
      </span>
    );
  });
}

export function ContactPhone({ snap }: { snap: DeviceSnapshot }) {
  const has = snap.message !== null;
  return (
    <div className="device contact-phone">
      <div className="contact-phone__screen">
        <div className="rider-phone__island" aria-hidden="true" />
        <PhoneStatusBar dark={false} t={snap.t} />
        {has ? (
          <div className="contact-phone__push" key={snap.crash.sentAt ?? 0}>
            <strong>Messages · now</strong>
            <span>WHOOSH DEMO - NOT REAL: {CONTACT.riderLabel} is demonstrating…</span>
          </div>
        ) : null}
        <div className="contact-phone__head">
          <span className="contact-phone__avatar" aria-hidden="true">W</span>
          <p>+1 (855) 555-0199</p>
        </div>
        <div className="contact-phone__thread" aria-live="polite">
          {has ? (
            <>
              <p className="contact-phone__stamp">Today {snap.messageTime}</p>
              <p className="msg">{linkify(snap.message ?? "")}</p>
            </>
          ) : (
            <p className="contact-phone__empty">
              {snap.crash.phase === "countdown"
                ? `Nothing yet. ${CONTACT.riderLabel} can still tap I'm OK.`
                : snap.crash.phase === "cancelled"
                  ? `${CONTACT.riderLabel} tapped I'm OK. No text was sent.`
                  : "No messages."}
            </p>
          )}
        </div>
      </div>
      <p className="device__caption">{CONTACT.contactName}&apos;s phone · emergency contact</p>
    </div>
  );
}

// ---------- Near-miss log ----------

export function NearMissLog({ nearMisses }: { nearMisses: NearMiss[] }) {
  return (
    <div className="nm-log">
      <h3>Near-miss log · this ride</h3>
      {nearMisses.length === 0 ? (
        <p className="note note--small">Nothing logged yet. Detected vehicles and close calls you mark show up here.</p>
      ) : (
        <ol>
          {nearMisses.map((n) => (
            <li key={n.id} className={n.source === "rider_reported" ? "is-rider" : n.falseAlarm ? "is-false" : undefined}>
              <span className="nm-log__time">{formatDuration(n.t)}</span>
              <span className="nm-log__what">
                {n.source === "rider_reported"
                  ? "Close call · marked by rider"
                  : n.falseAlarm
                    ? "Detected vehicle · false alarm (simulated mistake)"
                    : `Detected ${n.kind ?? "vehicle"} · ${hintText(n.hint)} · score ${n.score?.toFixed(2)}`}
              </span>
              <span className="nm-log__where">
                {n.lat.toFixed(5)}, {n.lon.toFixed(5)} · Mass Ave
              </span>
            </li>
          ))}
        </ol>
      )}
      <p className="note note--small">
        Stays on the phone. No video or frames are saved, and a camera can&apos;t measure passing distance.
      </p>
    </div>
  );
}
