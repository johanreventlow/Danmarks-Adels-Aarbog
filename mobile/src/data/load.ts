// Port af loadFromSupabase() fra design-HTML (linje 881-960), via supabase-js.
// Producerer mellem-formen db = {persons, unions, parentChild} + aux. buildModel kaldes
// SEPARAT bagefter (i storen) for at udlede parentId/spouse + indekser.
import { supabase, supabaseEnabled } from '../lib/supabase';
import { buildAux } from './buildAux';
import { buildGeo } from './buildGeo';
import { buildGenCoords, buildParentsUnknown, type GenCoord, type ParentsUnknown } from './generations';
import { collapseSameAs } from './collapseSameAs';
import { pickPreferredBio, type NarrativeCand } from './pickPreferredBio';
import { fmtYears, parseYear } from './fields';
import { normalizeKoen, normalizeKonfidens } from './types';
import type {
  AppPerson,
  Aux,
  Db,
  Geo,
  Provenance,
  ParentChild,
  RawArms,
  RawEstate,
  RawExtId,
  RawFact,
  RawLineage,
  RawMedia,
  RawMember,
  RawNarrative,
  RawOrg,
  RawPerson,
  RawPlace,
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
  // samme_som-collapse: ethvert medlems-id → kanonisk id + proveniens pr. kanonisk (til badge).
  canonicalIdById: Record<string, string>;
  mergedFrom: Record<string, Provenance[]>;
  // Geo-lag (kortpunkter) — tomt indtil koordinat-berigelsen (tng_places + geokodning) er kørt.
  geo: Geo;
  // Generations-koordinater pr. kanonisk person-id (slægtled_lokal/gennem + kuld pr. linje).
  // Bruges af tree-byggerens hul-reparation (Task C1); spejler web/src/data/model.ts (Task B2).
  genCoordsByPerson: Record<string, GenCoord[]>;
  // Marker-gatet "forældre ukendt" pr. kanonisk person-id (grad + proveniens). KUN personer hvor
  // kilden faktisk angiver at forbindelsen opad ikke er kendt — spejler web/src/data/model.ts.
  parentsUnknownByPerson: Record<string, ParentsUnknown>;
};

export function mapAppPersons(
  persons: RawPerson[],
  bioBy: Record<string, string>,
  includePrivat: boolean,
): AppPerson[] {
  return (persons || [])
    .filter((p) => includePrivat || !p.privat)
    .map((p) => ({
      id: String(p.id),
      // Fallback til visning_navn er MIDLERTIDIG kompat (spec §4.9) — visning_fuldt_navn er NULL
      // for personer der endnu ikke er regenereret efter udledt-slægtsnavn-backfillen.
      name: p.visning_fuldt_navn || p.visning_navn || '(uden navn)',
      born: parseYear(p.visning_foedt),
      died: parseYear(p.visning_doed),
      years: fmtYears(p.visning_foedt, p.visning_doed),
      title: p.visning_titel || '',
      bio: bioBy[String(p.id)] || '',
      privat: Boolean(p.privat),
      koen: normalizeKoen(p.koen),
    }));
}

// Sorterer forældre (partner-rolle-medlemmer af en familie) så far kommer før mor —
// DAA er patrilineær, linje/nr følger mandslinjen. `ordinal` er ægteskabs-nummer
// (1./2. ægteskab for DEN person), ikke en far/mor-markør: to forældre har typisk
// begge ordinal=1 for deres respektive første ægteskab, så en ren ordinal-sortering
// er vilkårlig og kan lige så godt vise mor som far i stamtræets forælder-slot.
// Kun tie-breaker for to forældre af samme/ukendt køn.
export function compareParentOrder(
  a: { person_id: number | string; ordinal: number | null },
  b: { person_id: number | string; ordinal: number | null },
  koenById: Record<string, string | null>,
): number {
  const rank = (k: string | null) => (k === 'mand' ? 0 : k === 'kvinde' ? 1 : 2);
  const koenDiff = rank(koenById[String(a.person_id)] ?? null) - rank(koenById[String(b.person_id)] ?? null);
  return koenDiff !== 0 ? koenDiff : (a.ordinal || 0) - (b.ordinal || 0);
}

// Henter alt fra Supabase og bygger mellem-formen. Kaster ved fejl — kalderen falder tilbage
// til offline-seed.
export async function loadFromSupabase(opts?: {
  includePrivat?: boolean;
  collapse?: boolean; // default true; redaktion slår FRA for at se de separate DB-poster (spec §8)
}): Promise<LoadResult> {
  if (!supabaseEnabled || !supabase) throw new Error('Supabase ikke konfigureret');
  const sb = supabase;

  // Start "forældre ukendt"-markerings-hentningen NU, så den overlapper hoved-batchen (ingen
  // data-afhængighed af canonicalIdById — buildParentsUnknown kanoniserer bagefter). Spejler web.
  const puRowsP = fetchParentsUnknownRows(sb);

  const [
    persons,
    ,
    members,
    narratives,
    extIds,
    sources,
    relations,
    estates,
    orgs,
    media,
    lineage,
    arms,
    sameAsRel,
    approvedConc,
    places,
    facts,
  ] = await Promise.all([
      getAll<RawPerson>(() =>
        sb.from('person').select('id,visning_navn,visning_fuldt_navn,visning_foedt,visning_doed,visning_titel,koen,privat'),
      ),
      getAll<{ id: number; type: string }>(() => sb.from('family').select('id,type')),
      getAll<RawMember>(() => sb.from('family_member').select('family_id,person_id,rolle,ordinal,konfidens')),
      getAll<RawNarrative>(() =>
        sb
          .from('narrative')
          .select('id,subjekt_id,subjekt_type,tekst,privat,source_id')
          .eq('subjekt_type', 'person'),
      ),
      // Linje/nr + slægtled-koordinater pr. person — tolerant: kolonnerne kan mangle på en
      // ikke-migreret base. Uden .catch ville en manglende kolonne fælde HELE Promise.all'et og
      // erstatte det levende datasæt med det indlejrede SEED (F1, dual-review 2026-07-05) —
      // degrader i stedet til "ingen linje/generations-data" som web's model.ts-pendant.
      getAll<RawExtId>(() =>
        sb.from('person_external_id').select('person_id,source_id,linje,nr,slaegtled_lokal,slaegtled_gennem,kuld'),
      ).catch((e) => { console.warn('[loadFromSupabase] person_external_id utilgængelig — linjer/generationer degraderet:', e); return [] as RawExtId[]; }),
      getAll<RawSource>(() => sb.from('source').select('id,slags,titel,udgave,aar,ekstern')),
      getAll<RawRelation>(() =>
        sb
          .from('relation')
          .select('subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw')
          .eq('subjekt_type', 'person'),
      ),
      getAll<RawEstate>(() => sb.from('estate').select('id,navn,slags,sted_id')),
      getAll<RawOrg>(() => sb.from('organisation').select('id,navn,slags')),
      getAll<RawMedia>(() => sb.from('media').select('*')),
      // Tolerant: lineage-tabellen findes måske ikke endnu (migration ej kørt) → tom = fallback til 'Linje {kode}'.
      getAll<RawLineage>(() => sb.from('lineage').select('id,source_id,kode,navn,parent_lineage_id')).catch(() => [] as RawLineage[]),
      // Tolerant: coat_of_arms-tabellen findes måske ikke endnu.
      getAll<RawArms>(() => sb.from('coat_of_arms').select('id,blasonering,note')).catch(() => [] as RawArms[]),
      // samme_som-relationer (person→person). Kanterne er retningsbestemte: subjekt=alias, objekt=kanonisk.
      getAll<{ id: number | string; subjekt_id: number | string; objekt_id: number | string }>(() =>
        sb
          .from('relation')
          .select('id,subjekt_id,objekt_id')
          .eq('rolle', 'samme_som')
          .eq('subjekt_type', 'person')
          .eq('objekt_type', 'person'),
      ).catch(() => [] as { id: number | string; subjekt_id: number | string; objekt_id: number | string }[]),
      // Afklarede (blåstemplede) konklusioner på relationer — kun disse identiteter foldes (spec §4).
      // Polymorf kobling (conclusion.target_type/target_id), ingen FK → hentes separat + matches i JS.
      getAll<{ target_id: number | string }>(() =>
        sb.from('conclusion').select('target_id').eq('target_type', 'relation').eq('status', 'afklaret'),
      ).catch(() => [] as { target_id: number | string }[]),
      // Steder m. koordinater (tolerant: tabellen kan mangle i ældre env).
      // .not('lat','is',null): buildGeo bruger kun steder MED koordinater, så vi henter kun dem.
      //   Før berigelsen er lat/lon tomme overalt → 0 rækker i ét enkelt round-trip (ingen dead weight).
      // .order('id'): place kan være >1000 rækker (tng_places ~6.788) efter berigelse → stabil rækkefølge
      //   på tværs af getAll's paginerede .range()-kald, så grænse-rækker hverken duplikeres eller tabes.
      getAll<RawPlace>(() =>
        sb.from('place').select('id,navn,lat,lon').not('lat', 'is', null).order('id'),
      ).catch(() => [] as RawPlace[]),
      // Geo-bærende fakta: kun rækker med et sted (reducerer payload). Tolerant hvis RLS/tabel afviger.
      getAll<RawFact>(() =>
        sb.from('fact').select('subjekt_type,subjekt_id,faktatype,sted_id').not('sted_id', 'is', null).order('id'),
      ).catch(() => [] as RawFact[]),
    ]);

  // Biografi pr. person — foretrukne offentlige narrativ (nyeste DAA-udgave) via pickPreferredBio.
  // Deterministisk pr. udgave i stedet for "første mødte" (som blev nondeterministisk når en
  // person fik flere narrativ-rækker). collapseSameAs-merge nedenfor er uændret.
  const srcById = new Map((sources || []).map((s) => [Number(s.id), s]));
  const candsBy: Record<string, NarrativeCand[]> = {};
  (narratives || []).forEach((n) => {
    if (n.privat) return;
    const k = String(n.subjekt_id);
    const s = n.source_id != null ? srcById.get(Number(n.source_id)) : undefined;
    (candsBy[k] ??= []).push({ narrativeId: n.id, tekst: n.tekst, sourceId: n.source_id ?? null,
      slags: s?.slags ?? null, aar: s?.aar ?? null, udgave: s?.udgave ?? null });
  });
  const bioBy: Record<string, string> = {};
  for (const k of Object.keys(candsBy)) {
    const best = pickPreferredBio(candsBy[k]);
    if (best?.tekst) bioBy[k] = best.tekst;
  }

  const appPersons = mapAppPersons(persons || [], bioBy, opts?.includePrivat ?? false);

  // koen pr. person — bruges KUN til at afgøre forælder-rækkefølge nedenfor (ordinal er
  // ægteskabs-nummer, ikke far/mor-markør; to forældre i samme familie har typisk begge
  // ordinal=1 for deres respektive første ægteskab, så en ordinal-sortering er vilkårlig).
  const koenById: Record<string, string | null> = {};
  appPersons.forEach((p) => { koenById[p.id] = p.koen ?? null; });

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
      .sort((a, b) => compareParentOrder(a, b, koenById));
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
      // Konfidens sidder på BARNETS medlemskabslink (rolle='barn'), ikke forælderens.
      const konfidens = normalizeKonfidens(c.konfidens);
      parents.forEach((pa) => {
        parentChild.push({
          child: String(c.person_id),
          parent: String(pa.person_id),
          union: 'f' + fid,
          konfidens,
        });
      });
    });
  });

  const rawDb: Db = { persons: appPersons, unions, parentChild };
  if (!rawDb.persons.length) throw new Error('Ingen personer hentet');

  // samme_som-collapse FØR alt andet: fold flere person-rækker der er samme fysiske person til
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
  if (collapsed.quarantined.length) {
    console.warn('[samme_som] karantæne (foldes ikke):', collapsed.quarantined);
  }
  const db = collapsed.db;

  const aux = buildAux(
    { extIds, sources, relations, estates, orgs, media, lineage, arms },
    collapsed.canonicalIdById,
  );

  // Geo-lag: bygges på den COLLAPSED + privat-filtrerede db.persons (RLS-gate). Tomt indtil
  // koordinat-berigelsen udfylder place.lat/lon.
  const geo = buildGeo(
    { facts, estates, places, persons: db.persons, unions: db.unions },
    collapsed.canonicalIdById,
  );

  const genCoordsByPerson = buildGenCoords(extIds, lineage, collapsed.canonicalIdById);
  const puRows = await puRowsP;
  const parentsUnknownByPerson = buildParentsUnknown(puRows.facts, puRows.conclusions, puRows.assertions, puRows.citations, collapsed.canonicalIdById);

  // Vælg fornuftige start-id'er (flest børn = midt i træet) — på den COLLAPSED db, så et start-id
  // aldrig peger på et foldet alias.
  const childSet = new Set(db.parentChild.map((e) => e.child));
  const parentSet = new Set(db.parentChild.map((e) => e.parent));
  const kids: Record<string, number> = {};
  db.parentChild.forEach((e) => {
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
    canonicalIdById: collapsed.canonicalIdById,
    mergedFrom: collapsed.mergedFrom,
    geo,
    genCoordsByPerson,
    parentsUnknownByPerson,
  };
}

// Hent de RÅ rækker til "forældre ukendt"-markeringer (faktatype 'forældre_ukendt' + afklaret
// konklusion + valgt assertions grad + citationens proveniens). Bevidst UDEN canonicalIdById, så
// den kan startes FØR collapse og overlappe hoved-batchen (buildParentsUnknown kanoniserer bagefter).
// Kort-cirkuleret på det (typisk lille/tomme) markerings-sæt; tolerant — fejl → tomme rækker.
// Spejler web/src/data/model.ts's fetchParentsUnknownRows.
type ParentsUnknownRows = {
  facts: { id: number | string; subjekt_id: number | string }[];
  conclusions: { target_id: number | string; valgt_assertion_id: number | string | null }[];
  assertions: { id: number | string; vaerdi_tekst: string | null }[];
  citations: { assertion_id: number | string; citat_tekst: string | null }[];
};

async function fetchParentsUnknownRows(sb: NonNullable<typeof supabase>): Promise<ParentsUnknownRows> {
  const empty: ParentsUnknownRows = { facts: [], conclusions: [], assertions: [], citations: [] };
  try {
    const facts = await getAll<ParentsUnknownRows['facts'][number]>(() =>
      sb.from('fact').select('id,subjekt_id').eq('subjekt_type', 'person').eq('faktatype', 'forældre_ukendt').order('id'),
    );
    if (!facts.length) return empty;
    const factIds = facts.map((f) => f.id);
    const conclusions = await getAll<ParentsUnknownRows['conclusions'][number]>(() =>
      sb.from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact').eq('status', 'afklaret').in('target_id', factIds).order('id'),
    );
    const assertionIds = conclusions.map((c) => c.valgt_assertion_id).filter((v): v is number | string => v != null);
    if (!assertionIds.length) return { facts, conclusions, assertions: [], citations: [] };
    const [assertions, citations] = await Promise.all([
      getAll<ParentsUnknownRows['assertions'][number]>(() =>
        sb.from('assertion').select('id,vaerdi_tekst').in('id', assertionIds).order('id')),
      getAll<ParentsUnknownRows['citations'][number]>(() =>
        sb.from('citation').select('assertion_id,citat_tekst').in('assertion_id', assertionIds).order('id')),
    ]);
    return { facts, conclusions, assertions, citations };
  } catch (e) {
    console.warn('[loadFromSupabase] forældre_ukendt-markeringer utilgængelige — ingen kandidat-ringe:', e);
    return empty;
  }
}
