// Rene selektorer over Geo (kort), i @daa/core. Samme kontrakt som selectors.ts: rene,
// testbare funktioner som kort-fladerne kalder frem for at grave i geo-indekserne direkte.
import type { Geo, GeoKind, GeoPoint } from './types';

// Rækkefølge for et livskort: fakta ordnes kronologisk-tematisk (fødsel → … → begravelse).
// Alle GeoKind SKAL være med (estate optræder aldrig i byPerson, men holder typen udtømmende).
const LIFE_ORDER: Record<GeoKind, number> = {
  fødsel: 0,
  dåb: 1,
  vielse: 2,
  død: 3,
  bisættelse: 4,
  begravelse: 5,
  estate: 6,
};

// Godskort: alle gods-markører.
export function estatePoints(geo: Geo): GeoPoint[] {
  return Object.values(geo.byEstate);
}

// Livskort: én persons punkter, ordnet som en livsrejse (år bryder ties inden for samme kind).
export function lifeJourney(geo: Geo, personId: string): GeoPoint[] {
  return [...(geo.byPerson[personId] ?? [])].sort(
    (a, b) => LIFE_ORDER[a.kind] - LIFE_ORDER[b.kind] || (a.year ?? Infinity) - (b.year ?? Infinity),
  );
}

// Haversine-afstand i km mellem to koordinater. (Findes ikke andetsteds i repoet.)
const R_KM = 6371;
const toRad = (deg: number) => (deg * Math.PI) / 180;
export function distanceKm(a: { lat: number; lon: number }, b: { lat: number; lon: number }): number {
  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lon - a.lon);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R_KM * Math.asin(Math.min(1, Math.sqrt(h)));
}

// Nærhed ("landmarks nær dig"): punkter inden for radiusKm af origin, nærmest først.
export type NearbyPoint = { point: GeoPoint; km: number };
export function nearbyPoints(
  geo: Geo,
  origin: { lat: number; lon: number },
  radiusKm: number,
): NearbyPoint[] {
  return geo.points
    .map((point) => ({ point, km: distanceKm(origin, point) }))
    .filter((n) => n.km <= radiusKm)
    .sort((a, b) => a.km - b.km);
}

// Overbliks-filtre — rene array→array, så de kan kædes.
export function filterByKind(points: GeoPoint[], kinds: GeoKind[]): GeoPoint[] {
  const set = new Set(kinds);
  return points.filter((p) => set.has(p.kind));
}

// Filtrér på linje (I–V): behold punkter hvis person hører til `code`. Gods/vielse har
// personId=null → kan ikke linje-filtreres pr. person; udelades med mindre includeNonPerson.
export function filterByLineage(
  points: GeoPoint[],
  linjeByPerson: Record<string, string[]>,
  code: string,
  opts?: { includeNonPerson?: boolean },
): GeoPoint[] {
  return points.filter((p) =>
    p.personId ? (linjeByPerson[p.personId] ?? []).includes(code) : Boolean(opts?.includeNonPerson),
  );
}

// Tids-slider: behold punkter hvis år ligger i [from, to] (åbne grænser = null). Punkter uden
// år udelades når mindst én grænse er sat; med begge grænser null returneres alt uændret.
export function filterByYearRange(
  points: GeoPoint[],
  from: number | null,
  to: number | null,
): GeoPoint[] {
  if (from == null && to == null) return points;
  return points.filter(
    (p) => p.year != null && (from == null || p.year >= from) && (to == null || p.year <= to),
  );
}

// Bounding-box til at tilpasse kort-viewport. null hvis ingen punkter.
export type Bounds = { minLat: number; minLon: number; maxLat: number; maxLon: number };
export function boundsOf(points: GeoPoint[]): Bounds | null {
  if (!points.length) return null;
  let minLat = Infinity;
  let minLon = Infinity;
  let maxLat = -Infinity;
  let maxLon = -Infinity;
  for (const p of points) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lon < minLon) minLon = p.lon;
    if (p.lon > maxLon) maxLon = p.lon;
  }
  return { minLat, minLon, maxLat, maxLon };
}
