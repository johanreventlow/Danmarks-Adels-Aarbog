// Port af loadFromSupabase() fra design-HTML (linje 881-960), via supabase-js.
// Producerer mellem-formen db = {persons, unions, parentChild} + aux. buildModel kaldes
// SEPARAT bagefter (i storen) for at udlede parentId/spouse + indekser.
import { supabase, supabaseEnabled } from '../lib/supabase';
import { buildAux } from './buildAux';
import { fmtYears, parseYear } from './fields';
import type {
  Aux,
  Db,
  ParentChild,
  RawEstate,
  RawExtId,
  RawLineage,
  RawMedia,
  RawMember,
  RawNarrative,
  RawOrg,
  RawPerson,
  RawRelation,
  RawSource,
  Union,
} from './types';

const PR = ['partner']; // parentRoles — README §8
const CR = ['barn']; //     childRoles (kun 'barn' er blodslægtskab)
const PAGE = 1000; // PostgREST cap pr. svar

// PostgREST returnerer max 1000 rækker pr. svar uanset limit — så vi sideinddeler med .range().
// VIGTIGT: gentag indtil et chunk er mindre end PAGE; stol ALDRIG på én bred .range(0, stort tal),
// for serveren capper alligevel ved 1000 og resten tabes lydløst (advisor 2026-06-23).
export async function getAll<T>(
  makeQuery: () => {
    range: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: unknown }>;
  },
): Promise<T[]> {
  const all: T[] = [];
  let from = 0;
  for (let i = 0; i < 400; i++) {
    const { data, error } = await makeQuery().range(from, from + PAGE - 1);
    if (error) throw error;
    const chunk = data ?? [];
    if (!chunk.length) break;
    all.push(...chunk);
    if (chunk.length < PAGE) break;
    from += PAGE;
  }
  return all;
}

export type LoadResult = {
  db: Db;
  aux: Aux;
  // Fornuftige start-id'er i de levende data (seed-id'erne findes ikke her).
  rootId: string;
  focusId: string;
  relAId: string;
  relBId: string;
};

// Henter alt fra Supabase og bygger mellem-formen. Kaster ved fejl — kalderen falder tilbage
// til offline-seed.
export async function loadFromSupabase(): Promise<LoadResult> {
  if (!supabaseEnabled || !supabase) throw new Error('Supabase ikke konfigureret');
  const sb = supabase;

  const [persons, , members, narratives, extIds, sources, relations, estates, orgs, media, lineage] =
    await Promise.all([
      getAll<RawPerson>(() =>
        sb.from('person').select('id,visning_navn,visning_foedt,visning_doed,visning_titel,koen,privat'),
      ),
      getAll<{ id: number; type: string }>(() => sb.from('family').select('id,type')),
      getAll<RawMember>(() => sb.from('family_member').select('family_id,person_id,rolle,ordinal')),
      getAll<RawNarrative>(() =>
        sb
          .from('narrative')
          .select('subjekt_id,subjekt_type,tekst,privat')
          .eq('subjekt_type', 'person'),
      ),
      getAll<RawExtId>(() =>
        sb.from('person_external_id').select('person_id,source_id,linje,nr'),
      ),
      getAll<RawSource>(() => sb.from('source').select('id,slags,titel,udgave,ekstern')),
      getAll<RawRelation>(() =>
        sb
          .from('relation')
          .select('subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw')
          .eq('subjekt_type', 'person'),
      ),
      getAll<RawEstate>(() => sb.from('estate').select('id,navn,slags')),
      getAll<RawOrg>(() => sb.from('organisation').select('id,navn,slags')),
      getAll<RawMedia>(() => sb.from('media').select('*')),
      // Tolerant: lineage-tabellen findes måske ikke endnu (migration ej kørt) → tom = fallback til 'Linje {kode}'.
      getAll<RawLineage>(() => sb.from('lineage').select('source_id,kode,navn')).catch(() => [] as RawLineage[]),
    ]);

  // Biografi pr. person — første ikke-private narrativ.
  const bioBy: Record<string, string> = {};
  (narratives || []).forEach((n) => {
    if (!n.privat && !bioBy[String(n.subjekt_id)]) bioBy[String(n.subjekt_id)] = n.tekst ?? '';
  });

  const appPersons = (persons || [])
    .filter((p) => !p.privat)
    .map((p) => ({
      id: String(p.id),
      name: p.visning_navn || '(uden navn)',
      born: parseYear(p.visning_foedt),
      died: parseYear(p.visning_doed),
      years: fmtYears(p.visning_foedt, p.visning_doed),
      title: p.visning_titel || '',
      bio: bioBy[String(p.id)] || '',
    }));

  // Familie-nav → unions + parentChild (partner × barn).
  const byFam: Record<string, RawMember[]> = {};
  (members || []).forEach((m) => {
    (byFam[String(m.family_id)] = byFam[String(m.family_id)] || []).push(m);
  });
  const unions: Union[] = [];
  const parentChild: ParentChild[] = [];
  Object.keys(byFam).forEach((fid) => {
    const mem = byFam[fid];
    const parents = mem
      .filter((m) => PR.includes(String(m.rolle || '').toLowerCase()))
      .sort((a, b) => (a.ordinal || 0) - (b.ordinal || 0));
    // Sortér børn efter ordinal — PostgREST har ingen garanteret rækkefølge, så uden dette
    // ville søskende-rækkefølgen være udefineret (og kunne skifte mellem loads).
    const children = mem
      .filter((m) => CR.includes(String(m.rolle || '').toLowerCase()))
      .sort((a, b) => (a.ordinal || 0) - (b.ordinal || 0));
    if (parents.length) {
      unions.push({
        id: 'f' + fid,
        p1: String(parents[0].person_id),
        p2: parents[1] ? String(parents[1].person_id) : null,
        p2_name: null,
        year: null,
      });
    }
    children.forEach((c) => {
      parents.forEach((pa) => {
        parentChild.push({
          child: String(c.person_id),
          parent: String(pa.person_id),
          union: 'f' + fid,
        });
      });
    });
  });

  const db: Db = { persons: appPersons, unions, parentChild };
  if (!db.persons.length) throw new Error('Ingen personer hentet');

  const aux = buildAux({ extIds, sources, relations, estates, orgs, media, lineage });

  // Vælg fornuftige start-id'er (flest børn = midt i træet).
  const childSet = new Set(parentChild.map((e) => e.child));
  const parentSet = new Set(parentChild.map((e) => e.parent));
  const kids: Record<string, number> = {};
  parentChild.forEach((e) => {
    kids[e.parent] = (kids[e.parent] || 0) + 1;
  });
  const byKids = (a: { id: string }, b: { id: string }) => (kids[b.id] || 0) - (kids[a.id] || 0);
  const midTree = db.persons.filter((p) => childSet.has(p.id) && parentSet.has(p.id)).sort(byKids);
  const anyParent = db.persons.filter((p) => parentSet.has(p.id)).sort(byKids);
  const roots = db.persons.filter((p) => !childSet.has(p.id));
  const focus = midTree[0] || anyParent[0] || roots[0] || db.persons[0];
  const root = roots[0] || db.persons[0];
  const leaves = db.persons.filter((p) => !parentSet.has(p.id));
  const relA = leaves[0] || db.persons[0];
  const relB = leaves[1] || leaves[0] || db.persons[0];

  return {
    db,
    aux,
    rootId: root.id,
    focusId: focus.id,
    relAId: relA.id,
    relBId: relB.id,
  };
}
