"use client";

import { useEffect, useRef } from "react";
import * as L from "leaflet";
import "leaflet/dist/leaflet.css";
import type { CrashSpot } from "@/lib/cityCrashes";
import { counterLabel, PROTECTION_LABEL } from "@/lib/cityStreets";
import { thinRoute } from "@/lib/geo";
import type { BikeCountLocation, BikeFacility, IncidentCell, LaneProtection, Ride } from "@/lib/types";

/** Points kept per route on the overview map. Enough for the shape at city zoom. */
const OVERVIEW_POINTS_PER_ROUTE = 300;

const ROUTE_STYLE: L.PolylineOptions = { color: "#3ba7ff", weight: 4, opacity: 0.75 };
const ROUTE_HOVER_STYLE: L.PolylineOptions = { color: "#2df5a8", weight: 7, opacity: 1 };

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
  /** Real city crash records, grouped by published location. */
  crashSpots: CrashSpot[];
  /** The city's bike lane inventory. */
  lanes: BikeFacility[];
  /** The city's bike counters. */
  counters: BikeCountLocation[];
  showRoutes: boolean;
  showIncidents: boolean;
  showCityCrashes: boolean;
  showLanes: boolean;
  showCounters: boolean;
}

const CITY_CRASH_COLOR = "#ffb020";

/** Lane styles by protection. Separated lanes are solid green; one-side separation is dashed. */
export const LANE_STYLE: Record<LaneProtection, L.PolylineOptions> = {
  separated: { color: "#2df5a8", weight: 5, opacity: 0.85 },
  partly_separated: { color: "#2df5a8", weight: 5, opacity: 0.85, dashArray: "8 6" },
  painted: { color: "#b48cff", weight: 4, opacity: 0.8 },
  shared: { color: "#8f99a3", weight: 3, opacity: 0.8, dashArray: "4 6" },
  path: { color: "#8f99a3", weight: 3, opacity: 0.8 },
};

function laneLabel(lane: BikeFacility): string {
  const installed = lane.install_year ? `, installed ${lane.install_year}` : "";
  return `${PROTECTION_LABEL[lane.protection]}: ${lane.facility_label}${installed}.`;
}

function counterText(counter: BikeCountLocation): string {
  const share =
    counter.latest_bike_share === null ? "" : `, ${Math.round(counter.latest_bike_share * 100)}% of counted traffic`;
  const days = counter.latest_year_days === 1 ? "1 count day" : `${counter.latest_year_days} count days`;
  return (
    `City bike counter, ${counterLabel(counter.name)}: ${counter.latest_avg_daily_bikes.toLocaleString()} bikes a day` +
    `${share} (${counter.last_year}, average of ${days}).`
  );
}

function crashLabel(spot: CrashSpot): string {
  const years = spot.firstYear === spot.lastYear ? `${spot.firstYear}` : `${spot.firstYear} to ${spot.lastYear}`;
  const noun = spot.count === 1 ? "bike crash" : "bike crashes";
  return `${spot.label}: ${spot.count} city-reported ${noun}, ${years}. Last: ${spot.lastMonth}.`;
}

/**
 * One map with every shared route, the incident cells, and the city's crash records. The parent turns each layer on or off;
 * that only adds or removes the layer, so the map and its tiles are not rebuilt.
 * Client-only; import through CommunityMapClient. Uses the canvas renderer for speed.
 */
export default function CommunityMap({
  rides,
  cells,
  crashSpots,
  lanes,
  counters,
  showRoutes,
  showIncidents,
  showCityCrashes,
  showLanes,
  showCounters,
}: CommunityMapProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const routesRef = useRef<L.LayerGroup | null>(null);
  const incidentsRef = useRef<L.LayerGroup | null>(null);
  const crashesRef = useRef<L.LayerGroup | null>(null);
  const lanesRef = useRef<L.LayerGroup | null>(null);
  const countersRef = useRef<L.LayerGroup | null>(null);
  const visibleRef = useRef({ showRoutes, showIncidents, showCityCrashes, showLanes, showCounters });

  // Build the map when the data changes.
  useEffect(() => {
    const container = containerRef.current;
    if (container === null) return;
    if (rides.length === 0 && cells.length === 0 && crashSpots.length === 0 && lanes.length === 0) return;

    const map = L.map(container, { preferCanvas: true, scrollWheelZoom: false });
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(map);

    // Lanes sit in their own pane under the other layers, so toggling never draws them on top.
    map.createPane("lanes");
    const lanePane = map.getPane("lanes");
    if (lanePane) lanePane.style.zIndex = "350";

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
        color: "#ff5a4f",
        weight: 2,
        fillColor: "#ff5a4f",
        fillOpacity: 0.35,
      })
        .bindTooltip(textNode(label))
        .addTo(incidents);
    }

    // City crashes: smaller, outlined circles in amber, drawn under the rider layers.
    const crashes = L.layerGroup();
    for (const spot of crashSpots) {
      const point: L.LatLngTuple = [spot.latitude, spot.longitude];
      bounds.extend(point);
      L.circleMarker(point, {
        radius: Math.min(16, 4 + Math.sqrt(spot.count) * 3),
        color: CITY_CRASH_COLOR,
        weight: 1.5,
        fillColor: CITY_CRASH_COLOR,
        fillOpacity: 0.25,
      })
        .bindTooltip(textNode(crashLabel(spot)))
        .addTo(crashes);
    }

    const laneLayer = L.layerGroup();
    for (const lane of lanes) {
      const points = lane.route.coordinates.map(([lon, lat]): L.LatLngTuple => [lat, lon]);
      for (const point of points) bounds.extend(point);
      L.polyline(points, { ...LANE_STYLE[lane.protection], pane: "lanes" })
        .bindTooltip(textNode(laneLabel(lane)), { sticky: true })
        .addTo(laneLayer);
    }

    const counterLayer = L.layerGroup();
    for (const counter of counters) {
      L.marker([counter.latitude, counter.longitude], {
        // The same numbers are listed as text in the city data section below the map.
        icon: L.divIcon({ className: "counter-pin", iconSize: [14, 14] }),
        keyboard: false,
      })
        .bindTooltip(textNode(counterText(counter)))
        .addTo(counterLayer);
    }

    if (visibleRef.current.showLanes) laneLayer.addTo(map);
    if (visibleRef.current.showCounters) counterLayer.addTo(map);
    if (visibleRef.current.showCityCrashes) crashes.addTo(map);
    if (visibleRef.current.showRoutes) routes.addTo(map);
    if (visibleRef.current.showIncidents) incidents.addTo(map);
    if (bounds.isValid()) map.fitBounds(bounds, { padding: [40, 40], maxZoom: 15 });

    mapRef.current = map;
    routesRef.current = routes;
    incidentsRef.current = incidents;
    crashesRef.current = crashes;
    lanesRef.current = laneLayer;
    countersRef.current = counterLayer;

    return () => {
      map.remove();
      mapRef.current = null;
      routesRef.current = null;
      incidentsRef.current = null;
      crashesRef.current = null;
      lanesRef.current = null;
      countersRef.current = null;
    };
  }, [rides, cells, crashSpots, lanes, counters]);

  // Show or hide layers without rebuilding the map.
  useEffect(() => {
    visibleRef.current = { showRoutes, showIncidents, showCityCrashes, showLanes, showCounters };
    const map = mapRef.current;
    if (map === null) return;
    const pairs: [L.LayerGroup | null, boolean][] = [
      [routesRef.current, showRoutes],
      [incidentsRef.current, showIncidents],
      [crashesRef.current, showCityCrashes],
      [lanesRef.current, showLanes],
      [countersRef.current, showCounters],
    ];
    for (const [layer, show] of pairs) {
      if (layer === null) continue;
      if (show && !map.hasLayer(layer)) layer.addTo(map);
      if (!show && map.hasLayer(layer)) map.removeLayer(layer);
    }
  }, [showRoutes, showIncidents, showCityCrashes, showLanes, showCounters]);

  return (
    <div
      ref={containerRef}
      className="ride-map community-map"
      role="region"
      aria-label="Map of shared routes, rider incident reports, city-reported bike crashes, bike lanes, and bike counters. Click the map to zoom with the scroll wheel."
    />
  );
}
