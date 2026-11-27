// Skilsmisse-indeks: hvilke familier (ægteskaber) der er opløst, og hvornår. Nøglen er family-id'et UDEN »f«.
// Tre tilstande for et par: skilt (Skilsmisse), ikke skilt (null) og ukendt (undefined, når opslaget ikke er hentet
// eller fejlede) — ukendt må aldrig vises som »ikke skilt« (fail-closed).
import { fmtDagDato } from './vielse';
import type { Model } from './types';

export type Skilsmisse = { dateMin: string | null; dateMax: string | null };
export type Skilsmisser = Record<string, Skilsmisse>;

type Id = number | string;

// Sammenstiller fact (familie, skilsmisse) → conclusion (valgt påstand) → assertion (datoer). Konklusioner uden kendt
// fact eller uden fundet påstand springes over.
export function byggSkilsmisser(
  facts: readonly { id: Id; subjekt_id: Id }[],
  konkl: readonly { target_id: Id; valgt_assertion_id: Id | null }[],
  assertions: readonly { id: Id; date_min: string | null; date_max: string | null }[],
): Skilsmisser {
  const familieByFact = new Map(facts.map((f) => [String(f.id), String(f.subjekt_id)]));
  const assertionById = new Map(assertions.map((a) => [String(a.id), a]));
  const ud: Skilsmisser = {};
  for (const c of konkl) {
    const fam = familieByFact.get(String(c.target_id));
    const a = c.valgt_assertion_id == null ? undefined : assertionById.get(String(c.valgt_assertion_id));
    if (fam && a) ud[fam] = { dateMin: a.date_min ?? null, dateMax: a.date_max ?? null };
  }
  return ud;
}

// Parrets skilsmisse: den første skilte familie parret har (samme par kan stå i flere familier, fx samme_som-kopier).
// Parret er uordnet. undefined = ukendt, null = ikke skilt.
export function parSkilsmisse(model: Model, a: string, b: string): Skilsmisse | null | undefined {
  const s = model.skilsmisser;
  if (s == null) return undefined;
  // unionById bærer id'er før samme_som-foldning; sammenlign på kanoniske id'er.
  const canon = (id: string) => model.canonicalIdById?.[id] ?? id;
  const ca = canon(a);
  const cb = canon(b);
  for (const u of Object.values(model.indexes.unionById)) {
    if (!u.id.startsWith('f') || u.p2 == null) continue;
    const p1 = canon(u.p1);
    const p2 = canon(u.p2);
    const par = (p1 === ca && p2 === cb) || (p1 === cb && p2 === ca);
    const hit = par ? s[u.id.slice(1)] : undefined;
    if (hit) return hit;
  }
  return null;
}

const AAR = /^(\d{3,4})-/;

// »skilt 12. okt. 1901« (dag), »skilt 1901« (år) eller »skilt«. Dag kun når begge ender er samme dag; år når begge
// ender er samme år; ellers (ukendt eller spredt dato) blot »skilt«.
export function fmtSkilt(s: Skilsmisse, form: 'dag' | 'aar' | 'ord'): string {
  if (form === 'ord' || !s.dateMin || !s.dateMax) return 'skilt';
  if (form === 'dag' && s.dateMin === s.dateMax) {
    const dag = fmtDagDato(s.dateMin);
    if (dag) return `skilt ${dag}`;
  }
  const a = AAR.exec(s.dateMin);
  const b = AAR.exec(s.dateMax);
  return a && b && a[1] === b[1] ? `skilt ${Number(a[1])}` : 'skilt';
}
