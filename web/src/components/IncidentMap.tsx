"use client";

import { useEffect, useRef } from "react";
import * as L from "leaflet";
import "leaflet/dist/leaflet.css";
import type { IncidentCell } from "@/lib/types";

function textNode(text: string): HTMLElement {
  const el = document.createElement("span");
  el.textContent = text;
  return el;
}

function month(iso: string): string {
  const [year, monthNumber] = iso.split("-");
  return `${monthNumber}/${year}`;
}

/** Circle radius in pixels grows with the square root of the count, so area tracks the count. */
function radiusFor(count: number): number {
  return Math.min(28, 8 + Math.sqrt(count) * 4);
}

/**
 * Draws incident cells. Client-only (Leaflet touches `window`); import through IncidentMapClient.
 * Uses Leaflet's canvas renderer: one canvas instead of one SVG element per circle, which keeps
 * hundreds of markers fast.
 */
export default function IncidentMap({ cells }: { cells: IncidentCell[] }) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (container === null || cells.length === 0) return;

    const map = L.map(container, { preferCanvas: true });
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(map);

    const bounds = L.latLngBounds([]);
    for (const cell of cells) {
      const point: L.LatLngTuple = [cell.latitude, cell.longitude];
      bounds.extend(point);
      const kinds = cell.vehicle_kinds.join(", ") || "unknown";
      const label =
        `${cell.incident_count} reports (${cell.rider_reported_count} rider-reported, ` +
        `${cell.detected_count} detected). Vehicles: ${kinds}. ` +
        `${month(cell.first_month)} to ${month(cell.last_month)}.`;
      L.circleMarker(point, {
        radius: radiusFor(cell.incident_count),
        color: "#7a2e00",
        weight: 2,
        fillColor: "#f08c3a",
        fillOpacity: 0.55,
      })
        .bindTooltip(textNode(label))
        .addTo(map);
    }
    map.fitBounds(bounds, { padding: [40, 40], maxZoom: 16 });

    return () => {
      map.remove();
    };
  }, [cells]);

  return <div ref={containerRef} className="ride-map" role="region" aria-label="Map of reported incidents" />;
}
