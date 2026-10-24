"use client";

import { useRef, useState, type KeyboardEvent } from "react";
import { Icon, type IconName } from "./Icon";

interface Step {
  id: string;
  tab: string;
  title: string;
  icon: IconName;
  points: string[];
}

const STEPS: Step[] = [
  {
    id: "phone",
    tab: "1. On the phone",
    title: "Everything starts on the phone",
    icon: "phone",
    points: [
      "The app records the ride with GPS and keeps it on the phone.",
      "If the rider turns detection on, the rear camera runs on the phone too. Video is never uploaded.",
      "A caution cue never waits on a network, so it works with no signal.",
    ],
  },
  {
    id: "backup",
    tab: "2. If you opt in",
    title: "Backup and sharing are separate choices",
    icon: "cloud",
    points: [
      "Cloud backup is off by default. It uses an anonymous account: no email, name, or phone number.",
      "Before upload, the first and last 160 m (about 0.1 mi) of the route are cut off.",
      "Sharing a ride on this website is a second, per-ride choice.",
    ],
  },
  {
    id: "website",
    tab: "3. On this website",
    title: "The website only sees what passes the privacy rules",
    icon: "map",
    points: [
      "Only rides a rider chose to share appear, and never with who they belong to.",
      "Incidents appear as areas of about 100 m, with at least 3 reports from at least 2 riders, after a day.",
      "Rider counts stay hidden until at least 3 riders have shared.",
    ],
  },
];

/** "How it works" as tabs (WAI-ARIA tabs pattern: arrow keys, Home and End move between tabs). */
export function HowItWorks() {
  const [active, setActive] = useState(0);
  const tabs = useRef<(HTMLButtonElement | null)[]>([]);

  function focusTab(index: number) {
    const next = (index + STEPS.length) % STEPS.length;
    setActive(next);
    tabs.current[next]?.focus();
  }

  function onKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (event.key === "ArrowRight") focusTab(active + 1);
    else if (event.key === "ArrowLeft") focusTab(active - 1);
    else if (event.key === "Home") focusTab(0);
    else if (event.key === "End") focusTab(STEPS.length - 1);
    else return;
    event.preventDefault();
  }

  const step = STEPS[active];

  return (
    <div className="steps">
      <div className="steps__tabs" role="tablist" aria-label="How Whoosh works">
        {STEPS.map((item, index) => (
          <button
            key={item.id}
            ref={(element) => {
              tabs.current[index] = element;
            }}
            type="button"
            role="tab"
            id={`step-tab-${item.id}`}
            aria-controls={`step-panel-${item.id}`}
            aria-selected={index === active}
            tabIndex={index === active ? 0 : -1}
            className="steps__tab"
            onClick={() => setActive(index)}
            onKeyDown={onKeyDown}
          >
            {item.tab}
          </button>
        ))}
      </div>
      <div
        key={step.id}
        role="tabpanel"
        id={`step-panel-${step.id}`}
        aria-labelledby={`step-tab-${step.id}`}
        className="steps__panel"
        tabIndex={0}
      >
        <span className="steps__icon">
          <Icon name={step.icon} size={34} />
        </span>
        <div>
          <h3>{step.title}</h3>
          <ul className="checklist">
            {step.points.map((point) => (
              <li key={point}>{point}</li>
            ))}
          </ul>
        </div>
      </div>
      <div className="steps__progress" aria-hidden="true">
        {STEPS.map((item, index) => (
          <span key={item.id} className={index <= active ? "is-done" : undefined} />
        ))}
      </div>
    </div>
  );
}
