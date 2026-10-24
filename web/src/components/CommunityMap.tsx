"use client";

import { useEffect, useRef } from "react";
import * as L from "leaflet";
import "leaflet/dist/leaflet.css";
import { thinRoute } from "@/lib/geo";
import type { IncidentCell, Ride } from "@/lib/types";

/** Points kept per route on the overview map. Enough for the shape at city zoom. */
const OVERVIEW_POINTS_PER_ROUTE = 300;

function textNode(text: string): HTMLElement {
  const el = document.createElement("span");
  el.textContent = text;
  return el;
}

function monthLabel(iso: string): string {
  const [year, month] = iso.split("-");
  return `${month}/${year}`;
}

/** Circle radius in pixels grows with the square root of the count, so area tracks the count. */
function radiusFor(count: number): number {
  return Math.min(28, 8 + Math.sqrt(count) * 4);
}

/**
 * One map with every shared route and the incident cells, each as a layer the viewer can turn
 * off with the layer control (top right). Client-only; import through CommunityMapClient.
 *
 * Performance: the canvas renderer draws all lines and circles on one canvas instead of one SVG
 * element each, and routes are thinned to a few hundred points for this overview.
 */
export default function CommunityMap({ rides, cells }: { rides: Ride[]; cells: IncidentCell[] }) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (container === null || (rides.length === 0 && cells.length === 0)) return;

    const map = L.map(container, { preferCanvas: true });
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(map);

    const bounds = L.latLngBounds([]);

    const routes = L.layerGroup();
    for (const ride of rides) {
      // GeoJSON is [lon, lat]; Leaflet wants [lat, lon].
      const points = thinRoute(ride.route.coordinates, OVERVIEW_POINTS_PER_ROUTE).map(
        ([lon, lat]): L.LatLngTuple => [lat, lon],
      );
      for (const point of points) bounds.extend(point);
      L.polyline(points, { color: "#0b4fd1", weight: 3, opacity: 0.6 }).addTo(routes);
    }

    const incidents = L.layerGroup();
    for (const cell of cells) {
      const point: L.LatLngTuple = [cell.latitude, cell.longitude];
      bounds.extend(point);
      const kinds = cell.vehicle_kinds.join(", ") || "unknown";
      const label =
        `${cell.incident_count} reports (${cell.rider_reported_count} rider-reported, ` +
        `${cell.detected_count} detected). Vehicles: ${kinds}. ` +
        `${monthLabel(cell.first_month)} to ${monthLabel(cell.last_month)}.`;
      L.circleMarker(point, {
        radius: radiusFor(cell.incident_count),
        color: "#7a2e00",
        weight: 2,
        fillColor: "#f08c3a",
        fillOpacity: 0.55,
      })
        .bindTooltip(textNode(label))
        .addTo(incidents);
    }

    routes.addTo(map);
    incidents.addTo(map);
    L.control
      .layers(undefined, { "Shared routes (blue lines)": routes, "Incident reports (orange circles)": incidents }, {
        collapsed: false,
      })
      .addTo(map);

    if (bounds.isValid()) map.fitBounds(bounds, { padding: [40, 40], maxZoom: 15 });

    return () => {
      map.remove();
    };
  }, [rides, cells]);

  return (
    <div
      ref={containerRef}
      className="ride-map community-map"
      role="region"
      aria-label="Map of all shared routes and incident reports"
    />
  );
}
