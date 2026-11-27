// Søgesiden (webredesign fase 6b, tegningen »Søgeresultater (web)«): filtrene i adressen. Match, levetid, filtre og
// stavemåder bor i @daa/core (mobil-paritet, bid 9) og re-eksporteres her, så web-imports er uændrede.
import type { SoegFiltre } from '@daa/core';

export {
  LIVSLAENGDE, MIN_STAVEORD, STANDARD_FILTRE, byggStaveordbog, levetid, matchNavn, roererPerioden, soeg, stavemaader,
} from '@daa/core';
export type {
  GodsRaekke, Maerke, PersonRaekke, SoegFiltre, SoegGods, SoegResultat, SoegSort, SoegType, Staveordbog,
} from '@daa/core';

const aar = (v: string | null): number | null => (v && /^-?\d{1,4}$/.test(v.trim()) ? parseInt(v, 10) : null);

export function soegFiltre(search: string): SoegFiltre {
  const qs = new URLSearchParams(search);
  const type = qs.get('type');
  const sort = qs.get('sort');
  return {
    q: qs.get('q') ?? '',
    // »godser« er fra før fase 7a (links fra 6b er ude) og betyder det samme.
    type: type === 'personer' || type === 'besiddelser' ? type : type === 'godser' ? 'besiddelser' : 'alt',
    linje: qs.get('linje') || null,
    fra: aar(qs.get('fra')), til: aar(qs.get('til')),
    sort: sort === 'navn' || sort === 'foedt' ? sort : 'match',
    bm: qs.get('bm') === '1',
  };
}

// Kun det, der afviger fra standarden, skrives i adressen (/soeg?q=Conrad, ikke en lang hale af tomme filtre).
export function soegSti(f: Partial<SoegFiltre>): string {
  const qs = new URLSearchParams();
  if (f.q) qs.set('q', f.q);
  if (f.type && f.type !== 'alt') qs.set('type', f.type);
  if (f.linje) qs.set('linje', f.linje);
  if (f.fra != null) qs.set('fra', String(f.fra));
  if (f.til != null) qs.set('til', String(f.til));
  if (f.sort && f.sort !== 'match') qs.set('sort', f.sort);
  if (f.bm) qs.set('bm', '1');
  const s = qs.toString();
  return s ? `/soeg?${s}` : '/soeg';
}
