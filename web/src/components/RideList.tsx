"use client";

import { formatDateTime, formatDistance, formatDuration } from "@/lib/units";
import type { Ride } from "@/lib/types";

interface RideListProps {
  rides: Ride[];
  selectedId: string;
  onSelect: (id: string) => void;
}

/** Rides in the order given. Each ride is a button. */
export function RideList({ rides, selectedId, onSelect }: RideListProps) {
  return (
    <ul className="ride-list" aria-label="Rides">
      {rides.map((ride) => {
        const selected = ride.id === selectedId;
        return (
          <li key={ride.id}>
            <button
              type="button"
              className="ride-item"
              aria-pressed={selected}
              aria-current={selected ? "true" : undefined}
              onClick={() => onSelect(ride.id)}
            >
              <span className="ride-item__date">{formatDateTime(ride.started_at)}</span>
              <span className="ride-item__stats">
                {formatDistance(ride.distance_m)} · {formatDuration(ride.active_duration_s)}
              </span>
              {selected ? <span className="ride-item__flag">Selected</span> : null}
            </button>
          </li>
        );
      })}
    </ul>
  );
}
