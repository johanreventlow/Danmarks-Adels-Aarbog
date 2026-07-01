// Bygger den flade visningsmodel (Model) til publikums-web: persons + unions + parentChild
// → buildModel. Lean udgave af mobile/src/data/load.ts (kun det stamtræ + slægtskabsfinder
// behøver — ikke Aux/godser/våben). Rolle-vokab: partner = forælder-par, barn = blodslægt.
import { supabase } from '../supabase';
import { buildModel } from './buildModel';
import { fmtYears, parseYear } from './fields';
import { getAll } from './paginate';
import { normalizeKoen, normalizeKonfidens, type AppPerson, type Db, type Model, type ModelPerson, type ParentChild, type Union } from './types';

const PARTNER_ROLLER = ['partner'];
// KUN blodslægt ('barn') bliver en forælder→barn-kant — matcher mobile/src/data/load.ts og
// holder slægtskabsfinderen blod-baseret. adopteret_/pleje-/stedbarn (som redaktionen kan se)
// indgår bevidst IKKE i stamtræet/finderen; de er ikke blodslægt.
const BARN_ROLLE = 'barn';

// Børn af en person som ModelPerson[] (childIdx er Sets). Delt af stamtræ-visningen.
export function childrenOf(model: Model, id: string): ModelPerson[] {
  return [...(model.indexes.childIdx[id] ?? new Set<string>())]
    .map((cid) => model.byId[cid])
    .filter(Boolean) as ModelPerson[];
}

type RawPerson = {
  id: number | string; visning_navn: string | null; visning_foedt: string | null;
  visning_doed: string | null; visning_titel: string | null; koen: string | null; privat: boolean | null;
};
type RawMember = { family_id: number | string; person_id: number | string; rolle: string | null; ordinal: number | null; konfidens: string | null };

// Sorterer forældre (partner-rolle-medlemmer af en familie) så far kommer før mor —
// DAA er patrilineær, linje/nr følger mandslinjen. `ordinal` er ægteskabs-nummer
// (1./2. ægteskab for DEN person), ikke en far/mor-markør: to forældre har typisk
// begge ordinal=1 for deres respektive første ægteskab, så en ren ordinal-sortering
// er vilkårlig og kan lige så godt vise mor som far i stamtræets forælder-slot.
// Kun tie-breaker for to forældre af samme/ukendt køn. Matcher mobile/src/data/load.ts.
export function compareParentOrder(
  a: { person_id: number | string; ordinal: number | null },
  b: { person_id: number | string; ordinal: number | null },
  koenById: Record<string, string | null>,
): number {
  const rank = (k: string | null) => (k === 'mand' ? 0 : k === 'kvinde' ? 1 : 2);
  const koenDiff = rank(koenById[String(a.person_id)] ?? null) - rank(koenById[String(b.person_id)] ?? null);
  return koenDiff !== 0 ? koenDiff : (a.ordinal ?? 0) - (b.ordinal ?? 0);
}

export async function loadModel(): Promise<Model> {
  const [persons, members] = await Promise.all([
    getAll<RawPerson>(() => supabase.from('person').select('id,visning_navn,visning_foedt,visning_doed,visning_titel,koen,privat')),
    getAll<RawMember>(() => supabase.from('family_member').select('family_id,person_id,rolle,ordinal,konfidens')),
  ]);

  const appPersons: AppPerson[] = persons.map((p) => ({
    id: String(p.id),
    name: p.visning_navn ?? '(uden navn)',
    born: parseYear(p.visning_foedt),
    died: parseYear(p.visning_doed),
    years: fmtYears(p.visning_foedt, p.visning_doed),
    title: p.visning_titel ?? '',
    bio: '',
    privat: Boolean(p.privat),
    koen: normalizeKoen(p.koen),
  }));

  // koen pr. person — bruges KUN til at afgøre forælder-rækkefølge nedenfor (ordinal er
  // ægteskabs-nummer, ikke far/mor-markør; to forældre i samme familie har typisk begge
  // ordinal=1 for deres respektive første ægteskab, så en ordinal-sortering er vilkårlig).
  const koenById: Record<string, string | null> = {};
  appPersons.forEach((p) => { koenById[p.id] = p.koen ?? null; });

  // Familie-medlemmer → unions (partner × partner) + parentChild (partner → barn).
  const byFam: Record<string, RawMember[]> = {};
  members.forEach((m) => { (byFam[String(m.family_id)] ??= []).push(m); });
  const unions: Union[] = [];
  const parentChild: ParentChild[] = [];
  Object.keys(byFam).forEach((fid) => {
    const mem = byFam[fid];
    const parents = mem
      .filter((m) => PARTNER_ROLLER.includes(String(m.rolle ?? '').toLowerCase()))
      .sort((a, b) => compareParentOrder(a, b, koenById));
    const children = mem
      .filter((m) => String(m.rolle ?? '').toLowerCase() === BARN_ROLLE)
      .sort((a, b) => (a.ordinal ?? 0) - (b.ordinal ?? 0));
    if (parents.length) {
      unions.push({ id: 'f' + fid, p1: String(parents[0].person_id), p2: parents[1] ? String(parents[1].person_id) : null, p2_name: null, year: null });
    }
    children.forEach((c) => {
      const konfidens = normalizeKonfidens(c.konfidens);
      parents.forEach((pa) => parentChild.push({ child: String(c.person_id), parent: String(pa.person_id), union: 'f' + fid, konfidens }));
    });
  });

  const db: Db = { persons: appPersons, unions, parentChild };
  return buildModel(db);
}
