import {
  boundsOf,
  distanceKm,
  estatePoints,
  filterByKind,
  filterByLineage,
  filterByYearRange,
  lifeJourney,
  nearbyPoints,
} from '../geoSelectors';
import type { Geo, GeoKind, GeoPoint } from '../types';

// Hjælper: byg et GeoPoint med defaults.
const pt = (over: Partial<GeoPoint> & { kind: GeoKind; lat: number; lon: number }): GeoPoint => ({
  placeId: 'p',
  navn: 'Sted',
  personId: null,
  estateId: null,
  unionId: null,
  year: null,
  ...over,
});
const geoOf = (points: GeoPoint[], byPerson: Record<string, GeoPoint[]> = {}, byEstate = {}): Geo => ({
  points,
  byPerson,
  byEstate,
});

test('distanceKm: samme punkt = 0; 1° breddegrad ≈ 111 km', () => {
  expect(distanceKm({ lat: 55, lon: 12 }, { lat: 55, lon: 12 })).toBe(0);
  const d = distanceKm({ lat: 0, lon: 0 }, { lat: 1, lon: 0 });
  expect(d).toBeGreaterThan(110);
  expect(d).toBeLessThan(112);
});

test('nearbyPoints: filtrerer på radius og sorterer nærmest først', () => {
  const near = pt({ kind: 'estate', lat: 55.01, lon: 12.0, placeId: 'near' }); // ~1 km
  const mid = pt({ kind: 'estate', lat: 55.1, lon: 12.0, placeId: 'mid' }); // ~11 km
  const far = pt({ kind: 'estate', lat: 56.0, lon: 12.0, placeId: 'far' }); // ~111 km
  const res = nearbyPoints(geoOf([far, mid, near]), { lat: 55, lon: 12 }, 20);
  expect(res.map((r) => r.point.placeId)).toEqual(['near', 'mid']); // far > 20 km væk udeladt
  expect(res[0].km).toBeLessThan(res[1].km);
});

test('estatePoints: returnerer godsmarkørerne fra byEstate', () => {
  const e = pt({ kind: 'estate', lat: 1, lon: 1, estateId: '10' });
  expect(estatePoints(geoOf([e], {}, { '10': e }))).toEqual([e]);
});

test('lifeJourney: ordner en persons punkter fødsel→…→begravelse', () => {
  const born = pt({ kind: 'fødsel', lat: 1, lon: 1, personId: 'x', year: 1644 });
  const married = pt({ kind: 'vielse', lat: 2, lon: 2, personId: null, year: 1670 });
  const died = pt({ kind: 'død', lat: 3, lon: 3, personId: 'x', year: 1708 });
  const buried = pt({ kind: 'begravelse', lat: 4, lon: 4, personId: 'x' });
  const geo = geoOf([], { x: [died, buried, born, married] });
  expect(lifeJourney(geo, 'x').map((p) => p.kind)).toEqual(['fødsel', 'vielse', 'død', 'begravelse']);
  expect(lifeJourney(geo, 'ukendt')).toEqual([]);
});

test('filterByKind: beholder kun de valgte typer', () => {
  const pts = [pt({ kind: 'fødsel', lat: 1, lon: 1 }), pt({ kind: 'død', lat: 2, lon: 2 }), pt({ kind: 'estate', lat: 3, lon: 3 })];
  expect(filterByKind(pts, ['fødsel', 'død']).map((p) => p.kind)).toEqual(['fødsel', 'død']);
});

test('filterByLineage: person-punkter filtreres; gods/vielse (personId null) udelades default', () => {
  const a = pt({ kind: 'fødsel', lat: 1, lon: 1, personId: 'a' });
  const b = pt({ kind: 'fødsel', lat: 2, lon: 2, personId: 'b' });
  const estate = pt({ kind: 'estate', lat: 3, lon: 3, personId: null });
  const linjeByPerson = { a: ['I'], b: ['II'] };
  expect(filterByLineage([a, b, estate], linjeByPerson, 'I')).toEqual([a]);
  // includeNonPerson tager gods/vielse med
  expect(filterByLineage([a, b, estate], linjeByPerson, 'I', { includeNonPerson: true })).toEqual([a, estate]);
});

test('filterByYearRange: åbne grænser + udeladelse af år-løse punkter', () => {
  const y1644 = pt({ kind: 'fødsel', lat: 1, lon: 1, year: 1644 });
  const y1708 = pt({ kind: 'død', lat: 2, lon: 2, year: 1708 });
  const noYear = pt({ kind: 'begravelse', lat: 3, lon: 3, year: null });
  const all = [y1644, y1708, noYear];
  expect(filterByYearRange(all, null, null)).toEqual(all); // begge åbne → uændret (inkl. år-løse)
  expect(filterByYearRange(all, 1700, null)).toEqual([y1708]); // ≥1700; år-løs udeladt
  expect(filterByYearRange(all, null, 1700)).toEqual([y1644]); // ≤1700
  expect(filterByYearRange(all, 1600, 1650)).toEqual([y1644]);
});

test('boundsOf: null ved tom; korrekt bbox ellers', () => {
  expect(boundsOf([])).toBeNull();
  const bb = boundsOf([pt({ kind: 'estate', lat: 55, lon: 12 }), pt({ kind: 'estate', lat: 54, lon: 13 })]);
  expect(bb).toEqual({ minLat: 54, minLon: 12, maxLat: 55, maxLon: 13 });
});
