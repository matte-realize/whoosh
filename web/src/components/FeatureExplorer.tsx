"use client";

import { useState } from "react";
import { FEATURES, STATUS_LABEL, STATUS_SYMBOL, type Status } from "@/lib/projectStatus";

type Filter = "all" | Status;

const ORDER: Status[] = ["tested", "built", "prototype", "planned"];

/** Feature cards with filter chips by build status. The chip count and the result line update together. */
export function FeatureExplorer() {
  const [filter, setFilter] = useState<Filter>("all");

  const counts = Object.fromEntries(
    ORDER.map((status) => [status, FEATURES.filter((feature) => feature.status === status).length]),
  ) as Record<Status, number>;
  const visible = filter === "all" ? FEATURES : FEATURES.filter((feature) => feature.status === filter);
  const chips: { key: Filter; label: string; count: number }[] = [
    { key: "all", label: "All", count: FEATURES.length },
    ...ORDER.filter((status) => counts[status] > 0).map((status) => ({
      key: status as Filter,
      label: STATUS_LABEL[status],
      count: counts[status],
    })),
  ];

  return (
    <div>
      <div className="chips" role="group" aria-label="Filter features by status">
        {chips.map((chip) => (
          <button
            key={chip.key}
            type="button"
            className="chip"
            aria-pressed={filter === chip.key}
            onClick={() => setFilter(chip.key)}
          >
            {chip.key !== "all" ? <span aria-hidden="true">{STATUS_SYMBOL[chip.key]} </span> : null}
            {chip.label}
            <span className="chip__count">{chip.count}</span>
          </button>
        ))}
      </div>

      <p className="visually-hidden" aria-live="polite">
        Showing {visible.length} of {FEATURES.length} features.
      </p>

      <ul className="feature-grid">
        {visible.map((feature) => (
          <li key={feature.name} className="feature-card">
            <p className={`status status--${feature.status}`}>
              <span aria-hidden="true">{STATUS_SYMBOL[feature.status]} </span>
              {STATUS_LABEL[feature.status]}
            </p>
            <h3>{feature.name}</h3>
            <p>{feature.summary}</p>
            <p className="status-note">{feature.statusNote}</p>
          </li>
        ))}
      </ul>
    </div>
  );
}
