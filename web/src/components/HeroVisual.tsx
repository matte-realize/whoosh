/**
 * Illustration for the hero: a rider with a phone on the bike, a car coming up behind, and the
 * phone's "view" reaching back. Pure SVG and CSS; the motion stops for reduced-motion users.
 */
export function HeroVisual() {
  return (
    <figure className="hero-visual">
      <svg
        viewBox="0 0 480 300"
        role="img"
        aria-label="Illustration: a phone mounted on a bike watches a car approaching from behind."
      >
        <defs>
          <linearGradient id="road" x1="0" x2="1">
            <stop offset="0" style={{ stopColor: "var(--road-a)" }} />
            <stop offset="1" style={{ stopColor: "var(--road-b)" }} />
          </linearGradient>
        </defs>

        <rect x="0" y="150" width="480" height="110" rx="14" fill="url(#road)" />
        <line x1="10" y1="205" x2="470" y2="205" className="hero-visual__lane" />

        {/* The phone's view, reaching back toward the car */}
        <g className="hero-visual__waves">
          <path d="M318 196 q-26 -30 0 -60" />
          <path d="M296 206 q-44 -50 0 -100" />
          <path d="M274 216 q-62 -70 0 -140" />
        </g>

        {/* Car, behind the rider */}
        <g className="hero-visual__car">
          <rect x="40" y="168" width="120" height="44" rx="12" />
          <rect x="62" y="152" width="72" height="26" rx="9" className="hero-visual__car-top" />
          <circle cx="70" cy="214" r="11" className="hero-visual__tire" />
          <circle cx="132" cy="214" r="11" className="hero-visual__tire" />
          <rect x="152" y="180" width="8" height="10" rx="2" className="hero-visual__light" />
        </g>

        {/* Rider */}
        <g className="hero-visual__bike">
          <circle cx="340" cy="222" r="22" />
          <circle cx="420" cy="222" r="22" />
          <path d="M340 222 l28 -40 h34 l18 40 M368 182 l18 40 M362 172 h14 M402 182 l-4 -14 h12" />
          <circle cx="384" cy="132" r="10" className="hero-visual__head" />
          <path d="M384 142 l-6 32 l20 10 M380 156 l22 12" />
          <rect x="324" y="186" width="10" height="18" rx="2" className="hero-visual__phone" />
        </g>
      </svg>
      <figcaption className="visually-hidden">
        The phone on the bike looks backward. Detection is experimental.
      </figcaption>
    </figure>
  );
}
