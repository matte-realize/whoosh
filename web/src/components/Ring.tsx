import type { CSSProperties } from "react";

export type RingTone = "green" | "blue" | "amber" | "red" | "violet";

interface RingProps {
  /** 0 to 1. Values outside are clamped. */
  value: number;
  /** Big text in the middle, already formatted (for example "92%" or "4.2 mi"). */
  display: string;
  label: string;
  /** Small line under the label, for example what the ring is compared against. */
  caption?: string;
  tone?: RingTone;
  size?: number;
}

/**
 * A ring gauge in the style of fitness wearables: a thick arc that fills to `value`, with the
 * number in the middle. The text says everything the ring shows, so nothing depends on the arc or
 * its color alone. The fill animates once (CSS), and not at all for reduced motion.
 */
export function Ring({ value, display, label, caption, tone = "green", size = 148 }: RingProps) {
  const stroke = Math.max(8, Math.round(size * 0.085));
  const radius = (size - stroke) / 2;
  const circumference = 2 * Math.PI * radius;
  const fraction = Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : 0;
  const style = {
    "--ring-c": `${circumference}`,
    "--ring-offset": `${circumference * (1 - fraction)}`,
  } as CSSProperties;

  return (
    <figure className={`ring ring--${tone}`} style={{ width: size }}>
      <div className="ring__dial" style={{ width: size, height: size }}>
        <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true" focusable="false">
          <circle className="ring__track" cx={size / 2} cy={size / 2} r={radius} strokeWidth={stroke} />
          <circle
            className="ring__fill"
            cx={size / 2}
            cy={size / 2}
            r={radius}
            strokeWidth={stroke}
            strokeDasharray={circumference}
            style={style}
          />
        </svg>
        <span className="ring__value" style={{ fontSize: Math.round(size * 0.2) }}>
          {display}
        </span>
      </div>
      <figcaption>
        <span className="ring__label">{label}</span>
        {caption ? <span className="ring__caption">{caption}</span> : null}
      </figcaption>
    </figure>
  );
}
