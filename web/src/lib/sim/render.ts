/**
 * Draws the ride simulation on a 2D canvas with a small hand-written 3D projection
 * (look-at camera, near-plane clipping, painter's algorithm). No WebGL, no libraries.
 *
 * World axes match engine.ts: x to the rider's right, y up, z forward; the rider is at z = 0.
 */

import {
  CONTACT,
  DETECTION,
  RIDER_X,
  ROAD,
  countdownRemaining,
  cueActive,
  fallAmount,
  timeToReach,
  type SimState,
  type Vehicle,
} from "./engine";

export type ViewMode = "orbit" | "overhead" | "phone";

export interface Orbit {
  /** Radians around the vertical axis, measured from +z. */
  azimuth: number;
  /** Radians above the ground. */
  elevation: number;
  /** Meters from the target. */
  radius: number;
  /** Point the camera circles and looks at. Defaults to the road just behind the rider. */
  target?: { x: number; y: number; z: number };
}

export const DEFAULT_ORBIT: Orbit = { azimuth: (35 * Math.PI) / 180, elevation: (24 * Math.PI) / 180, radius: 38 };

export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

/** A free camera: where it is, what it looks at, and its vertical field of view in degrees. */
export interface CameraPose {
  pos: Vec3;
  target: Vec3;
  fov: number;
}

/** The phone's rear camera, on the seat post, looking back down the road. */
export const PHONE_CAMERA: CameraPose = {
  pos: { x: RIDER_X, y: 0.8, z: -0.65 },
  target: { x: RIDER_X - 0.6, y: 0.9, z: -40 },
  fov: 64,
};

/** Optional extras for drawScene. Every field defaults to the /simulation behavior. */
export interface SceneOptions {
  /** Draw the detector's output (zone, pins, labels, colored vehicles, cue border). Default true. */
  detector?: boolean;
  /** How far the phone is clipped onto the seat post, 0 (not there) to 1 (mounted). Default 1. */
  phoneMount?: number;
  /** Draw the rider and bike in non-phone views. Default true. */
  showRider?: boolean;
  /** Use this camera instead of the view's own (the orbit is ignored). */
  camera?: CameraPose;
  /** Top-left tag in the phone view. */
  cameraTag?: string;
}

const v = (x: number, y: number, z: number): Vec3 => ({ x, y, z });
const sub = (a: Vec3, b: Vec3): Vec3 => v(a.x - b.x, a.y - b.y, a.z - b.z);
const dot = (a: Vec3, b: Vec3): number => a.x * b.x + a.y * b.y + a.z * b.z;
const cross = (a: Vec3, b: Vec3): Vec3 => v(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
const norm = (a: Vec3): Vec3 => {
  const l = Math.hypot(a.x, a.y, a.z) || 1;
  return v(a.x / l, a.y / l, a.z / l);
};

const NEAR = 0.25;

interface Camera {
  pos: Vec3;
  right: Vec3;
  up: Vec3;
  forward: Vec3;
  focal: number;
  cx: number;
  cy: number;
}

function makeCamera(pos: Vec3, target: Vec3, fovDegrees: number, width: number, height: number): Camera {
  const forward = norm(sub(target, pos));
  // With x right, y up and z forward, cross(worldUp, forward) points to screen right.
  const right = norm(cross(v(0, 1, 0), forward));
  const up = cross(forward, right);
  const focal = height / 2 / Math.tan(((fovDegrees * Math.PI) / 180) / 2);
  return { pos, right, up, forward, focal, cx: width / 2, cy: height / 2 };
}

function toCamera(cam: Camera, p: Vec3): Vec3 {
  const d = sub(p, cam.pos);
  return v(dot(d, cam.right), dot(d, cam.up), dot(d, cam.forward));
}

function projectCamera(cam: Camera, c: Vec3): [number, number] {
  const s = cam.focal / c.z;
  return [cam.cx + c.x * s, cam.cy - c.y * s];
}

/** Projects a world point, or returns null when it is behind the camera. */
export function project(cam: Camera, p: Vec3): [number, number] | null {
  const c = toCamera(cam, p);
  return c.z < NEAR ? null : projectCamera(cam, c);
}

/** Clips a polygon (camera space) against the near plane. */
function clipNear(points: Vec3[]): Vec3[] {
  const out: Vec3[] = [];
  for (let i = 0; i < points.length; i += 1) {
    const a = points[i];
    const b = points[(i + 1) % points.length];
    const aIn = a.z >= NEAR;
    const bIn = b.z >= NEAR;
    if (aIn) out.push(a);
    if (aIn !== bIn) {
      const t = (NEAR - a.z) / (b.z - a.z);
      out.push(v(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, NEAR));
    }
  }
  return out;
}

function drawPolygon(
  ctx: CanvasRenderingContext2D,
  cam: Camera,
  world: Vec3[],
  fill: string | null,
  stroke?: string,
  lineWidth = 1,
): void {
  const clipped = clipNear(world.map((p) => toCamera(cam, p)));
  if (clipped.length < 3) return;
  ctx.beginPath();
  clipped.forEach((c, i) => {
    const [x, y] = projectCamera(cam, c);
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  });
  ctx.closePath();
  if (fill) {
    ctx.fillStyle = fill;
    ctx.fill();
  }
  if (stroke) {
    ctx.strokeStyle = stroke;
    ctx.lineWidth = lineWidth;
    ctx.stroke();
  }
}

/** Ground rectangle at y = 0 from (x0, z0) to (x1, z1). */
function groundRect(x0: number, x1: number, z0: number, z1: number): Vec3[] {
  return [v(x0, 0, z0), v(x1, 0, z0), v(x1, 0, z1), v(x0, 0, z1)];
}

// ---------- Boxes (painter's algorithm) ----------

type RGB = [number, number, number];

interface Face {
  points: Vec3[];
  color: string;
  depth: number;
}

function shade(rgb: RGB, factor: number): string {
  const [r, g, b] = rgb.map((c) => Math.round(Math.min(255, c * factor)));
  return `rgb(${r} ${g} ${b})`;
}

/** Adds the camera-facing faces of an axis-aligned box. x/z are the center; y0 is the bottom. */
function addBox(
  faces: Face[],
  cam: Camera,
  x: number,
  z: number,
  y0: number,
  width: number,
  height: number,
  length: number,
  rgb: RGB,
): void {
  const x0 = x - width / 2;
  const x1 = x + width / 2;
  const z0 = z - length / 2;
  const z1 = z + length / 2;
  const y1 = y0 + height;
  const sides: { pts: Vec3[]; normal: Vec3; light: number }[] = [
    { pts: [v(x0, y1, z0), v(x1, y1, z0), v(x1, y1, z1), v(x0, y1, z1)], normal: v(0, 1, 0), light: 1.15 },
    { pts: [v(x0, y0, z1), v(x1, y0, z1), v(x1, y1, z1), v(x0, y1, z1)], normal: v(0, 0, 1), light: 0.85 },
    { pts: [v(x0, y0, z0), v(x0, y1, z0), v(x1, y1, z0), v(x1, y0, z0)], normal: v(0, 0, -1), light: 0.8 },
    { pts: [v(x1, y0, z0), v(x1, y1, z0), v(x1, y1, z1), v(x1, y0, z1)], normal: v(1, 0, 0), light: 0.65 },
    { pts: [v(x0, y0, z0), v(x0, y0, z1), v(x0, y1, z1), v(x0, y1, z0)], normal: v(-1, 0, 0), light: 0.7 },
  ];
  for (const side of sides) {
    const center = v(
      side.pts.reduce((s, p) => s + p.x, 0) / 4,
      side.pts.reduce((s, p) => s + p.y, 0) / 4,
      side.pts.reduce((s, p) => s + p.z, 0) / 4,
    );
    if (dot(side.normal, sub(cam.pos, center)) <= 0) continue; // back face
    const c = toCamera(cam, center);
    faces.push({ points: side.pts, color: shade(rgb, side.light), depth: c.z });
  }
}

const COLORS = {
  sky: "#060708",
  horizon: "#0f1a17",
  ground: "#0b0e0f",
  sidewalk: "#1b1f22",
  road: "#15181b",
  bikeLane: "#13261f",
  marking: "rgb(244 246 248 / 70%)",
  bikeMarking: "rgb(45 245 168 / 80%)",
  accent: "#2df5a8",
  lime: "#c8f135",
  red: "#ff5a4f",
  amber: "#ffb020",
  text: "#f4f6f8",
  muted: "#98a1ab",
};

const BUILDING: RGB = [34, 39, 44];
const CAR_IDLE: RGB = [92, 102, 115];
const CAR_ONCOMING: RGB = [64, 70, 78];
const CAR_TRACKING: RGB = [255, 176, 32];
const CAR_CUED: RGB = [255, 90, 79];
const RIDER: RGB = [45, 245, 168];
const BIKE: RGB = [200, 206, 212];
const SKIN: RGB = [214, 180, 150];

function vehicleColor(vehicle: Vehicle, detector: boolean): RGB {
  if (vehicle.direction === -1) return CAR_ONCOMING;
  if (vehicle.missed || !detector) return CAR_IDLE;
  if (vehicle.state === "cued") return CAR_CUED;
  if (vehicle.state === "tracking") return CAR_TRACKING;
  return CAR_IDLE;
}

function addVehicle(faces: Face[], cam: Camera, vehicle: Vehicle, detector = true): void {
  const rgb = vehicleColor(vehicle, detector);
  if (vehicle.kind === "car") {
    addBox(faces, cam, vehicle.x, vehicle.z, 0.25, vehicle.width, vehicle.height * 0.5, vehicle.length, rgb);
    addBox(
      faces,
      cam,
      vehicle.x,
      vehicle.z - vehicle.direction * 0.3,
      0.25 + vehicle.height * 0.5,
      vehicle.width * 0.86,
      vehicle.height * 0.45,
      vehicle.length * 0.5,
      rgb.map((c) => c * 0.8) as RGB,
    );
  } else {
    addBox(faces, cam, vehicle.x, vehicle.z, 0.35, vehicle.width, vehicle.height, vehicle.length, rgb);
  }
}

function addRider(faces: Face[], cam: Camera, fall: number, phoneMount = 1): void {
  const x = RIDER_X;
  if (fall >= 0.5) {
    // On the ground: the bike on its side, the rider lying to the right of it, away from traffic.
    addBox(faces, cam, x + 0.25, 0.55, 0, 0.68, 0.07, 0.68, BIKE); // front wheel
    addBox(faces, cam, x + 0.25, -0.55, 0, 0.68, 0.07, 0.68, BIKE); // rear wheel
    addBox(faces, cam, x + 0.3, 0, 0.07, 0.1, 0.08, 1.05, BIKE); // frame
    addBox(faces, cam, x + 0.95, 0.1, 0, 0.62, 0.3, 0.42, RIDER); // torso
    addBox(faces, cam, x + 1.42, 0.15, 0, 0.26, 0.24, 0.26, SKIN); // head
    addBox(faces, cam, x + 0.3, -0.5, 0.07, 0.16, 0.05, 0.1, RIDER); // phone, still on the seat post
    return;
  }
  addBox(faces, cam, x, 0.55, 0, 0.07, 0.68, 0.68, BIKE); // front wheel
  addBox(faces, cam, x, -0.55, 0, 0.07, 0.68, 0.68, BIKE); // rear wheel
  addBox(faces, cam, x, 0, 0.42, 0.08, 0.1, 1.05, BIKE); // frame
  addBox(faces, cam, x, -0.05, 0.9, 0.42, 0.62, 0.36, RIDER); // torso
  addBox(faces, cam, x, 0.05, 1.52, 0.24, 0.26, 0.26, SKIN); // head
  if (phoneMount > 0) {
    // Phone on the seat post; while mounting it drops in from above.
    const lift = (1 - Math.min(1, phoneMount)) * 0.7;
    addBox(faces, cam, x, -0.5, 0.72 + lift, 0.1, 0.16, 0.05, RIDER);
  }
}

/**
 * Buildings scroll past with the rider's distance so the scene feels like motion. `sides` lists
 * which side of the road to draw: the orbit view skips the side the camera is on, so buildings
 * never stand between the camera and the road.
 */
function addBuildings(faces: Face[], cam: Camera, riderDistance: number, sides: number[]): void {
  const spacing = 18;
  const offset = riderDistance % spacing;
  const block = Math.floor(riderDistance / spacing);
  for (let k = -10; k <= 4; k += 1) {
    const z = k * spacing - offset;
    for (const side of sides) {
      const n = (k + block) * 7 + (side > 0 ? 3 : 11);
      const height = 6 + (Math.abs(Math.sin(n * 12.9898) * 43758.5453) % 1) * 16;
      const x = side > 0 ? ROAD.sidewalkRight + 6 : ROAD.sidewalkLeft - 6;
      addBox(faces, cam, x, z, 0, 9, height, 14, BUILDING);
    }
  }
}

function drawFaces(ctx: CanvasRenderingContext2D, cam: Camera, faces: Face[]): void {
  faces.sort((a, b) => b.depth - a.depth);
  for (const face of faces) drawPolygon(ctx, cam, face.points, face.color, "rgb(0 0 0 / 35%)", 1);
}

// ---------- Ground: road, markings, detection zone ----------

function drawGround(ctx: CanvasRenderingContext2D, cam: Camera, state: SimState, showZone: boolean, showPins = true): void {
  const far = -220;
  const near = 80;
  drawPolygon(ctx, cam, groundRect(-80, 80, far, near), COLORS.ground);
  drawPolygon(ctx, cam, groundRect(ROAD.bikeLaneRight, ROAD.sidewalkRight, far, near), COLORS.sidewalk);
  drawPolygon(ctx, cam, groundRect(ROAD.sidewalkLeft, ROAD.oncomingLaneLeft, far, near), COLORS.sidewalk);
  drawPolygon(ctx, cam, groundRect(ROAD.oncomingLaneLeft, ROAD.bikeLaneLeft, far, near), COLORS.road);
  drawPolygon(ctx, cam, groundRect(ROAD.bikeLaneLeft, ROAD.bikeLaneRight, far, near), COLORS.bikeLane);

  // Solid bike lane line and dashed center line, scrolling with the rider.
  drawPolygon(ctx, cam, groundRect(ROAD.bikeLaneLeft - 0.08, ROAD.bikeLaneLeft + 0.08, far, near), COLORS.bikeMarking);
  const dash = 3;
  const gap = 9;
  const offset = state.riderDistance % gap;
  for (let z = far - offset; z < near; z += gap) {
    const x = ROAD.travelLaneLeft;
    drawPolygon(ctx, cam, groundRect(x - 0.07, x + 0.07, z, z + dash), "#d8b14a");
    drawPolygon(ctx, cam, groundRect(x - 0.3, x - 0.16, z, z + dash), "#d8b14a");
  }

  // Near-miss pins: a diamond painted where each one was logged, left behind as the rider rides on.
  for (const nearMiss of showPins ? state.nearMisses : []) {
    const z = nearMiss.at - state.riderDistance;
    if (z < far || z > near) continue;
    const r = 0.75;
    const color = nearMiss.source === "rider_reported" ? "rgb(200 241 53 / 85%)" : "rgb(255 176 32 / 85%)";
    drawPolygon(
      ctx,
      cam,
      [v(RIDER_X, 0.02, z - r), v(RIDER_X + r * 0.8, 0.02, z), v(RIDER_X, 0.02, z + r), v(RIDER_X - r * 0.8, 0.02, z)],
      color,
      "rgb(6 7 8 / 60%)",
      1,
    );
  }

  // Crash: a pulsing ring around the rider while the countdown runs, solid once the alert is out.
  const crash = state.crash;
  if (crash.phase === "countdown" || crash.phase === "sending" || crash.phase === "sent") {
    const pulse = crash.phase === "countdown" ? 0.5 + 0.5 * Math.sin(state.t * 8) : 1;
    const radius = 1.6 + pulse * 0.5;
    const ring: Vec3[] = [];
    for (let i = 0; i < 28; i += 1) {
      const a = (i / 28) * Math.PI * 2;
      ring.push(v(RIDER_X + 0.6 + Math.cos(a) * radius, 0.02, Math.sin(a) * radius));
    }
    drawPolygon(ctx, cam, ring, `rgb(255 90 79 / ${Math.round(10 + pulse * 14)}%)`, "rgb(255 90 79 / 85%)", 2);
  }

  if (showZone) {
    const cue = cueActive(state);
    const zone = [v(RIDER_X, 0.01, -0.6), v(ROAD.oncomingLaneLeft + 3.2, 0.01, -DETECTION.rangeMeters), v(ROAD.bikeLaneRight + 1, 0.01, -DETECTION.rangeMeters)];
    drawPolygon(
      ctx,
      cam,
      zone,
      cue ? "rgb(255 90 79 / 16%)" : "rgb(45 245 168 / 8%)",
      cue ? "rgb(255 90 79 / 60%)" : "rgb(45 245 168 / 35%)",
      1.5,
    );
  }
}

// ---------- Labels ----------

function pill(ctx: CanvasRenderingContext2D, x: number, y: number, text: string, color: string, scale: number): void {
  ctx.font = `700 ${11 * scale}px ui-sans-serif, system-ui, sans-serif`;
  const padX = 7 * scale;
  const w = ctx.measureText(text).width + padX * 2;
  const h = 20 * scale;
  ctx.fillStyle = "rgb(6 7 8 / 82%)";
  ctx.strokeStyle = color;
  ctx.lineWidth = 1.5 * scale;
  ctx.beginPath();
  ctx.roundRect(x - w / 2, y - h, w, h, h / 2);
  ctx.fill();
  ctx.stroke();
  ctx.fillStyle = color;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(text, x, y - h / 2 + 0.5);
}

function vehicleLabel(vehicle: Vehicle, riderSpeed: number): { text: string; color: string } | null {
  const behind = Math.round(-(vehicle.z + vehicle.length / 2));
  if (vehicle.direction === -1) {
    return Math.abs(vehicle.z) < 45 ? { text: "Oncoming · not flagged", color: COLORS.muted } : null;
  }
  if (vehicle.state === "passed") return null;
  if (vehicle.missed && behind < DETECTION.rangeMeters) return { text: "Missed (simulated mistake)", color: COLORS.muted };
  if (vehicle.state === "cued") return { text: `Caution cue · ${Math.max(behind, 0)} m`, color: COLORS.red };
  if (vehicle.state === "tracking") {
    const ttr = timeToReach(vehicle, riderSpeed);
    return { text: `Tracking · ${behind} m${ttr !== null ? ` · ${ttr.toFixed(1)} s` : ""}`, color: COLORS.amber };
  }
  return null;
}

function drawLabels(ctx: CanvasRenderingContext2D, cam: Camera, state: SimState, scale: number): void {
  for (const vehicle of state.vehicles) {
    const label = vehicleLabel(vehicle, state.riderSpeed);
    if (label === null) continue;
    const p = project(cam, v(vehicle.x, vehicle.height + 0.9, vehicle.z));
    if (p !== null) pill(ctx, p[0], p[1], label.text, label.color, scale);
  }
  for (const nearMiss of state.nearMisses) {
    const z = nearMiss.at - state.riderDistance;
    if (z < -40 || z > 1) continue;
    const p = project(cam, v(RIDER_X, 0.9, z));
    const text = nearMiss.source === "rider_reported" ? "Close call · marked by rider" : "Near miss logged";
    if (p !== null && z < -2) pill(ctx, p[0], p[1], text, nearMiss.source === "rider_reported" ? COLORS.lime : COLORS.amber, scale);
  }
  const rider = project(cam, v(RIDER_X + 0.6, fallAmount(state) >= 0.5 ? 1.3 : 2.3, 0));
  if (rider !== null) {
    const { text, color } = riderLabel(state);
    pill(ctx, rider[0], rider[1], text, color, scale);
  }
}

function riderLabel(state: SimState): { text: string; color: string } {
  const remaining = countdownRemaining(state);
  switch (state.crash.phase) {
    case "countdown":
      return { text: `Crash detected · alert in ${Math.ceil(remaining ?? 0)} s`, color: COLORS.red };
    case "sending":
      return { text: `Sending alert to ${CONTACT.contactName}…`, color: COLORS.red };
    case "sent":
      return { text: `Alert sent to ${CONTACT.contactName}`, color: COLORS.red };
    case "cancelled":
      if (fallAmount(state) > 0) return { text: "I'm OK · no alert sent", color: COLORS.accent };
      break;
    default:
      break;
  }
  return { text: state.riderSpeed < 0.05 ? "Rider · ready" : "Rider", color: COLORS.accent };
}

/** In the phone view, outline what the simulated detector sees, like a detector overlay would. */
function drawDetections(ctx: CanvasRenderingContext2D, cam: Camera, state: SimState, scale: number): void {
  for (const vehicle of state.vehicles) {
    if (vehicle.direction !== 1 || vehicle.missed) continue;
    if (vehicle.state !== "tracking" && vehicle.state !== "cued") continue;
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;
    for (const dx of [-0.5, 0.5]) {
      for (const dy of [0, 1]) {
        for (const dz of [-0.5, 0.5]) {
          const p = project(cam, v(vehicle.x + dx * vehicle.width, 0.25 + dy * vehicle.height, vehicle.z + dz * vehicle.length));
          if (p === null) continue;
          minX = Math.min(minX, p[0]);
          minY = Math.min(minY, p[1]);
          maxX = Math.max(maxX, p[0]);
          maxY = Math.max(maxY, p[1]);
        }
      }
    }
    if (!Number.isFinite(minX)) continue;
    const color = vehicle.state === "cued" ? COLORS.red : COLORS.amber;
    ctx.strokeStyle = color;
    ctx.lineWidth = 2 * scale;
    ctx.strokeRect(minX, minY, maxX - minX, maxY - minY);
    const behind = Math.max(0, Math.round(-(vehicle.z + vehicle.length / 2)));
    pill(ctx, (minX + maxX) / 2, minY - 4 * scale, `${vehicle.kind} · approaching · ${behind} m`, color, scale);
  }
}

// ---------- Scene ----------

/** Exported for scripts/sim-check (projection tests). */
export function cameraFor(view: ViewMode, orbit: Orbit, width: number, height: number): Camera {
  if (view === "phone") {
    return makeCamera(PHONE_CAMERA.pos, PHONE_CAMERA.target, PHONE_CAMERA.fov, width, height);
  }
  if (view === "overhead") {
    // From above and slightly behind, so the rider rides up the screen and traffic comes from below.
    return makeCamera(v(-2.5, 78, -66), v(-2.5, 0, -24), 48, width, height);
  }
  const target = orbit.target ? v(orbit.target.x, orbit.target.y, orbit.target.z) : v(RIDER_X - 1.5, 0.8, -14);
  const pos = v(
    target.x + orbit.radius * Math.sin(orbit.azimuth) * Math.cos(orbit.elevation),
    target.y + orbit.radius * Math.sin(orbit.elevation),
    target.z + orbit.radius * Math.cos(orbit.azimuth) * Math.cos(orbit.elevation),
  );
  return makeCamera(pos, target, 52, width, height);
}

export function drawScene(
  ctx: CanvasRenderingContext2D,
  state: SimState,
  view: ViewMode,
  orbit: Orbit,
  width: number,
  height: number,
  scale: number,
  options: SceneOptions = {},
): void {
  const detector = options.detector ?? true;
  const sky = ctx.createLinearGradient(0, 0, 0, height);
  sky.addColorStop(0, COLORS.sky);
  sky.addColorStop(0.55, COLORS.horizon);
  sky.addColorStop(1, COLORS.sky);
  ctx.fillStyle = sky;
  ctx.fillRect(0, 0, width, height);

  const pose = options.camera;
  const cam = pose ? makeCamera(pose.pos, pose.target, pose.fov, width, height) : cameraFor(view, orbit, width, height);
  drawGround(ctx, cam, state, view !== "phone" && detector, detector);

  const faces: Face[] = [];
  // Buildings on the camera's side would block the road, except when looking along it from the bike.
  const alongRoad = view === "phone" || (pose !== undefined && Math.abs(cam.pos.x - RIDER_X) < 1.5);
  const buildingSides = view === "orbit" && !alongRoad ? [cam.pos.x > RIDER_X ? -1 : 1] : [-1, 1];
  addBuildings(faces, cam, state.riderDistance, buildingSides);
  for (const vehicle of state.vehicles) addVehicle(faces, cam, vehicle, detector);
  if (view !== "phone" && (options.showRider ?? true)) addRider(faces, cam, fallAmount(state), options.phoneMount ?? 1);
  drawFaces(ctx, cam, faces);

  if (view === "phone") {
    if (detector) drawDetections(ctx, cam, state, scale);
    // The rear camera looks backward, so the rider's left is on the right of this image.
    ctx.font = `700 ${11 * scale}px ui-sans-serif, system-ui, sans-serif`;
    ctx.fillStyle = COLORS.muted;
    ctx.textBaseline = "bottom";
    ctx.textAlign = "left";
    ctx.fillText("← RIDER'S RIGHT", 14 * scale, height - 12 * scale);
    ctx.textAlign = "right";
    ctx.fillText("RIDER'S LEFT →", width - 14 * scale, height - 12 * scale);
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    ctx.fillStyle = COLORS.accent;
    ctx.fillText(options.cameraTag ?? "● REAR CAMERA · SIMULATED", 14 * scale, 12 * scale);
  } else if (detector) {
    drawLabels(ctx, cam, state, scale);
  }

  if ((detector && cueActive(state)) || state.crash.phase === "countdown") {
    ctx.strokeStyle = "rgb(255 90 79 / 70%)";
    ctx.lineWidth = 6 * scale;
    ctx.strokeRect(3 * scale, 3 * scale, width - 6 * scale, height - 6 * scale);
  }
}
