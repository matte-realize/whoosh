/**
 * Thins a route to at most `maxPoints` points for overview drawing, keeping the first and last
 * point. Every point between is kept at an even stride. This is for display only: the overview
 * map draws many routes at once, and a few hundred points per route is plenty at that zoom.
 * Returns the input unchanged when it is already short enough.
 */
export function thinRoute(coordinates: [number, number][], maxPoints: number): [number, number][] {
  const limit = Math.max(2, Math.floor(maxPoints));
  if (coordinates.length <= limit) return coordinates;

  const stride = (coordinates.length - 1) / (limit - 1);
  const thinned: [number, number][] = [];
  for (let i = 0; i < limit - 1; i += 1) {
    thinned.push(coordinates[Math.round(i * stride)]);
  }
  thinned.push(coordinates[coordinates.length - 1]);
  return thinned;
}
