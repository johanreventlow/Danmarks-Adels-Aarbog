// Bygger den flade visningsmodel (Model) til publikums-web: persons + unions + parentChild
// → buildModel. Lean udgave af mobile/src/data/load.ts (kun det stamtræ + slægtskabsfinder
// behøver — ikke Aux/godser/våben). Rolle-vokab: partner = forælder-par, barn = blodslægt.
import { supabase } from '../supabase';
import { buildModel } from './buildModel';
import { collapseSameAs } from './collapseSameAs';
import { buildLineage } from './lineage';
import { buildSources } from './sources';
import { fmtYears, parseYear } from './fields';
import { getAll } from './paginate';
import { normalizeKoen, normalizeKonfidens, type AppPerson, type Db, type Model, type ModelPerson, type ParentChild, type RawExtId, type RawLineage, type RawSource, type Union } from './types';

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

// Forældre af en person som ModelPerson[] (fra primær fødselsfamilie, far før mor jf.
// compareParentOrder i loaderen). Symmetrisk med childrenOf; bruges af ane-drillen i variant B.
// Matcher mobilens selectors.parentsOf.
export function parentsOf(model: Model, id: string): ModelPerson[] {
  return (model.indexes.parentsByChild[id] ?? [])
    .map((pid) => model.byId[pid])
    .filter(Boolean) as ModelPerson[];
}

type RawPerson = {
  id: number | string; visning_navn: string | null; visning_fuldt_navn: string | null; visning_foedt: string | null;
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

// Returnerer Model med samme_som-alias-map (canonicalIdById) + proveniens (mergedFrom på
// model.byId) stampet på. collapse: default true; redaktion slår FRA (collapse:false) for at slå
// navne op på de rå DB-poster (et foldet alias ville ellers mangle i model.byId) — spec §8.
export async function loadModel(opts?: { collapse?: boolean }): Promise<Model> {
  const [persons, members, extIds, lineageRows, sources, sameAsRel, approvedConc] = await Promise.all([
    getAll<RawPerson>(() => supabase.from('person').select('id,visning_navn,visning_fuldt_navn,visning_foedt,visning_doed,visning_titel,koen,privat')),
    getAll<RawMember>(() => supabase.from('family_member').select('family_id,person_id,rolle,ordinal,konfidens')),
    // Linje/nr pr. person (grene) — tolerant: tabellen/kolonnerne kan mangle i ældre baser.
    // Review 15: log ved fejl, så en RLS/drifts-fejl ikke stiltiende ligner "ingen linjer"
    // (graceful degradation bevares, men degraderingen bliver synlig i konsol/telemetri).
    getAll<RawExtId>(() => supabase.from('person_external_id').select('person_id,source_id,linje,nr')).catch((e) => { console.warn('[loadModel] person_external_id utilgængelig — linjer/kilder degraderet:', e); return [] as RawExtId[]; }),
    // Linje-navne — lineage-tabellen findes måske ikke endnu (fallback til 'Linje {kode}').
    getAll<RawLineage>(() => supabase.from('lineage').select('source_id,kode,navn')).catch((e) => { console.warn('[loadModel] lineage utilgængelig — bruger linje-koder som navne:', e); return [] as RawLineage[]; }),
    // Kilder (trykt værk) — til "Kilde i Aarbogen" pr. person.
    getAll<RawSource>(() => supabase.from('source').select('id,slags,titel,udgave,ekstern')).catch((e) => { console.warn('[loadModel] source utilgængelig — Kilde-i-Aarbogen degraderet:', e); return [] as RawSource[]; }),
    // samme_som-relationer (person→person; subjekt=alias, objekt=kanonisk) + afklarede konklusioner.
    // Polymorf kobling (conclusion.target_type/target_id), ingen FK → hentes separat + matches i JS.
    getAll<{ id: number | string; subjekt_id: number | string; objekt_id: number | string }>(() =>
      supabase.from('relation').select('id,subjekt_id,objekt_id').eq('rolle', 'samme_som').eq('subjekt_type', 'person').eq('objekt_type', 'person'),
    ).catch((e) => { console.warn('[loadModel] samme_som-relationer utilgængelige — ingen collapse:', e); return [] as { id: number | string; subjekt_id: number | string; objekt_id: number | string }[]; }),
    getAll<{ target_id: number | string }>(() =>
      supabase.from('conclusion').select('target_id').eq('target_type', 'relation').eq('status', 'afklaret'),
    ).catch((e) => { console.warn('[loadModel] conclusion utilgængelig — ingen collapse:', e); return [] as { target_id: number | string }[]; }),
  ]);

  const appPersons: AppPerson[] = persons.map((p) => ({
    id: String(p.id),
    // Fallback til visning_navn er MIDLERTIDIG kompat (spec §4.9) — visning_fuldt_navn er NULL
    // for personer der endnu ikke er regenereret efter udledt-slægtsnavn-backfillen.
    name: p.visning_fuldt_navn ?? p.visning_navn ?? '(uden navn)',
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

  const rawDb: Db = { persons: appPersons, unions, parentChild };

  // samme_som-collapse FØR buildModel: fold flere person-rækker der er samme fysiske person til
  // ÉN kanonisk post (spec 2026-07-02). Kun afklarede identiteter foldes; konflikter karantæneres.
  const approved = new Set((approvedConc || []).map((c) => String(c.target_id)));
  const edges =
    opts?.collapse === false
      ? []
      : (sameAsRel || [])
          .filter((r) => approved.has(String(r.id)))
          .map((r) => ({ alias: String(r.subjekt_id), canonical: String(r.objekt_id) }));
  const extMap = new Map((extIds || []).map((x) => [String(x.person_id), { linje: x.linje, nr: x.nr }]));
  const collapsed = collapseSameAs(rawDb, edges, extMap);
  if (collapsed.quarantined.length) console.warn('[samme_som] karantæne (foldes ikke):', collapsed.quarantined);

  const model: Model = {
    ...buildModel(collapsed.db),
    lineage: buildLineage(extIds, lineageRows, collapsed.canonicalIdById),
    sourcesBy: buildSources(extIds, sources, collapsed.canonicalIdById),
    canonicalIdById: collapsed.canonicalIdById,
  };
  // Påfør proveniens på de foldede kanoniske personer (til badge i detalje-panelet).
  for (const [canon, prov] of Object.entries(collapsed.mergedFrom)) {
    if (model.byId[canon]) model.byId[canon].mergedFrom = prov;
  }
  return model;
}
