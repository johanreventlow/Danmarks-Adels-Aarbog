// Slægtskabs-algoritme — port 1:1 af v2-designet (linje 1068-1090, 1418-1450).
// ancestorsInclusive → lcaId (laveste fælles ane) → chainTo (kæde til LCA) →
// relationshipLabel (generations-afstande → danske etiketter). Rene funktioner (testbare).
import type { Model, ModelPerson } from './types';

export function ancestorsInclusive(model: Model, id: string): ModelPerson[] {
  const out: ModelPerson[] = [];
  let c: ModelPerson | undefined = model.byId[id];
  let guard = 0;
  while (c && guard < 40) {
    out.push(c);
    c = c.parentId ? model.byId[c.parentId] : undefined;
    guard++;
  }
  return out;
}

// Laveste fælles ane. null hvis ingen fælles ane (adskilte grene).
export function lcaId(model: Model, a: string, b: string): string | null {
  const A = new Set(ancestorsInclusive(model, a).map((x) => x.id));
  const B = ancestorsInclusive(model, b);
  for (const x of B) {
    if (A.has(x.id)) return x.id;
  }
  return null;
}

// Kæde fra person op til (og med) LCA.
export function chainTo(model: Model, id: string, lca: string): ModelPerson[] {
  const out: ModelPerson[] = [];
  let c: ModelPerson | undefined = model.byId[id];
  let guard = 0;
  while (c && guard < 40) {
    out.push(c);
    if (c.id === lca) break;
    c = c.parentId ? model.byId[c.parentId] : undefined;
    guard++;
  }
  return out;
}

// Oversæt generations-afstande (d1 fra A til LCA, d2 fra B til LCA) til dansk etiket.
export function relationshipLabel(d1: number, d2: number): string {
  if (d1 === 0 && d2 === 0) return 'Samme person';
  if (d1 === 0 || d2 === 0) {
    const n = d1 + d2;
    const asc = [
      'Forælder & barn',
      'Bedsteforælder & barnebarn',
      'Oldeforælder & oldebarn',
      'Tipoldeforælder & tipoldebarn',
      'Tip-tipoldeforælder & efterkommer',
    ];
    return n - 1 < asc.length ? asc[n - 1] : 'Direkte forfædre-linje';
  }
  const minD = Math.min(d1, d2);
  const rem = Math.abs(d1 - d2);
  const deg = minD - 1;
  if (deg === 0) {
    if (rem === 0) return 'Søskende';
    if (rem === 1) return 'Onkel/tante & niece/nevø';
    return 'Grandonkel/-tante & grandniece/-nevø';
  }
  let s = deg + '. grads fætter/kusine';
  if (rem > 0) s += ' · ' + rem + ' gang' + (rem > 1 ? 'e' : '') + ' forskudt';
  return s;
}

export type RelationStep = {
  id: string;
  name: string;
  years: string;
  isLca: boolean;
};

export type RelationResult = {
  found: boolean;
  label: string;
  lcaId: string | null;
  lcaName: string;
  steps: RelationStep[];
};

// Beregn slægtskab mellem to personer: etiket + trin-for-trin-kæde (A → LCA → B).
export function computeRelationship(model: Model, aId: string, bId: string): RelationResult {
  const a = model.byId[aId];
  const b = model.byId[bId];
  if (!a || !b) return { found: false, label: '', lcaId: null, lcaName: '', steps: [] };
  if (a.id === b.id) {
    return { found: true, label: 'Samme person', lcaId: a.id, lcaName: a.name, steps: [] };
  }
  const L = lcaId(model, a.id, b.id);
  if (!L) {
    return { found: false, label: 'Ingen påvist forbindelse', lcaId: null, lcaName: '', steps: [] };
  }
  const cA = chainTo(model, a.id, L);
  const cB = chainTo(model, b.id, L);
  const d1 = cA.length - 1;
  const d2 = cB.length - 1;
  const label = relationshipLabel(d1, d2);
  const down = cB.slice(0, -1).reverse();
  const full = cA.concat(down);
  const lcaIndex = cA.length - 1;
  const steps: RelationStep[] = full.map((p, idx) => ({
    id: p.id,
    name: p.name,
    years: p.years,
    isLca: idx === lcaIndex,
  }));
  return { found: true, label, lcaId: L, lcaName: model.byId[L]?.name ?? '', steps };
}
