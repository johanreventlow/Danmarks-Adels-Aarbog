// Søgesiden (webredesign fase 6b, tegningen »Søgeresultater (web)«) som rene funktioner: filtre i adressen,
// match og fremhævning, levetid og forslag til stavemåder.
import { compareDanish, foldToken } from '@daa/core';
import { linjeNavnFor } from './slaegtskab';
import type { EstateItem } from './public';
import type { Model } from './types';

export type SoegType = 'alt' | 'personer' | 'besiddelser';
export type SoegSort = 'match' | 'navn' | 'foedt';
export type SoegFiltre = {
  q: string; type: SoegType; linje: string | null;
  fra: number | null; til: number | null; // levetid, hele år
  sort: SoegSort; bm: boolean;
};
export const STANDARD_FILTRE: SoegFiltre = { q: '', type: 'alt', linje: null, fra: null, til: null, sort: 'match', bm: false };

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

export type Maerke = [number, number]; // [start, slut) i navnet
type Ramt = { rang: number; maerker: Maerke[] };

const ORD = /[\s,.()[\]-]+/;
const ordAf = (s: string) => s.toLowerCase().split(ORD).filter(Boolean);
// Første forekomst, helst i begyndelsen af et ord.
function forekomst(navn: string, t: string): number {
  let i = navn.indexOf(t);
  let foerste = i;
  while (i > 0 && !ORD.test(navn[i - 1])) i = navn.indexOf(t, i + 1);
  return i >= 0 ? i : foerste;
}

// Match af et navn. Rang: 0 navnet begynder med søgeordet, 1 et ord gør, 2 navnet indeholder det, 3 alle søgeordene
// står i navnet, 4 kun ens efter stavemåde-foldning (Detlev/Detlef, Reventlov/Reventlow). Kun bogstavret
// genfundne søgeord fremhæves; et foldet match vises uden fremhævning.
export function matchNavn(navn: string, q: string): Ramt | null {
  const n = navn.toLowerCase();
  const s = q.trim().toLowerCase();
  if (!s) return { rang: 0, maerker: [] };
  if (n.includes(s)) {
    const i = forekomst(n, s);
    return { rang: i === 0 ? 0 : !ORD.test(n[i - 1]) ? 2 : 1, maerker: [[i, i + s.length]] };
  }
  const toks = ordAf(s);
  const maerker: Maerke[] = [];
  for (const t of toks) {
    if (!n.includes(t)) { maerker.length = 0; break; }
    const i = forekomst(n, t);
    maerker.push([i, i + t.length]);
  }
  if (maerker.length === toks.length && toks.length > 0) return { rang: 3, maerker: maerker.sort((a, b) => a[0] - b[0]) };
  const navnFold = ordAf(n).map(foldToken);
  const qFold = toks.map(foldToken);
  if (qFold.length && qFold.every((t) => navnFold.some((w) => w.startsWith(t)))) return { rang: 4, maerker: [] };
  return null;
}

// Levetidens spænd i hele år: fra det tidligste mulige fødselsår til det seneste mulige dødsår. En usikker dato
// tæller i hele sin bredde (»† 1406/1410« → 1410). Mangler det ene endepunkt, regnes et menneskeliv (100 år) fra
// det andet, så en person med kun dødsår 1708 rører 1608–1708. Uden årstal: null (kan ikke placeres i en periode).
// »ca. 1660« er ét år; bogen siger ikke, hvor bredt »ca.« er.
export const LIVSLAENGDE = 100;
type Leveaar = { born: number | null; died: number | null; foedtSpaend?: [number, number] | null; doedSpaend?: [number, number] | null };
export function levetid(p: Leveaar): [number, number] | null {
  const f = p.foedtSpaend ?? (p.born != null ? [p.born, p.born] : null);
  const d = p.doedSpaend ?? (p.died != null ? [p.died, p.died] : null);
  const lo = f?.[0] ?? (d ? d[0] - LIVSLAENGDE : null);
  const hi = d?.[1] ?? (f ? f[1] + LIVSLAENGDE : null);
  return lo == null || hi == null ? null : [lo, hi];
}
export function roererPerioden(p: Leveaar, fra: number | null, til: number | null): boolean | null {
  if (fra == null && til == null) return true;
  const s = levetid(p);
  if (!s) return null;
  return (til == null || s[0] <= til) && (fra == null || s[1] >= fra);
}

export type PersonRaekke = {
  id: string; name: string; years: string; title: string; born: number | null;
  linje: string | null; maerker: Maerke[]; rang: number;
};
export type GodsRaekke = { id: string; navn: string; slags: string; ejere: number; maerker: Maerke[]; rang: number };
export type SoegResultat = {
  personer: PersonRaekke[]; godser: GodsRaekke[];
  udenAar: number; // personer, der matcher alt andet, men ikke kan placeres i perioden
};

const sortér = <R extends { rang: number }>(rows: R[], sort: SoegSort, navn: (r: R) => string, born: (r: R) => number | null) =>
  rows.sort((a, b) =>
    sort === 'foedt' ? (born(a) ?? 99999) - (born(b) ?? 99999) || compareDanish(navn(a), navn(b))
      : sort === 'match' ? a.rang - b.rang || compareDanish(navn(a), navn(b))
        : compareDanish(navn(a), navn(b)));

export function soeg(model: Model, estates: EstateItem[], f: SoegFiltre, bogmaerker?: ReadonlySet<string>): SoegResultat {
  const personer: PersonRaekke[] = [];
  let udenAar = 0;
  for (const p of model.persons) {
    // Et delt link med bm=1 hos en læser uden bogmærker: filteret gælder ikke (ellers en tom side uden forklaring).
    if (f.bm && bogmaerker && !bogmaerker.has(p.id)) continue;
    if (f.linje && !(model.lineage?.byPerson[p.id] ?? []).includes(f.linje)) continue;
    const m = matchNavn(p.name, f.q);
    if (!m) continue;
    const r = roererPerioden(p, f.fra, f.til);
    if (r === null) { udenAar++; continue; }
    if (!r) continue;
    personer.push({ id: p.id, name: p.name, years: p.years, title: p.title, born: p.born, linje: linjeNavnFor(model, p.id), maerker: m.maerker, rang: m.rang });
  }
  // Godser kender hverken linje, levetid eller bogmærker; filtrerer man på dem, søges der kun i personer. Uden
  // søgeord er siden personregistret (Personer i hovedmenuen); godserne kommer kun med, når man vælger dem.
  const kunPersoner = (f.bm && !!bogmaerker) || f.linje != null || f.fra != null || f.til != null;
  const godser: GodsRaekke[] = [];
  if (!kunPersoner && (f.q.trim() !== '' || f.type === 'besiddelser')) {
    for (const e of estates) {
      const m = matchNavn(e.navn, f.q);
      if (m) godser.push({ id: e.id, navn: e.navn, slags: e.slags, ejere: e.ownerCount, maerker: m.maerker, rang: m.rang });
    }
  }
  return {
    personer: sortér(personer, f.sort, (r) => r.name, (r) => r.born),
    godser: sortér(godser, f.sort === 'foedt' ? 'navn' : f.sort, (r) => r.navn, () => null),
    udenAar,
  };
}

// Afstand mellem to ord (Levenshtein), til stavemåde-forslag.
function afstand(a: string, b: string): number {
  const d = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    let diag = d[0];
    d[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const op = d[j];
      d[j] = Math.min(d[j] + 1, d[j - 1] + 1, diag + (a[i - 1] === b[j - 1] ? 0 : 1));
      diag = op;
    }
  }
  return d[b.length];
}

// Andre stavemåder af søgeordet: ord fra navnene, der ligner et søgeord (højst én fejl pr. fire bogstaver, mindst
// én), men som søgningen ikke allerede rammer (ikke samme ord, ikke ens efter foldning, ikke indeholder søgeordet).
// Bruges som »Mente du …?«, når intet findes, og som »Andre stavemåder«, når noget findes: »Reventlow« ↔ »Reventlou«.
// Et søgeord, der intet navn rammer, skiftes først ud (»Otto Revenlow« → »Otto Reventlow«); ellers det første med
// naboer. Ord under fem bogstaver får ingen naboer: én fejl i »Otto« eller »Ida« er et andet navn, ikke en stavemåde.
// Højst tre forslag.
// Et par, hvor kun det ene ord ender på -a/-e, er typisk to navne (Christian/Christina, Benedict/Benedicte), ikke
// to stavemåder af ét; de foreslås ikke.
export const MIN_STAVEORD = 5;
const kvindeEndelse = (w: string) => /[ae]$/.test(w);
export function stavemaader(navne: readonly string[], q: string, n = 3): string[] {
  const toks = q.trim().split(/\s+/).filter(Boolean);
  if (!toks.length) return [];
  const ordbog = new Map<string, string>(); // lille → som i bogen
  for (const navn of navne) for (const w of navn.split(ORD)) if (w.length >= 3 && !ordbog.has(w.toLowerCase())) ordbog.set(w.toLowerCase(), w);
  const rammer = (t: string) => { const tf = foldToken(t); return [...ordbog.keys()].some((k) => k.includes(t) || foldToken(k).startsWith(tf)); };
  const raekkefoelge = toks.map((t, i) => ({ i, ingen: !rammer(t.toLowerCase()) })).sort((a, b) => Number(b.ingen) - Number(a.ingen) || a.i - b.i).map((x) => x.i);
  for (const i of raekkefoelge) {
    if (toks[i].length < MIN_STAVEORD) continue;
    const lt = toks[i].toLowerCase();
    const tf = foldToken(lt);
    const max = Math.max(1, Math.floor(lt.length / 4));
    const naboer = [...ordbog.entries()]
      .filter(([k]) => k !== lt && !k.includes(lt) && foldToken(k) !== tf && kvindeEndelse(k) === kvindeEndelse(lt))
      .map(([k, v]) => ({ v, d: afstand(lt, k) }))
      .filter((x) => x.d <= max)
      .sort((a, b) => a.d - b.d || compareDanish(a.v, b.v))
      .slice(0, n);
    if (naboer.length) return naboer.map((x) => toks.map((t, j) => (j === i ? x.v : t)).join(' '));
  }
  return [];
}
