/**
 * The Whoosh mark: a bike wheel with three "whoosh" arcs trailing behind it, for the road behind
 * the rider. `Logo` adds the name next to it. Every copy of the mark defines the same gradient,
 * so sharing one id across the page is harmless.
 */
const gradientId = "whoosh-logo-arc";

export function LogoMark({ size = 32, title }: { size?: number; title?: string }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 64 64"
      role={title ? "img" : undefined}
      aria-hidden={title ? undefined : true}
      aria-label={title}
      focusable="false"
    >
      <defs>
        <linearGradient id={gradientId} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#3ba7ff" />
          <stop offset="1" stopColor="#2df5a8" />
        </linearGradient>
      </defs>
      <g fill="none" stroke={`url(#${gradientId})`} strokeLinecap="round" strokeWidth={4.5}>
        <path d="M10.56 49 A34 34 0 0 1 10.56 15" opacity="0.35" />
        <path d="M16.62 45.5 A27 27 0 0 1 16.62 18.5" opacity="0.65" />
        <path d="M22.68 42 A20 20 0 0 1 22.68 22" />
      </g>
      <circle cx="40" cy="32" r="12.5" fill="none" stroke="#2df5a8" strokeWidth={5} />
      <circle cx="40" cy="32" r="3.4" fill="#2df5a8" />
    </svg>
  );
}

export function Logo({ size = 32 }: { size?: number }) {
  return (
    <span className="logo">
      <LogoMark size={size} />
      <span className="logo__word">whoosh</span>
    </span>
  );
}
