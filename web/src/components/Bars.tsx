import type { RingTone } from "./Ring";

export interface Bar {
  label: string;
  value: number;
  /** Shown at the end of the bar. Defaults to the value. */
  display?: string;
}

/**
 * Horizontal bars with the number written next to each one, so the chart reads as text too.
 * Bars are scaled to the largest value.
 */
export function Bars({
  bars,
  tone = "blue",
  label,
  stacked = false,
}: {
  bars: Bar[];
  tone?: RingTone;
  label: string;
  /** Put each label on its own line above the bar, for long labels such as street blocks. */
  stacked?: boolean;
}) {
  const max = Math.max(1, ...bars.map((bar) => bar.value));
  return (
    <ul className={`bars bars--${tone}${stacked ? " bars--stacked" : ""}`} aria-label={label}>
      {bars.map((bar) => (
        <li key={bar.label}>
          <span className="bars__label">{bar.label}</span>
          <span className="bars__track" aria-hidden="true">
            <span className="bars__fill" style={{ width: `${(bar.value / max) * 100}%` }} />
          </span>
          <span className="bars__value">{bar.display ?? bar.value}</span>
        </li>
      ))}
    </ul>
  );
}
