// Port af loadFromSupabase() fra design-HTML (linje 881-960), via supabase-js.
// Producerer mellem-formen db = {persons, unions, parentChild} + aux. buildModel kaldes
// SEPARAT bagefter (i storen) for at udlede parentId/spouse + indekser.
import { supabase, supabaseEnabled } from '../lib/supabase';
import { buildAux } from './buildAux';
import {
  buildGenCoords, buildParentsUnknown, buildGeo, collapseSameAs, buildBioSourceVersions,
  mapPublicBioSourceVersionsV2, selectDefaultPublicBioSourceVersionV2, fmtYears, parseYear, getAll, EMPTY_GEO,
  citationRowsTilProveniens, coordinateRowToExtId, COORDINATES_RPC_RAEKKER, COORDINATES_RPC_SAMLET, fetchPublicCoordinates,
  type GenCoord, type ParentsUnknown, type CitationProvenanceRow, type RaaCitationRow,
} from '@daa/core';
import {
  buildHaendelserBy,
  buildLivsdatoBy,
  buildStorieBy,
  type FeedPinInput,
  type HaendelserBy,
  type LivsdatoBy,
  type StorieBy,
} from '@daa/feed';
import { fetchFeedPins } from './feedPins';
import { fetchHaendelseRows } from './haendelser';
import { fetchLivsdatoRows } from './livsdato';
import { fetchStoryRows } from './story';
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
  RawOrg,
  RawPerson,
  RawPlace,
  RawRelation,
  RawSource,
  RawTextMention,
  Union,
} from './types';

const PR = ['partner']; // parentRoles — README §8
const CR = ['barn']; //     childRoles (kun 'barn' er blodslægtskab)

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
  // Geo-lag (kortpunkter) — starter TOMT (review 27 P3, "lazy geo-kæde"): place+fact hentes ikke
  // ved cold-start. loadGeo() henter dem + bygger den rigtige Geo, kaldt af storen ved første
  // kort-brug (Slægtens kort, Godser-kort, livsrejse-minikort). Spejler web/src/data/model.ts.
  geo: Geo;
  loadGeo: () => Promise<Geo>;
  // Generations-koordinater pr. kanonisk person-id (slægtled_lokal/gennem + kuld pr. linje).
  // Bruges af tree-byggerens hul-reparation (Task C1); spejler web/src/data/model.ts (Task B2).
  genCoordsByPerson: Record<string, GenCoord[]>;
  // Marker-gatet "forældre ukendt" pr. kanonisk person-id (grad + proveniens). KUN personer hvor
  // kilden faktisk angiver at forbindelsen opad ikke er kendt — spejler web/src/data/model.ts.
  parentsUnknownByPerson: Record<string, ParentsUnknown>;
  // Strukturerede fødsels-/dødsdatoer pr. kanonisk person-id (fase1-design.md §6.1) — til
  // dag-præcise feed-kort ('på denne dag', jubilæer). {} hvis livsdato-hentningen degraderer.
  livsdatoBy: LivsdatoBy;
  // Regenererbare narrativ-hændelser pr. kanonisk person-id (fase2-design.md §5.2).
  // {} hvis tabellen endnu ikke er migreret eller hentningen ellers degraderer.
  haendelserBy: HaendelserBy;
  // Publicerede redaktionelle minihistorier; {} ved umigreret/utilgængelig story-kæde.
  storieBy: StorieBy;
  // Redaktionel pin/skjul-kurering; [] betyder almindeligt, ukurateret fase 2-feed.
  feedPins: FeedPinInput[];
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

export function mapPublicBioVersionsByPersonV2(
  rows: readonly unknown[],
  canonicalIdById: Record<string, string>,
): Record<string, string> {
  const rowsByCanonicalPerson = new Map<string, unknown[]>();
  for (const row of rows) {
    if (typeof row !== 'object' || row === null || typeof (row as Record<string, unknown>).person_id !== 'number') {
      throw new Error('PUBLIC_BIO_SOURCE_VERSION_V2_INVALID_person_id');
    }
    const personId = (row as Record<string, number>).person_id;
    const canonicalId = canonicalIdById[String(personId)] ?? String(personId);
    const personRows = rowsByCanonicalPerson.get(canonicalId);
    if (personRows) personRows.push(row); else rowsByCanonicalPerson.set(canonicalId, [row]);
  }
  const bioBy: Record<string, string> = {};
  for (const [canonicalId, personRows] of rowsByCanonicalPerson) {
    const selected = selectDefaultPublicBioSourceVersionV2(mapPublicBioSourceVersionsV2(personRows));
    if (selected) bioBy[canonicalId] = selected.narrativeText;
  }
  return bioBy;
}

function mapPublicBioVersionsByPersonV1(
  rows: readonly unknown[],
  canonicalIdById: Record<string, string>,
): Record<string, string> {
  const bioBy: Record<string, string> = {};
  for (const row of rows) {
    if (typeof row !== 'object' || row === null) continue;
    const value = row as Record<string, unknown>;
    if (typeof value.person_id !== 'number'
      || (value.provenance_kind !== 'source_record' && value.provenance_kind !== 'legacy_narrative')
      || (value.record_ref !== null && typeof value.record_ref !== 'string')
      || typeof value.source_label !== 'string' || typeof value.record_label !== 'string'
      || typeof value.narrative_text !== 'string' || typeof value.citation_label !== 'string') continue;
    const text = buildBioSourceVersions([{
      record_ref: value.record_ref,
      source_label: value.source_label,
      record_label: value.record_label,
      narrative_text: value.narrative_text,
      citation_label: value.citation_label,
      provenance_kind: value.provenance_kind,
    }])[0]?.narrativeText;
    if (text) bioBy[canonicalIdById[String(value.person_id)] ?? String(value.person_id)] ??= text;
  }
  return bioBy;
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
  // Samme mønster for livsdato (fase1-design.md §6.1): starter parallelt med hoved-batchen,
  // kanoniseres først når collapsed.canonicalIdById findes.
  const livsdatoRowsP = fetchLivsdatoRows(sb);
  // Hændelsesprojektionen følger samme tolerante parallel-load og kanoniseres efter collapse.
  const haendelseRowsP = fetchHaendelseRows(sb);
  // Stories og pins starter parallelt; story-person-id'er kanoniseres først efter collapse.
  const storyRowsP = fetchStoryRows(sb);
  const feedPinsP = fetchFeedPins(sb);

  const [
    persons,
    members,
    extIds,
    sources,
    relations,
    mediaRelations,
    mediaMentions,
    estates,
    orgs,
    media,
    mediaVariants,
    lineage,
    arms,
    sameAsRel,
    approvedConc,
  ] = await Promise.all([
      // Alle tabel-læsninger her sorteres på en ENTYDIG nøgle (PK / alle PK-kolonner): getAll
      // offset-paginerer, og uden fast rækkefølge kan rækker springes over/gentages mellem sider.
      getAll<RawPerson>(() =>
        sb.from('person').select('id,visning_navn,visning_fuldt_navn,visning_foedt,visning_doed,visning_titel,koen,privat').order('id'),
      ),
      getAll<RawMember>(() => sb.from('family_member').select('family_id,person_id,rolle,ordinal,konfidens')
        .order('family_id').order('person_id').order('rolle')),
      // Linje/nr + slægtled-koordinater pr. person — tolerant: kolonnerne kan mangle på en
      // ikke-migreret base. Uden .catch ville en manglende kolonne fælde HELE Promise.all'et og
      // erstatte det levende datasæt med det indlejrede SEED (F1, dual-review 2026-07-05) —
      // degrader i stedet til "ingen linje/generations-data" som web's model.ts-pendant.
      // 5c-2: koordinater fra public_person_source_coordinates (placement ved gældende membership, ellers legacy).
      // Kodereview 36 P2: ét kald (samlet jsonb); fald tilbage til rækkefunktionen via getAll, hvis DDL'en mangler.
      fetchPublicCoordinates(() => sb.rpc(COORDINATES_RPC_SAMLET), () => sb.rpc(COORDINATES_RPC_RAEKKER))
        .then((rows) => rows.map(coordinateRowToExtId))
        .catch((e) => { console.warn('[loadFromSupabase] public_person_source_coordinates utilgængelig — linjer/generationer degraderet:', e); return [] as RawExtId[]; }),
      getAll<RawSource>(() => sb.from('source').select('id,slags,titel,udgave,aar,ekstern').order('id')),
      getAll<RawRelation>(() =>
        sb
          .from('relation')
          .select('subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw,kvalifikator')
          .eq('subjekt_type', 'person')
          .order('id'),
      ),
      getAll<RawRelation>(() =>
        sb
          .from('relation')
          .select('subjekt_type,subjekt_id,objekt_type,objekt_id,rolle,periode_raw')
          .eq('subjekt_type', 'media')
          .eq('rolle', 'afbildet')
          .order('id'),
      ),
      getAll<RawTextMention>(() =>
        sb
          .from('text_mention')
          .select('kilde_type,kilde_id,maal_type,maal_id')
          .eq('maal_type', 'media')
          .order('kilde_type').order('kilde_id').order('maal_type').order('maal_id'),
      ),
      getAll<RawEstate>(() => sb.from('estate').select('id,navn,slags,sted_id').order('id')),
      getAll<RawOrg>(() => sb.from('organisation').select('id,navn,slags').order('id')),
      getAll<RawMedia>(() => sb.from('media').select('*').order('id')),
      // Billedstørrelser (2026-07-05, Slice B3 'thumb' + Slice C 'medium' — narrativ-indlejrede
      // billeder). ÉN query for begge tiers (ikke to separate) — samme rækker filtreres i JS
      // nedenfor. Tolerant: tabellen kan mangle på en ikke-migreret base (samme mønster som
      // lineage/arms).
      getAll<{ media_id: number; tier: string; storage_path: string }>(() =>
        sb.from('media_variant').select('media_id,tier,storage_path').in('tier', ['thumb', 'medium']).order('id'),
      ).catch(() => [] as { media_id: number; tier: string; storage_path: string }[]),
      // Tolerant: lineage-tabellen findes måske ikke endnu (migration ej kørt) → tom = fallback til 'Linje {kode}'.
      getAll<RawLineage>(() => sb.from('lineage').select('id,source_id,kode,navn,parent_lineage_id').order('id')).catch(() => [] as RawLineage[]),
      // Tolerant: coat_of_arms-tabellen findes måske ikke endnu.
      getAll<RawArms>(() => sb.from('coat_of_arms').select('id,blasonering,note').order('id')).catch(() => [] as RawArms[]),
      // samme_som-relationer (person→person). Kanterne er retningsbestemte: subjekt=alias, objekt=kanonisk.
      getAll<{ id: number | string; subjekt_id: number | string; objekt_id: number | string }>(() =>
        sb
          .from('relation')
          .select('id,subjekt_id,objekt_id')
          .eq('rolle', 'samme_som')
          .eq('subjekt_type', 'person')
          .eq('objekt_type', 'person')
          .order('id'),
      ).catch(() => [] as { id: number | string; subjekt_id: number | string; objekt_id: number | string }[]),
      // Afklarede (blåstemplede) konklusioner på relationer — kun disse identiteter foldes (spec §4).
      // Polymorf kobling (conclusion.target_type/target_id), ingen FK → hentes separat + matches i JS.
      getAll<{ target_id: number | string }>(() =>
        sb.from('conclusion').select('target_id').eq('target_type', 'relation').eq('status', 'afklaret').order('id'),
      ).catch(() => [] as { target_id: number | string }[]),
      // place+fact (den tunge geo-kæde) er UDSKUDT (review 27 P3): de hentes først af loadGeo()
      // nedenfor, ved første kort-brug, ikke ved cold-start. Se loadGeo-closuren for de faktiske
      // queries (uændrede) + degradering.
    ]);

  // A contract-gated RPC is the sole person biography reader.  After v2 the
  // model sees only the event text; an RPC failure rejects this load rather
  // than reaching back to public.narrative.tekst.
  const contract = await sb.rpc('narrative_record_contract_version', {});
  if (contract.error || typeof contract.data !== 'number' || !Number.isInteger(contract.data)) {
    throw new Error('NARRATIVE_RECORD_CONTRACT_VERSION_UNAVAILABLE');
  }
  const publicRows = await sb.rpc(
    contract.data >= 2 ? 'public_person_bio_source_versions_v2' : 'public_person_bio_source_versions',
    { p_person_ids: (persons || []).map((person) => Number(person.id)).filter(Number.isFinite) },
  );
  if (publicRows.error || !Array.isArray(publicRows.data)) {
    throw new Error('PUBLIC_BIO_SOURCE_VERSIONS_UNAVAILABLE');
  }
  // Bios are applied only after identity collapse.  This prevents v2 event
  // text from being concatenated across aliases by collapseSameAs.
  const appPersons = mapAppPersons(persons || [], {}, opts?.includePrivat ?? false);

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
  const extMap = new Map((extIds || []).map((x) => [String(x.person_id), { linje: x.linje, nr: x.nr, nr_label: x.nr_label ?? null }]));
  const collapsed = collapseSameAs(rawDb, edges, extMap);
  if (collapsed.quarantined.length) {
    console.warn('[samme_som] karantæne (foldes ikke):', collapsed.quarantined);
  }
  const db = collapsed.db;
  const bioBy = contract.data >= 2
    ? mapPublicBioVersionsByPersonV2(publicRows.data, collapsed.canonicalIdById)
    : mapPublicBioVersionsByPersonV1(publicRows.data, collapsed.canonicalIdById);
  db.persons.forEach((person) => { person.bio = bioBy[person.id] ?? ''; });

  // Billedstørrelser (Slice B3 'thumb' + Slice C 'medium'): berig hver media-række med sine
  // variant-stier (hvis nogen) — downstream (buildAux/lib/media.ts) forbruger dermed bare to
  // ekstra felter på RawMedia i stedet for at kende til media_variant-tabellen. Ingen match
  // (rækker fra før Slice B) → felterne udelades.
  const thumbPathByMediaId = new Map(
    (mediaVariants || []).filter((v) => v.tier === 'thumb').map((v) => [String(v.media_id), v.storage_path]));
  const mediumPathByMediaId = new Map(
    (mediaVariants || []).filter((v) => v.tier === 'medium').map((v) => [String(v.media_id), v.storage_path]));
  const mediaEnriched = (media || []).map((m) => {
    const thumb = thumbPathByMediaId.get(String(m.id));
    const medium = mediumPathByMediaId.get(String(m.id));
    return (thumb || medium) ? { ...m, thumb_storage_path: thumb, medium_storage_path: medium } : m;
  });

  const citationKilder = await fetchNavnProveniens(sb);
  const aux = buildAux(
    { extIds, sources, relations, mediaRelations, mediaMentions, estates, orgs, media: mediaEnriched, lineage, arms, citationKilder },
    collapsed.canonicalIdById,
  );

  // Geo-lag: starter TOMT (review 27 P3, "lazy geo-kæde") — place+fact hentes ikke ved cold-start.
  // loadGeo() nedenfor henter dem + bygger den rigtige Geo, kaldt af storen ved første kort-brug.
  const geo = EMPTY_GEO;
  const loadGeo = async (): Promise<Geo> => {
    // Geo-lag: godser m. sted (allerede hentet ovenfor), steder m. koordinater, geo-bærende
    // fakta. Alt tolerant (tomt = ingen kortpunkter). place.not('lat',...) → 0 rækker/ét
    // round-trip før berigelse; .order('id') giver stabil paginering når place >1000 rækker
    // (tng_places ~6.788) efter berigelse.
    const [places, facts] = await Promise.all([
      getAll<RawPlace>(() =>
        sb.from('place').select('id,navn,lat,lon').not('lat', 'is', null).order('id'),
      ).catch((e) => { console.warn('[loadFromSupabase] place utilgængelig — intet geo:', e); return [] as RawPlace[]; }),
      getAll<RawFact>(() =>
        sb.from('fact').select('subjekt_type,subjekt_id,faktatype,sted_id').not('sted_id', 'is', null).order('id'),
      ).catch((e) => { console.warn('[loadFromSupabase] fact utilgængelig — intet geo:', e); return [] as RawFact[]; }),
    ]);
    // Geo-lag bygget på den COLLAPSED + (RLS-)privat-filtrerede db.persons — samme mønster som web.
    return buildGeo(
      { facts, estates, places, persons: db.persons, unions: db.unions },
      collapsed.canonicalIdById,
    );
  };

  const genCoordsByPerson = buildGenCoords(extIds, lineage, collapsed.canonicalIdById);
  const puRows = await puRowsP;
  const parentsUnknownByPerson = buildParentsUnknown(puRows.facts, puRows.conclusions, puRows.assertions, puRows.citations, collapsed.canonicalIdById);
  const livsdatoRows = await livsdatoRowsP;
  const livsdatoBy = buildLivsdatoBy(livsdatoRows.facts, livsdatoRows.conclusions, livsdatoRows.assertions, collapsed.canonicalIdById);
  const haendelseRows = await haendelseRowsP;
  const haendelserBy = buildHaendelserBy(
    haendelseRows.rows, haendelseRows.narrativer, haendelseRows.sources,
    collapsed.canonicalIdById,
  );
  const storyRows = await storyRowsP;
  const storieBy = buildStorieBy(
    storyRows.rows, storyRows.kilder, storyRows.sources, collapsed.canonicalIdById,
  );
  const feedPins = await feedPinsP;

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
    loadGeo,
    genCoordsByPerson,
    parentsUnknownByPerson,
    livsdatoBy,
    haendelserBy,
    storieBy,
    feedPins,
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

// Proveniens til "Kilde i Aarbogen" for personer UDEN bog-nummer (de 627 ægtefæller). Kun
// `navn`-faktaet hentes: det er det ene faktum hver person beviseligt har (1756 af 1756), så
// omkostningen er ~1 række pr. person i stedet for hele faktabordet. Forbehold: en person med
// fakta fra flere udgaver får kun navnefaktaets kilde — men netop faldback-mængden har
// gennemgående præcis én kilde, så det koster intet i praksis.
// Tolerant: fejler opslaget, degraderer visningen til det den var før (ingen kilde vist).
async function fetchNavnProveniens(sb: NonNullable<typeof supabase>): Promise<CitationProvenanceRow[]> {
  try {
    const facts = await getAll<{ id: number; subjekt_id: number }>(() =>
      sb.from('fact').select('id,subjekt_id').eq('subjekt_type', 'person').eq('faktatype', 'navn').order('id'));
    if (!facts.length) return [];
    const asserts = await getAll<{ id: number; target_id: number }>(() =>
      sb.from('assertion').select('id,target_id').eq('target_type', 'fact').in('target_id', facts.map((f) => f.id)).order('id'));
    if (!asserts.length) return [];
    const cits = await getAll<RaaCitationRow>(() =>
      sb.from('citation').select('assertion_id,side,source:source_id(titel,udgave)').in('assertion_id', asserts.map((a) => a.id)).order('id'));
    const personAfFact = new Map(facts.map((f) => [f.id, String(f.subjekt_id)]));
    const personAfAssert = new Map(asserts.map((a) => [a.id, personAfFact.get(a.target_id) ?? '']));
    return citationRowsTilProveniens(cits, personAfAssert);
  } catch (e) {
    console.warn('[loadFromSupabase] citation-proveniens utilgængelig — ægtefæller vises uden kilde:', e);
    return [];
  }
}

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
