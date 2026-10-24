/**
 * Hero illustration: a city street at dusk, a rider with a phone under the saddle, a car coming
 * up behind, and the phone's view reaching back toward it. Pure SVG. Colors live on the shapes
 * (so the drawing is self-contained); CSS in globals.css only adds motion: the wheels spin, the
 * lane markings scroll, the car closes in, and a heads-up appears as it gets near. All motion
 * stops for reduced-motion users.
 */

const INK = "#e8ecef";
const GREEN = "#2df5a8";
const RED = "#ff5a4f";

function Wheel({ cx, cy }: { cx: number; cy: number }) {
  const spokes = Array.from({ length: 8 }, (_, i) => (i * Math.PI) / 8);
  return (
    <g>
      <circle cx={cx} cy={cy} r={27} fill="none" stroke={INK} strokeWidth={4.5} />
      <circle cx={cx} cy={cy} r={23} fill="none" stroke="#5b636b" strokeWidth={1.5} />
      <g className="hv-spokes" style={{ transformOrigin: `${cx}px ${cy}px` }} stroke="#8a939b" strokeWidth={1}>
        {spokes.map((angle) => (
          <line
            key={angle}
            x1={cx - Math.cos(angle) * 22}
            y1={cy - Math.sin(angle) * 22}
            x2={cx + Math.cos(angle) * 22}
            y2={cy + Math.sin(angle) * 22}
          />
        ))}
      </g>
      <circle cx={cx} cy={cy} r={3} fill={INK} />
    </g>
  );
}

function CarWheel({ cx, cy }: { cx: number; cy: number }) {
  return (
    <g>
      <circle cx={cx} cy={cy} r={13} fill="#0b0c0d" stroke="#2a2e32" strokeWidth={2} />
      <circle cx={cx} cy={cy} r={6.5} fill="#8a939b" />
    </g>
  );
}

// Skyline blocks: x, width, height.
const SKYLINE: [number, number, number][] = [
  [0, 38, 70], [40, 26, 104], [68, 44, 82], [114, 30, 126], [146, 52, 92], [200, 34, 140],
  [236, 46, 100], [284, 28, 118], [314, 58, 86], [374, 34, 132], [410, 40, 96], [452, 28, 112],
];

const WINDOWS: [number, number][] = [
  [58, 150], [62, 162], [130, 140], [214, 128], [222, 142], [300, 156], [388, 140], [392, 154], [430, 166],
];

export function HeroVisual() {
  return (
    <figure className="hero-visual">
      <svg
        viewBox="0 0 480 320"
        role="img"
        aria-label="Illustration: a cyclist with a phone under the saddle. The phone looks back at a car approaching from behind, and a heads-up appears."
      >
        <defs>
          <linearGradient id="hv-sky" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#05070a" />
            <stop offset="1" stopColor="#0f1d1a" />
          </linearGradient>
          <linearGradient id="hv-road" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#1c2024" />
            <stop offset="1" stopColor="#101214" />
          </linearGradient>
          <linearGradient id="hv-beam" x1="1" y1="0" x2="0" y2="0">
            <stop offset="0" stopColor={GREEN} stopOpacity="0.02" />
            <stop offset="0.3" stopColor={GREEN} stopOpacity="0.16" />
            <stop offset="1" stopColor={GREEN} stopOpacity="0.02" />
          </linearGradient>
          <linearGradient id="hv-headlight" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0" stopColor="#fff3c4" stopOpacity="0.45" />
            <stop offset="1" stopColor="#fff3c4" stopOpacity="0" />
          </linearGradient>
          <linearGradient id="hv-car" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#ff6a5f" />
            <stop offset="1" stopColor="#c7372d" />
          </linearGradient>
          <clipPath id="hv-frame">
            <rect x="0" y="0" width="480" height="320" rx="18" />
          </clipPath>
        </defs>

        <g clipPath="url(#hv-frame)">
          <rect x="0" y="0" width="480" height="320" fill="url(#hv-sky)" />

          {/* Skyline, two depths, and a few lit windows */}
          <g fill="#0a0d0f">
            {SKYLINE.map(([x, w, h]) => (
              <rect key={`f${x}`} x={x + 6} y={196 - h * 0.8} width={w} height={h * 0.8} />
            ))}
          </g>
          <g fill="#121719">
            {SKYLINE.map(([x, w, h], i) => (
              <rect
                key={`n${x}`}
                x={(x * 1.3 + 20) % 480}
                y={196 - h * 0.55 - (i % 3) * 6}
                width={w * 0.9}
                height={h * 0.55 + (i % 3) * 6}
              />
            ))}
          </g>
          <g fill="#ffd27a" opacity={0.5}>
            {WINDOWS.map(([x, y]) => (
              <rect key={`${x}-${y}`} x={x} y={y} width="4" height="5" />
            ))}
          </g>

          {/* Sidewalk, road, lane line, bike lane */}
          <rect x="0" y="196" width="480" height="14" fill="#23272b" />
          <rect x="0" y="210" width="480" height="110" fill="url(#hv-road)" />
          <line x1="0" y1="211" x2="480" y2="211" stroke="#3a4046" strokeWidth={2} />
          <line
            className="hv-lane"
            x1="0"
            y1="236"
            x2="480"
            y2="236"
            stroke="#d8b14a"
            strokeWidth={2}
            strokeDasharray="18 14"
            opacity={0.7}
          />
          <rect x="0" y="283" width="480" height="3" fill={GREEN} opacity={0.55} />
          <g className="hv-dashes" fill={GREEN} opacity={0.5}>
            {Array.from({ length: 13 }, (_, i) => (
              <rect key={i} x={i * 46 - 46} y="302" width="24" height="3" rx="1.5" />
            ))}
          </g>

          {/* The car, behind the rider, with its headlight beam */}
          <g className="hv-car">
            <path d="M188 254 L280 264 L280 246 L188 238 Z" fill="url(#hv-headlight)" />
            <g className="hv-streaks" stroke="rgb(255 255 255 / 30%)" strokeWidth={2} strokeLinecap="round">
              <line x1="14" y1="230" x2="40" y2="230" />
              <line x1="6" y1="244" x2="38" y2="244" />
              <line x1="18" y1="258" x2="42" y2="258" />
            </g>
            <path
              d="M50 266 L50 246 Q52 238 62 236 L86 232 Q100 212 124 210 L150 210 Q164 212 176 230 L184 236 Q190 240 190 250 L190 266 Z"
              fill="url(#hv-car)"
            />
            <path d="M94 232 Q106 216 124 215 L134 215 L134 232 Z" fill="#12202a" stroke="rgb(255 255 255 / 15%)" />
            <path d="M139 215 L150 215 Q160 217 170 232 L139 232 Z" fill="#12202a" stroke="rgb(255 255 255 / 15%)" />
            <rect x="182" y="242" width="9" height="7" rx="2" fill="#fff6d0" />
            <rect x="48" y="244" width="5" height="8" rx="1.5" fill="#ff2d2d" />
            <CarWheel cx={82} cy={268} />
            <CarWheel cx={164} cy={268} />
          </g>

          {/* The phone's view, reaching back from under the saddle */}
          <path className="hv-beam" d="M346 220 L200 186 L200 290 Z" fill="url(#hv-beam)" />
          <g className="hv-waves" fill="none" stroke={GREEN} strokeWidth={2.5} strokeLinecap="round">
            <path d="M326 204 q-14 16 0 32" />
            <path d="M306 196 q-24 28 0 56" />
            <path d="M284 188 q-34 40 0 80" />
          </g>

          {/* Bike */}
          <Wheel cx={330} cy={258} />
          <Wheel cx={432} cy={258} />
          <g fill="none" stroke={GREEN} strokeWidth={4.5} strokeLinecap="round" strokeLinejoin="round">
            <path d="M330 258 L368 258 L356 214 Z" />
            <path d="M368 258 L414 216 L356 214" />
            <path d="M414 216 L432 258" />
            <path d="M410 204 L416 222" />
            <path d="M404 202 L420 200 L425 209" />
          </g>
          <path d="M348 206 L366 206" stroke={INK} strokeWidth={5} strokeLinecap="round" />
          {/* Phone, under the saddle, lens facing back */}
          <rect x="344" y="212" width="9" height="15" rx="2" fill="#0b0d0f" stroke={INK} strokeWidth={1.5} />
          <circle cx="346.6" cy="216" r="1.6" fill={GREEN} />

          {/* Rider */}
          <g fill="none" strokeLinecap="round" strokeLinejoin="round">
            <path d="M360 204 L352 232 L366 252" stroke="#9aa3ab" strokeWidth={7} />
            <path d="M360 204 L392 164" stroke={INK} strokeWidth={12} />
            <path d="M360 204 L382 226 L372 254" stroke={INK} strokeWidth={7} />
            <path d="M390 168 L410 188 L418 200" stroke={INK} strokeWidth={6} />
          </g>
          <circle cx="400" cy="152" r="10" fill="#d9b496" />
          <path d="M388 150 Q391 137 403 138 Q414 140 412 151 Z" fill={GREEN} />

          {/* Heads-up bubble, shown as the car gets close */}
          <g className="hv-bubble">
            <rect x="300" y="94" width="168" height="34" rx="9" fill="#2a0d0b" stroke={RED} strokeWidth={1.5} />
            <path d="M380 128 L388 138 L396 128" fill="#2a0d0b" stroke={RED} strokeWidth={1.5} strokeLinejoin="round" />
            <rect x="376" y="126" width="24" height="3" fill="#2a0d0b" />
            <circle cx="316" cy="111" r="5" fill={RED} />
            <text
              x="328"
              y="115.5"
              fill="#f5f7f8"
              fontSize="12.5"
              fontWeight={700}
              letterSpacing="0.05em"
              textLength="128"
              lengthAdjust="spacingAndGlyphs"
              className="hv-bubble-text"
            >
              CAR BEHIND · LEFT
            </text>
          </g>
        </g>
      </svg>
      <figcaption className="visually-hidden">
        The phone on the bike looks backward. Detection is experimental.
      </figcaption>
    </figure>
  );
}
