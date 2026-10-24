/** Small decorative line icons. Always paired with visible text, so they are hidden from screen readers. */

export type IconName = "route" | "clock" | "riders" | "alert" | "bike" | "phone" | "cloud" | "map" | "lock";

const PATHS: Record<IconName, string> = {
  route: "M5 19c3 0 3-6 7-6s4-6 7-6 M5 19a1.5 1.5 0 1 0 0 .01 M19 7a1.5 1.5 0 1 0 0 .01",
  clock: "M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z M12 7v5l3 2",
  riders: "M8 11a3 3 0 1 0 0-6a3 3 0 1 0 0 6z M2 20c0-3.5 2.7-6 6-6s6 2.5 6 6 M17 11a2.5 2.5 0 1 0 0-5 M16 14c3 .3 5 2.7 5 6",
  alert: "M12 3l9.5 17h-19z M12 10v4 M12 17v.01",
  bike: "M6 18a3.5 3.5 0 1 0 0-7a3.5 3.5 0 1 0 0 7z M18 18a3.5 3.5 0 1 0 0-7a3.5 3.5 0 1 0 0 7z M6 14.5l4-7h5l3 7 M9 7.5h3 M10 7.5l2.5 7",
  phone: "M8 2h8a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z M11 18h2",
  cloud: "M7 18a4.5 4.5 0 0 1-.6-8.96A6 6 0 0 1 18 9.5a4 4 0 0 1-.5 8.5z",
  map: "M3 6l6-2 6 2 6-2v14l-6 2-6-2-6 2z M9 4v14 M15 6v14",
  lock: "M6 11h12v9H6z M8 11V8a4 4 0 0 1 8 0v3",
};

export function Icon({ name, size = 22 }: { name: IconName; size?: number }) {
  return (
    <svg
      className="icon"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d={PATHS[name]} />
    </svg>
  );
}
