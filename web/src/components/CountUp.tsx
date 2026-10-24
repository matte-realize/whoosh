"use client";

import { useEffect, useState } from "react";

interface CountUpProps {
  value: number;
  format: (n: number) => string;
  durationMs?: number;
}

/**
 * Animates a number from 0 up to `value`. Screen readers get the final value only (the moving
 * digits are hidden from them), and people who ask for reduced motion see the final value at once.
 */
export function CountUp({ value, format, durationMs = 900 }: CountUpProps) {
  const [shown, setShown] = useState(value);

  useEffect(() => {
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduceMotion || !Number.isFinite(value) || value <= 0) {
      setShown(value);
      return;
    }
    let frame = 0;
    const start = performance.now();
    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / durationMs);
      const eased = 1 - Math.pow(1 - t, 3);
      setShown(value * eased);
      if (t < 1) frame = requestAnimationFrame(tick);
    };
    setShown(0);
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [value, durationMs]);

  return (
    <span>
      <span className="visually-hidden">{format(value)}</span>
      <span aria-hidden="true">{format(shown)}</span>
    </span>
  );
}
