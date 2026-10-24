"use client";

import { useEffect, useRef } from "react";
import * as L from "leaflet";
import "leaflet/dist/leaflet.css";
import { thinRoute } from "@/lib/geo";
import type { IncidentCell, Ride } from "@/lib/types";

/** Points kept per route on the overview map. Enough for the shape at city zoom. */
const OVERVIEW_POINTS_PER_ROUTE = 300;

const ROUTE_STYLE: L.PolylineOptions = { color: "#2f6bff", weight: 4, opacity: 0.65 };
const ROUTE_HOVER_STYLE: L.PolylineOptions = { color: "#0b3fc4", weight: 7, opacity: 0.95 };

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

function dateLabel(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? "Shared ride" : `Shared ride, ${d.toLocaleDateString()}`;
}

interface CommunityMapProps {
  rides: Ride[];
  cells: IncidentCell[];
  showRoutes: boolean;
  showIncidents: boolean;
}

/**
 * One map with every shared route and the incident cells. The parent turns each layer on or off;
 * that only adds or removes the layer, so the map and its tiles are not rebuilt.
 * Client-only; import through CommunityMapClient. Uses the canvas renderer for speed.
 */
export default function CommunityMap({ rides, cells, showRoutes, showIncidents }: CommunityMapProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const routesRef = useRef<L.LayerGroup | null>(null);
  const incidentsRef = useRef<L.LayerGroup | null>(null);
  const visibleRef = useRef({ showRoutes, showIncidents });

  // Build the map when the data changes.
  useEffect(() => {
    const container = containerRef.current;
    if (container === null || (rides.length === 0 && cells.length === 0)) return;

    const map = L.map(container, { preferCanvas: true, scrollWheelZoom: false });
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(map);

    // Let the page scroll past the map; zoom with the wheel only after the map is clicked.
    map.on("click", () => map.scrollWheelZoom.enable());
    map.on("mouseout", () => map.scrollWheelZoom.disable());

    const bounds = L.latLngBounds([]);

    const routes = L.layerGroup();
    for (const ride of rides) {
      // GeoJSON is [lon, lat]; Leaflet wants [lat, lon].
      const points = thinRoute(ride.route.coordinates, OVERVIEW_POINTS_PER_ROUTE).map(
        ([lon, lat]): L.LatLngTuple => [lat, lon],
      );
      for (const point of points) bounds.extend(point);
      const line = L.polyline(points, ROUTE_STYLE).bindTooltip(textNode(dateLabel(ride.started_at)), { sticky: true });
      line.on("mouseover", () => line.setStyle(ROUTE_HOVER_STYLE).bringToFront());
      line.on("mouseout", () => line.setStyle(ROUTE_STYLE));
      line.addTo(routes);
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
        color: "#a34100",
        weight: 2,
        fillColor: "#ff8a3d",
        fillOpacity: 0.55,
      })
        .bindTooltip(textNode(label))
        .addTo(incidents);
    }

    if (visibleRef.current.showRoutes) routes.addTo(map);
    if (visibleRef.current.showIncidents) incidents.addTo(map);
    if (bounds.isValid()) map.fitBounds(bounds, { padding: [40, 40], maxZoom: 15 });

    mapRef.current = map;
    routesRef.current = routes;
    incidentsRef.current = incidents;

    return () => {
      map.remove();
      mapRef.current = null;
      routesRef.current = null;
      incidentsRef.current = null;
    };
  }, [rides, cells]);

  // Show or hide layers without rebuilding the map.
  useEffect(() => {
    visibleRef.current = { showRoutes, showIncidents };
    const map = mapRef.current;
    if (map === null) return;
    const pairs: [L.LayerGroup | null, boolean][] = [
      [routesRef.current, showRoutes],
      [incidentsRef.current, showIncidents],
    ];
    for (const [layer, show] of pairs) {
      if (layer === null) continue;
      if (show && !map.hasLayer(layer)) layer.addTo(map);
      if (!show && map.hasLayer(layer)) map.removeLayer(layer);
    }
  }, [showRoutes, showIncidents]);

  return (
    <div
      ref={containerRef}
      className="ride-map community-map"
      role="region"
      aria-label="Map of all shared routes and incident reports. Click the map to zoom with the scroll wheel."
    />
  );
}
