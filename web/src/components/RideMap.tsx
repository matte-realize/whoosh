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
 *
 * The map and its tile layer are created once. Selecting another ride only swaps the route layer,
 * so tiles are not re-downloaded and the map is not torn down on every click.
 */
export default function RideMap({ ride }: { ride: RideWithNearMisses }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const layerRef = useRef<L.LayerGroup | null>(null);

  // Create the map once.
  useEffect(() => {
    const container = containerRef.current;
    if (container === null) return;

    const map = L.map(container, { preferCanvas: true });
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(map);
    mapRef.current = map;
    layerRef.current = L.layerGroup().addTo(map);

    return () => {
      map.remove();
      mapRef.current = null;
      layerRef.current = null;
    };
  }, []);

  // Redraw only the ride's layer when the selected ride changes.
  useEffect(() => {
    const map = mapRef.current;
    const layer = layerRef.current;
    if (map === null || layer === null) return;

    layer.clearLayers();

    // GeoJSON is [lon, lat]; Leaflet wants [lat, lon].
    const points: L.LatLngTuple[] = ride.route.coordinates.map(
      ([lon, lat]): L.LatLngTuple => [lat, lon],
    );

    const line = L.polyline(points, { color: "#2df5a8", weight: 5, opacity: 0.95 }).addTo(layer);
    map.fitBounds(line.getBounds(), { padding: [32, 32] });

    const start = points[0];
    const end = points[points.length - 1];
    L.circleMarker(start, { radius: 9, color: "#060708", weight: 3, fillColor: "#2df5a8", fillOpacity: 1 })
      .bindTooltip(textNode("Start"), { permanent: true, direction: "top" })
      .addTo(layer);
    L.circleMarker(end, { radius: 9, color: "#060708", weight: 3, fillColor: "#f4f6f8", fillOpacity: 1 })
      .bindTooltip(textNode("End"), { permanent: true, direction: "top" })
      .addTo(layer);

    for (const nearMiss of ride.near_misses ?? []) {
      const hint = nearMiss.position_hint ? `, position: ${nearMiss.position_hint}` : "";
      const label = `${nearMiss.kind}, ${Math.round(nearMiss.confidence * 100)}% confidence${hint}`;
      L.circleMarker([nearMiss.latitude, nearMiss.longitude], {
        radius: 7,
        color: "#ff5a4f",
        weight: 3,
        dashArray: "3 3",
        fillColor: "#060708",
        fillOpacity: 0.9,
      })
        .bindTooltip(textNode(label))
        .addTo(layer);
    }
  }, [ride]);

  return <div ref={containerRef} className="ride-map" role="region" aria-label="Map of the selected ride route" />;
}
