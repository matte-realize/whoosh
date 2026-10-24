"use client";

import { useCallback, useEffect, useRef, useState, type KeyboardEvent, type PointerEvent } from "react";
import {
  DETECTION,
  RIDER_X,
  SCENARIOS,
  cancelCrash,
  clockTime,
  closingSpeed,
  countdownRemaining,
  createSim,
  cueActive,
  drillMessage,
  findScenario,
  isRecording,
  markCloseCall,
  nearMissToastActive,
  nearestBehind,
  rideTime,
  sendCrashNow,
  startRide,
  step,
  timeToReach,
  triggerCrash,
  type ScenarioKey,
  type SimEvent,
  type SimState,
} from "@/lib/sim/engine";
import { DEFAULT_ORBIT, drawScene, type Orbit, type ViewMode } from "@/lib/sim/render";
import { formatDistance, formatDuration, formatSpeed } from "@/lib/units";
import { ContactPhone, NearMissLog, RiderPhone, WatchMock, hintText, type DeviceSnapshot } from "./SimDevices";

const VIEWS: { key: ViewMode; label: string; hint: string }[] = [
  { key: "orbit", label: "3D orbit", hint: "Drag, or use the arrow keys, to look around. + and − zoom." },
  { key: "overhead", label: "Overhead", hint: "Straight down on the road. The rider is the green figure." },
  { key: "phone", label: "Phone's rear camera", hint: "What the phone on the seat post sees, with the simulated detector's boxes." },
];

type ModeKey = "recording" | "nearmiss" | "crash" | "free";

const MODES: { key: ModeKey; label: string; view: ViewMode; orbit: Orbit }[] = [
  { key: "recording", label: "1 · Ride recording", view: "orbit", orbit: { ...DEFAULT_ORBIT } },
  { key: "nearmiss", label: "2 · Near-miss logging", view: "phone", orbit: { ...DEFAULT_ORBIT } },
  {
    key: "crash",
    label: "3 · Crash response",
    view: "orbit",
    orbit: { azimuth: 1.05, elevation: 0.38, radius: 20, target: { x: RIDER_X, y: 0.5, z: -2 } },
  },
  { key: "free", label: "Free ride", view: "orbit", orbit: { ...DEFAULT_ORBIT } },
];

const SPEEDS = [0.5, 1, 2];

interface Snapshot extends DeviceSnapshot {
  events: SimEvent[];
  nearest: { distance: number; closing: number; ttr: number | null; missed: boolean } | null;
}

function snapshot(state: SimState): Snapshot {
  const near = nearestBehind(state);
  const sent = state.crash.phase === "sent";
  return {
    t: state.t,
    recording: isRecording(state),
    rideStartsAt: state.rideStartsAt,
    rideTime: rideTime(state),
    riderDistance: state.riderDistance,
    riderSpeed: state.riderSpeed,
    cue: cueActive(state),
    lastCue: state.lastCue,
    nearMisses: state.nearMisses.slice(0, 8),
    toast: nearMissToastActive(state),
    crash: {
      phase: state.crash.phase,
      remaining: countdownRemaining(state),
      detectedAt: state.crash.detectedAt,
      sentAt: state.crash.sentAt,
      endedAt: state.crash.endedAt,
    },
    message: sent ? drillMessage(state) : null,
    messageTime: state.crash.sentAt !== null ? clockTime(state.crash.sentAt) : null,
    events: state.events.slice(0, 8),
    nearest:
      near === null
        ? null
        : {
            distance: Math.max(0, -(near.z + near.length / 2)),
            closing: closingSpeed(near, state.riderSpeed),
            ttr: timeToReach(near, state.riderSpeed),
            missed: near.missed,
          },
  };
}

function eventLine(event: SimEvent): string {
  const at = formatDuration(event.t);
  if (event.type === "false-alarm") return `${at} · False alarm (simulated mistake): nothing was there`;
  const where = event.hint === "center" ? "directly behind" : `on the ${event.hint}`;
  return `${at} · Caution cue · ${event.kind} ${where} · ${event.distance} m back`;
}

/** Short tones, only if the visitor turned sound on (which also unlocks audio). */
function tone(context: AudioContext, frequency: number, offsets: number[], length = 0.12): void {
  const now = context.currentTime;
  for (const offset of offsets) {
    const osc = context.createOscillator();
    const gain = context.createGain();
    osc.frequency.value = frequency;
    gain.gain.setValueAtTime(0.0001, now + offset);
    gain.gain.exponentialRampToValueAtTime(0.15, now + offset + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + offset + length);
    osc.connect(gain).connect(context.destination);
    osc.start(now + offset);
    osc.stop(now + offset + length + 0.02);
  }
}

export default function SimulationDemo() {
  const wrapRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const simRef = useRef<SimState>(createSim("recording"));
  const orbitRef = useRef<Orbit>({ ...DEFAULT_ORBIT });
  const dragRef = useRef<{ x: number; y: number } | null>(null);
  const audioRef = useRef<AudioContext | null>(null);
  const lastEventRef = useRef<SimEvent | null>(null);
  const lastBeepSecondRef = useRef<number | null>(null);
  const lastPhaseRef = useRef<string>("none");

  const [playing, setPlaying] = useState(false);
  const [reducedMotion, setReducedMotion] = useState(false);
  const [speed, setSpeed] = useState(1);
  const [view, setView] = useState<ViewMode>("orbit");
  const [mode, setMode] = useState<ModeKey>("recording");
  const [scenario, setScenario] = useState<ScenarioKey>("light");
  const [mistakes, setMistakes] = useState(false);
  const [sound, setSound] = useState(false);
  const [snap, setSnap] = useState<Snapshot>(() => snapshot(simRef.current));
  const [announcement, setAnnouncement] = useState("");

  // Mirror the controls into refs so the animation loop reads current values without restarting.
  const live = useRef({ playing, speed, view, sound });
  live.current = { playing, speed, view, sound };

  // Start playing on mount, unless the visitor asked for reduced motion.
  useEffect(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    setReducedMotion(reduce);
    setPlaying(!reduce);
  }, []);

  const reset = useCallback((key: ScenarioKey, withMistakes: boolean) => {
    simRef.current = createSim(key, withMistakes);
    lastEventRef.current = null;
    lastBeepSecondRef.current = null;
    lastPhaseRef.current = "none";
    setSnap(snapshot(simRef.current));
  }, []);

  const scenarioFor = (nextMode: ModeKey, freeScenario: ScenarioKey): ScenarioKey =>
    nextMode === "free" ? freeScenario : nextMode;

  function chooseMode(nextMode: ModeKey) {
    const info = MODES.find((item) => item.key === nextMode) ?? MODES[0];
    setMode(nextMode);
    setView(info.view);
    orbitRef.current = { ...info.orbit, target: info.orbit.target ? { ...info.orbit.target } : undefined };
    reset(scenarioFor(nextMode, scenario), mistakes);
    setPlaying(true);
  }

  /** Runs an action on the live simulation and refreshes the readouts at once. */
  function act(action: (sim: SimState) => unknown, message?: string) {
    action(simRef.current);
    setSnap(snapshot(simRef.current));
    if (message) setAnnouncement(message);
  }

  // Animation loop: simulate while playing, draw every frame, pause when offscreen or hidden.
  useEffect(() => {
    const canvas = canvasRef.current;
    const wrap = wrapRef.current;
    if (canvas === null || wrap === null) return;
    const ctx = canvas.getContext("2d");
    if (ctx === null) return;

    let frame = 0;
    let last = performance.now();
    let lastSnap = 0;
    let visible = true;
    let scale = 1;

    const resize = () => {
      scale = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.round(wrap.clientWidth * scale);
      canvas.height = Math.round(wrap.clientHeight * scale);
    };
    resize();
    const resizer = new ResizeObserver(resize);
    resizer.observe(wrap);
    const watcher = new IntersectionObserver((entries) => {
      visible = entries.some((entry) => entry.isIntersecting);
    });
    watcher.observe(wrap);

    const tick = (now: number) => {
      const dt = Math.min((now - last) / 1000, 0.1);
      last = now;
      const sim = simRef.current;
      if (visible && !document.hidden) {
        if (live.current.playing) {
          step(sim, dt * live.current.speed);
          const audio = live.current.sound ? audioRef.current : null;
          const latest = sim.events[0] ?? null;
          if (latest !== null && latest !== lastEventRef.current) {
            lastEventRef.current = latest;
            setAnnouncement(`Caution: vehicle ${hintText(latest.hint)}. Near miss logged.`);
            if (audio) tone(audio, 880, [0, 0.18]);
          }
          // Crash countdown: a tone each second in the last 10 s, and a ping when the text is sent.
          const remaining = countdownRemaining(sim);
          if (remaining !== null) {
            const second = Math.ceil(remaining);
            if (second !== lastBeepSecondRef.current) {
              lastBeepSecondRef.current = second;
              if (audio && second <= 10) tone(audio, 660, [0], 0.18);
            }
          }
          if (sim.crash.phase !== lastPhaseRef.current) {
            lastPhaseRef.current = sim.crash.phase;
            if (sim.crash.phase === "countdown") setAnnouncement("Crash detected. Sending an alert unless you tap I'm OK.");
            if (sim.crash.phase === "sent") {
              setAnnouncement("Alert sent to the emergency contact.");
              if (audio) tone(audio, 1320, [0, 0.12], 0.09);
            }
          }
        }
        drawScene(ctx, sim, live.current.view, orbitRef.current, canvas.width, canvas.height, scale);
        if (now - lastSnap > 120) {
          lastSnap = now;
          setSnap(snapshot(sim));
        }
      }
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);

    return () => {
      cancelAnimationFrame(frame);
      resizer.disconnect();
      watcher.disconnect();
    };
  }, []);

  useEffect(() => () => void audioRef.current?.close(), []);

  function toggleSound() {
    const next = !sound;
    if (next && audioRef.current === null) {
      const AudioCtor = window.AudioContext;
      if (AudioCtor) audioRef.current = new AudioCtor();
    }
    void audioRef.current?.resume();
    setSound(next);
  }

  function rotate(dAzimuth: number, dElevation: number) {
    const orbit = orbitRef.current;
    orbit.azimuth += dAzimuth;
    orbit.elevation = Math.min(1.45, Math.max(0.12, orbit.elevation + dElevation));
  }

  function zoom(factor: number) {
    const orbit = orbitRef.current;
    orbit.radius = Math.min(90, Math.max(8, orbit.radius * factor));
  }

  function onPointerDown(event: PointerEvent<HTMLCanvasElement>) {
    if (view !== "orbit") return;
    dragRef.current = { x: event.clientX, y: event.clientY };
    event.currentTarget.setPointerCapture(event.pointerId);
  }

  function onPointerMove(event: PointerEvent<HTMLCanvasElement>) {
    const drag = dragRef.current;
    if (drag === null) return;
    rotate(-(event.clientX - drag.x) * 0.008, (event.clientY - drag.y) * 0.006);
    dragRef.current = { x: event.clientX, y: event.clientY };
  }

  function onPointerUp() {
    dragRef.current = null;
  }

  function onKeyDown(event: KeyboardEvent<HTMLCanvasElement>) {
    if (view !== "orbit") return;
    const keys: Record<string, () => void> = {
      ArrowLeft: () => rotate(0.08, 0),
      ArrowRight: () => rotate(-0.08, 0),
      ArrowUp: () => rotate(0, 0.06),
      ArrowDown: () => rotate(0, -0.06),
      "+": () => zoom(0.9),
      "=": () => zoom(0.9),
      "-": () => zoom(1.1),
    };
    const action = keys[event.key];
    if (action === undefined) return;
    action();
    event.preventDefault();
  }

  const viewInfo = VIEWS.find((item) => item.key === view) ?? VIEWS[0];
  const activeScenario = findScenario(scenarioFor(mode, scenario));
  const crashBusy = snap.crash.phase === "countdown" || snap.crash.phase === "sending" || snap.crash.phase === "sent";
  const onStart = () => act(startRide, "Ride started. Recording.");
  const onMarkCloseCall = () => act(markCloseCall, "Close call marked with your location.");
  const onCancelCrash = () => act(cancelCrash, "Cancelled. No alert was sent.");
  const onSendNow = () => act(sendCrashNow, "Sending the alert now.");

  return (
    <div className="sim">
      <div className="sim__modes chips" role="group" aria-label="Demo feature">
        {MODES.map((item) => (
          <button key={item.key} type="button" className="chip" aria-pressed={mode === item.key} onClick={() => chooseMode(item.key)}>
            {item.label}
          </button>
        ))}
      </div>

      <div className="sim__stage">
        <div ref={wrapRef} className={`sim__canvas-wrap${snap.cue || snap.crash.phase === "countdown" ? " is-cue" : ""}`}>
          <canvas
            ref={canvasRef}
            className={`sim__canvas sim__canvas--${view}`}
            tabIndex={0}
            role="img"
            aria-label={`Simulation, ${viewInfo.label} view: a rider in a city bike lane with traffic. The phone, watch and log next to it describe what is happening.`}
            onPointerDown={onPointerDown}
            onPointerMove={onPointerMove}
            onPointerUp={onPointerUp}
            onPointerCancel={onPointerUp}
            onKeyDown={onKeyDown}
          />
          {!playing && snap.t === 0 ? (
            <div className="sim__overlay">
              <p>
                {reducedMotion
                  ? "Animation is paused because your system asks for reduced motion."
                  : "Simulation paused."}
              </p>
              <button type="button" className="button button--primary" onClick={() => setPlaying(true)}>
                Play simulation
              </button>
            </div>
          ) : null}
          <span className="sim__badge">Simulation · not a recording</span>
        </div>

        <p className="sim__feature-note">
          <strong>{activeScenario.label}.</strong> {activeScenario.description}
        </p>

        <div className="sim__controls">
          <div className="sim__row">
            <button type="button" className="button button--primary sim__play" onClick={() => setPlaying((p) => !p)}>
              {playing ? "❚❚ Pause" : "▶ Play"}
            </button>
            <button type="button" className="button button--ghost" onClick={() => reset(scenarioFor(mode, scenario), mistakes)}>
              ↺ Restart
            </button>
            <div className="chips" role="group" aria-label="Playback speed">
              {SPEEDS.map((value) => (
                <button key={value} type="button" className="chip" aria-pressed={speed === value} onClick={() => setSpeed(value)}>
                  {value}×
                </button>
              ))}
            </div>
          </div>

          <div className="sim__row">
            <div className="chips" role="group" aria-label="Camera view">
              {VIEWS.map((item) => (
                <button key={item.key} type="button" className="chip" aria-pressed={view === item.key} onClick={() => setView(item.key)}>
                  {item.label}
                </button>
              ))}
            </div>
            {view === "orbit" ? (
              <div className="chips" role="group" aria-label="Zoom">
                <button type="button" className="chip" aria-label="Zoom in" onClick={() => zoom(0.85)}>
                  +
                </button>
                <button type="button" className="chip" aria-label="Zoom out" onClick={() => zoom(1.15)}>
                  −
                </button>
                <button
                  type="button"
                  className="chip"
                  onClick={() => {
                    const info = MODES.find((item) => item.key === mode) ?? MODES[0];
                    orbitRef.current = { ...info.orbit, target: info.orbit.target ? { ...info.orbit.target } : undefined };
                  }}
                >
                  Reset view
                </button>
              </div>
            ) : null}
          </div>
          <p className="note note--small">{viewInfo.hint}</p>

          <div className="sim__row">
            <button type="button" className="chip" onClick={onMarkCloseCall} disabled={!snap.recording || crashBusy}>
              ◆ Mark close call
            </button>
            <button
              type="button"
              className="chip chip--danger"
              onClick={() => act(triggerCrash)}
              disabled={!snap.recording || crashBusy || snap.riderSpeed < 0.5}
            >
              ✚ Simulate crash
            </button>
            <button type="button" className="chip" aria-pressed={sound} onClick={toggleSound}>
              Sound
            </button>
          </div>

          {mode === "free" ? (
            <div className="sim__row">
              <label className="sim__select">
                <span>Traffic</span>
                <select
                  value={scenario}
                  onChange={(event) => {
                    const key = event.target.value as ScenarioKey;
                    setScenario(key);
                    reset(key, mistakes);
                  }}
                >
                  {SCENARIOS.map((item) => (
                    <option key={item.key} value={item.key}>
                      {item.label}
                    </option>
                  ))}
                </select>
              </label>
              <button
                type="button"
                className="chip"
                aria-pressed={mistakes}
                onClick={() => {
                  const next = !mistakes;
                  setMistakes(next);
                  reset(scenario, next);
                }}
              >
                Show detector mistakes
              </button>
            </div>
          ) : null}
        </div>
      </div>

      <aside className="sim__side" aria-label="The rider's devices">
        <RiderPhone snap={snap} onStart={onStart} onMarkCloseCall={onMarkCloseCall} onCancelCrash={onCancelCrash} onSendNow={onSendNow} />
        <WatchMock snap={snap} onCancelCrash={onCancelCrash} />
      </aside>

      <div className="sim__panels">
        <NearMissLog nearMisses={snap.nearMisses} />
        <ContactPhone snap={snap} />
        <div className="sim__panel-stack">
          <dl className="sim__readouts">
            <div>
              <dt>Nearest vehicle behind</dt>
              <dd>{snap.nearest === null ? "None" : formatDistance(snap.nearest.distance)}</dd>
            </div>
            <div>
              <dt>Closing speed</dt>
              <dd>{snap.nearest === null ? "—" : formatSpeed(Math.max(0, snap.nearest.closing))}</dd>
            </div>
            <div>
              <dt>Time to reach you</dt>
              <dd>{snap.nearest === null || snap.nearest.ttr === null ? "—" : `${snap.nearest.ttr.toFixed(1)} s`}</dd>
            </div>
            <div>
              <dt>Cues this run</dt>
              <dd>{snap.events.length}</dd>
            </div>
          </dl>
          <div className="sim__log">
            <h3>Caution cues</h3>
            {snap.events.length === 0 ? (
              <p className="note note--small">No cues yet.</p>
            ) : (
              <ol>
                {snap.events.map((event) => (
                  <li key={`${event.t}-${event.vehicleId ?? "fa"}`} className={event.type === "false-alarm" ? "is-false" : undefined}>
                    {eventLine(event)}
                  </li>
                ))}
              </ol>
            )}
          </div>
        </div>
      </div>

      <p className="visually-hidden" aria-live="polite">
        {announcement}
      </p>
      <p className="visually-hidden">
        Detection rules in this simulation: vehicles are tracked within {DETECTION.rangeMeters} m behind the rider,
        and a cue fires once per vehicle when it is {DETECTION.cueTimeToReachSeconds} s or {DETECTION.cueDistanceMeters} m away.
      </p>
    </div>
  );
}
