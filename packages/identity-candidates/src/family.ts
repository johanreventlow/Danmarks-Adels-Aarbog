export type FamilyContext = {
  principal_person_id: number; marriage_ordinal: number; marriage_claims_in_post: number;
  families: Array<{ family_id: number; ordinal: number | null; konfidens: string[]; partners: number[] }>;
};
export type FamilyEval = { partners: number[]; target: number | null; structureOk: boolean; reason: string; ordinalMatch: Set<number> };

// Spec §6.1/§6.2(b): samme strukturelle regler som kernen efterprøver. Generatorens svar er
// kun en sorteringshjælp — kernen genberegner det hele under rækkelåse.
export function evaluateFamily(ctx: FamilyContext): FamilyEval {
  const partners = [...new Set(ctx.families.flatMap((x) => x.partners))].sort((a, b) => a - b);
  const no = (reason: string): FamilyEval => ({ partners, target: null, structureOk: false, reason, ordinalMatch: new Set() });
  if (ctx.marriage_claims_in_post !== ctx.families.length) return no('count_mismatch');
  if (ctx.families.length > 1 && ctx.families.some((x) => x.ordinal == null)) return no('ordinal_null');
  const chosen = ctx.families.length === 1 ? ctx.families : ctx.families.filter((x) => x.ordinal === ctx.marriage_ordinal);
  if (chosen.length !== 1) return no('ordinal_no_match');
  const fam = chosen[0];
  if (fam.partners.length !== 1) return no('partner_count');
  if (fam.konfidens.some((k) => k === 'omstridt' || k === 'formodet')) return no('konfidens');
  return { partners, target: fam.partners[0], structureOk: true, reason: 'ok', ordinalMatch: new Set(fam.partners) };
}

// Union-find over samme_som-par; repræsentant = laveste id (rangeringen vælger den synlige).
export function clusterMap(pairs: Array<[number, number]>): Map<number, number> {
  const parent = new Map<number, number>();
  const find = (x: number): number => { const p = parent.get(x) ?? x; if (p === x) return x; const r = find(p); parent.set(x, r); return r; };
  for (const [a, b] of pairs) { const ra = find(a), rb = find(b); if (ra !== rb) parent.set(Math.max(ra, rb), Math.min(ra, rb)); }
  const out = new Map<number, number>();
  for (const x of new Set(pairs.flat())) out.set(x, find(x));
  return out;
}
