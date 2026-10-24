"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { FILM_SCENARIO, RIDER_X, createSim, step, type SimState } from "@/lib/sim/engine";
import { drawScene, type Orbit, type ViewMode } from "@/lib/sim/render";
import { LogoMark } from "./Logo";

/**
 * A 16-second film rendered live from the simulation (no video file): it plays like a video,
 * stays sharp at any size, and uses the same 3D scene as /simulation. The ride is scripted
 * (FILM_SCENARIO), and scripts/sim-check.ts pins the moments the shots are cut to.
 */

const DURATION = 16;
const FADE = 0.35;

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

interface Shot {
  from: number;
  to: number;
  view: ViewMode;
  orbit: (progress: number) => Orbit;
}

const SHOTS: Shot[] = [
  // Wide opening on the street.
  { from: 0, to: 3.5, view: "orbit", orbit: (p) => ({ azimuth: lerp(1.15, 0.8, p), elevation: lerp(0.56, 0.4, p), radius: lerp(78, 52, p) }) },
  // In front of the rider, looking back: the car comes into range.
  { from: 3.5, to: 7.5, view: "orbit", orbit: (p) => ({ azimuth: lerp(0.75, 0.5, p), elevation: lerp(0.32, 0.24, p), radius: lerp(46, 34, p) }) },
  // Through the phone's rear camera: the detector box, then the heads-up.
  { from: 7.5, to: 10.5, view: "phone", orbit: () => ({ azimuth: 0, elevation: 0, radius: 1 }) },
  // From the sidewalk, close on the rider, as the car goes by behind them.
  {
    from: 10.5,
    to: 13.5,
    view: "orbit",
    orbit: (p) => ({
      azimuth: lerp(1.25, 1.0, p),
      elevation: 0.2,
      radius: lerp(14, 12, p),
      target: { x: RIDER_X - 1, y: 0.9, z: -2 },
    }),
  },
  // End card over a slow drift.
  { from: 13.5, to: DURATION, view: "orbit", orbit: (p) => ({ azimuth: lerp(0.8, 0.95, p), elevation: 0.62, radius: 72 }) },
];

interface Caption {
  from: number;
  to: number;
  text: string;
  tone?: "alert";
}

const CAPTIONS: Caption[] = [
  { from: 3.7, to: 7.4, text: "A car is coming up behind you." },
  { from: 7.6, to: 8.95, text: "Whoosh keeps watch through your phone's back camera." },
  { from: 9.0, to: 10.4, text: "Heads-up: car on your left.", tone: "alert" },
  { from: 10.6, to: 13.4, text: "You feel a tap and keep your eyes on the road ahead." },
];

const TITLE = { from: 0.3, to: 3.35 };
const END = { from: 13.6, to: DURATION };
const TAP = { from: 9.0, to: 11.6 };

const inRange = (t: number, range: { from: number; to: number }) => t >= range.from && t < range.to;

function shotAt(t: number): Shot {
  return SHOTS.find((shot) => t >= shot.from && t < shot.to) ?? SHOTS[SHOTS.length - 1];
}

/** Black fade in and out at each cut, 0 to 1. */
function fadeAt(t: number, shot: Shot): number {
  const fromStart = t - shot.from;
  const toEnd = shot.to - t;
  const edge = Math.min(fromStart, toEnd);
  return edge >= FADE ? 0 : 1 - edge / FADE;
}

export default function IntroFilm() {
  const wrapRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const simRef = useRef<SimState>(createSim(FILM_SCENARIO));
  const [playing, setPlaying] = useState(false);
  const [started, setStarted] = useState(false);
  const [time, setTime] = useState(0);
  const playingRef = useRef(playing);
  playingRef.current = playing;

  // Autoplay (silent, like a muted video), unless the visitor asked for reduced motion.
  useEffect(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (!reduce) {
      setPlaying(true);
      setStarted(true);
    }
  }, []);

  useEffect(() => {
    const canvas = canvasRef.current;
    const wrap = wrapRef.current;
    if (canvas === null || wrap === null) return;
    const ctx = canvas.getContext("2d");
    if (ctx === null) return;

    let frame = 0;
    let last = performance.now();
    let lastUi = 0;
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
      let sim = simRef.current;
      if (visible && !document.hidden) {
        if (playingRef.current) {
          step(sim, dt);
          if (sim.t >= DURATION) {
            sim = createSim(FILM_SCENARIO);
            simRef.current = sim;
          }
        }
        const shot = shotAt(sim.t);
        const progress = (sim.t - shot.from) / (shot.to - shot.from);
        drawScene(ctx, sim, shot.view, shot.orbit(progress), canvas.width, canvas.height, scale);
        const fade = fadeAt(sim.t, shot);
        const dim = inRange(sim.t, TITLE) || inRange(sim.t, END) ? 0.45 : 0;
        const alpha = Math.max(fade, dim);
        if (alpha > 0) {
          ctx.fillStyle = `rgb(6 7 8 / ${Math.round(alpha * 100)}%)`;
          ctx.fillRect(0, 0, canvas.width, canvas.height);
        }
        if (now - lastUi > 90) {
          lastUi = now;
          setTime(sim.t);
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

  function replay() {
    simRef.current = createSim(FILM_SCENARIO);
    setTime(0);
    setPlaying(true);
    setStarted(true);
  }

  const caption = CAPTIONS.find((item) => inRange(time, item));
  const showTitle = started && inRange(time, TITLE);
  const showEnd = inRange(time, END);
  const showTap = inRange(time, TAP);

  return (
    <figure className="film">
      <div ref={wrapRef} className="film__frame">
        <canvas ref={canvasRef} className="film__canvas" aria-hidden="true" />

        {showTitle ? (
          <div className="film__title">
            <LogoMark size={64} />
            <p>Meet Whoosh</p>
          </div>
        ) : null}

        {showEnd ? (
          <div className="film__end">
            <LogoMark size={72} />
            <p className="film__end-line">A heads-up for what&apos;s behind you.</p>
            <Link href="/simulation" className="button button--primary">
              Try the simulation <span aria-hidden="true">→</span>
            </Link>
          </div>
        ) : null}

        {caption !== undefined ? (
          <p className={`film__caption${caption.tone === "alert" ? " film__caption--alert" : ""}`} key={caption.text}>
            {caption.tone === "alert" ? <span aria-hidden="true">⚠ </span> : null}
            {caption.text}
          </p>
        ) : null}

        <div className={`film__watch${showTap ? " is-on" : ""}`} aria-hidden="true">
          <span>TAP</span>
        </div>

        {!started ? (
          <div className="film__start">
            <button type="button" className="film__big-play" onClick={replay} aria-label="Play the 16-second film">
              <span aria-hidden="true">▶</span>
            </button>
            <p>Play the 16-second film</p>
          </div>
        ) : null}

        <div className="film__bar">
          <button
            type="button"
            className="film__control"
            onClick={() => {
              setStarted(true);
              setPlaying((value) => !value);
            }}
            aria-label={playing ? "Pause the film" : "Play the film"}
          >
            <span aria-hidden="true">{playing ? "❚❚" : "▶"}</span>
          </button>
          <button type="button" className="film__control" onClick={replay} aria-label="Restart the film">
            <span aria-hidden="true">↺</span>
          </button>
          <div className="film__progress" aria-hidden="true">
            <span style={{ width: `${Math.min(100, (time / DURATION) * 100)}%` }} />
          </div>
          <span className="film__tag">Simulated ride</span>
        </div>
      </div>
      <figcaption className="film__description">
        A 16-second simulated ride: a car comes up behind a cyclist on a city street, Whoosh spots it
        through the phone&apos;s back camera, and the rider gets a heads-up that the car is on their left.
        This is an illustration, not a recording.
      </figcaption>
    </figure>
  );
}
