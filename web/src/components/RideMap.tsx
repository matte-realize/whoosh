"use client";

import { useEffect, useRef } from "react";
import * as L from "leaflet";
import "leaflet/dist/leaflet.css";
import type { RideWithNearMisses } from "@/lib/types";

/** Builds tooltip content as a DOM node. Leaflet treats strings as HTML, so untrusted text goes in via textContent. */
function textNode(text: string): HTMLElement {
  const el = document.createElement("span");
  el.textContent = text;
  return el;
}

/**
 * Draws one ride's route with Leaflet. Must be loaded client-side only (Leaflet touches `window`);
 * import it through RideMapClient.
 */
export default function RideMap({ ride }: { ride: RideWithNearMisses }) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (container === null) return;

    const map = L.map(container);

    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(map);

    // GeoJSON is [lon, lat]; Leaflet wants [lat, lon].
    const points: L.LatLngTuple[] = ride.route.coordinates.map(
      ([lon, lat]): L.LatLngTuple => [lat, lon],
    );

    const line = L.polyline(points, { color: "#0b4fd1", weight: 5, opacity: 0.9 }).addTo(map);
    map.fitBounds(line.getBounds(), { padding: [32, 32] });

    const start = points[0];
    const end = points[points.length - 1];
    L.circleMarker(start, { radius: 9, color: "#ffffff", weight: 3, fillColor: "#146c2e", fillOpacity: 1 })
      .bindTooltip(textNode("Start"), { permanent: true, direction: "top" })
      .addTo(map);
    L.circleMarker(end, { radius: 9, color: "#ffffff", weight: 3, fillColor: "#1f2328", fillOpacity: 1 })
      .bindTooltip(textNode("End"), { permanent: true, direction: "top" })
      .addTo(map);

    for (const nearMiss of ride.near_misses ?? []) {
      const hint = nearMiss.position_hint ? `, position: ${nearMiss.position_hint}` : "";
      const label = `${nearMiss.kind}, ${Math.round(nearMiss.confidence * 100)}% confidence${hint}`;
      L.circleMarker([nearMiss.latitude, nearMiss.longitude], {
        radius: 7,
        color: "#9a1c1c",
        weight: 3,
        dashArray: "3 3",
        fillColor: "#ffffff",
        fillOpacity: 0.9,
      })
        .bindTooltip(textNode(label))
        .addTo(map);
    }

    return () => {
      map.remove();
    };
  }, [ride]);

  return <div ref={containerRef} className="ride-map" role="region" aria-label="Map of the selected ride route" />;
}
