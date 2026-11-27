// Bygger den flade visningsmodel (Model) til publikums-web: persons + unions + parentChild
// → buildModel. Lean udgave af mobile/src/data/load.ts (kun det stamtræ + slægtskabsfinder
// behøver — ikke Aux/godser/våben). Rolle-vokab: partner = forælder-par, barn = blodslægt.
import { supabase } from '../supabase';
import { aarSpaend, boernIder, personVisningsnavn, buildGenCoords, buildParentsUnknown, byggBogNr, buildGeo, buildModel, collapseSameAs, coordinateRowToExtId, COORDINATES_RPC_RAEKKER, COORDINATES_RPC_SAMLET, fetchPublicCoordinates, fmtVisningsAar, oploesRelativDato, parseYear, getAll, EMPTY_GEO } from '@daa/core';
import { buildLineage, stamtavleSkemaOpslag } from './lineage';
import { buildSources } from './sources';
import { byggLinjeRaekker } from './linjeRaekker';
import { byggUdgaveModel } from './udgaver';
import { byggErStamtavle } from './stamtavleKilder';
import { hentSammeSomKanter, type SammeSomKant } from './sammeSomKanter';
import { normalizeKoen, normalizeKonfidens, type AppModel, type AppPerson, type Db, type Geo, type ParentChild, type RawEstate, type RawExtId, type RawFact, type RawLineageContext, type RawLineageScheme, type RawLineageSchemeEntry, type RawLineageSchemeEntryLineage, type RawPlace, type RawSource, type Union } from './types';
import { fetchLinjeAdelsnavne } from './adelsnavn';
import { fetchSkilsmisser } from './skilsmisser';

const PARTNER_ROLLER = ['partner'];
// KUN blodslægt ('barn') bliver en forælder→barn-kant — matcher mobile/src/data/load.ts og
// holder slægtskabsfinderen blod-baseret. adopteret_/pleje-/stedbarn (som redaktionen kan se)
// indgår bevidst IKKE i stamtræet/finderen; de er ikke blodslægt.
const BARN_ROLLE = 'barn';

// childrenOf/parentsOf er flyttet til @daa/core (mobil-paritet, batch 6); re-eksport så web-imports er uændrede.
export { childrenOf, parentsOf } from '@daa/core';

type RawPerson = {
  id: number | string; visning_navn: string | null; visning_fuldt_navn: string | null; visning_foedt: string | null;
  visning_doed: string | null; visning_floruit?: string | null; visning_titel: string | null; koen: string | null; privat: boolean | null; levende?: boolean | null;
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
export async function loadModel(opts?: { collapse?: boolean }): Promise<AppModel> {
  // Start "forældre ukendt"-markerings-hentningen NU, så den overlapper hoved-batchen (dens
  // facts-probe har ingen data-afhængighed af canonicalIdById — kun buildParentsUnknown til sidst har).
  const puRowsP = fetchParentsUnknownRows();
  // Linjernes adelsnavn (bogens formelle navneform) overlapper ligeledes hoved-batchen; tolerant (tomt ved fejl).
  const adelsnavneP = fetchLinjeAdelsnavne();
  // Skilsmisser (null ved fejl = ukendt, fail-closed downstream) overlapper ligeledes hoved-batchen.
  const skilsmisserP = fetchSkilsmisser();
  const [persons, members, extIds, lineageRows, schemes, schemeEntries, schemeMappings, sources, sameAsEdges, estates] = await Promise.all([
    getAll<RawPerson>(() => supabase.from('person').select('id,visning_navn,visning_fuldt_navn,visning_foedt,visning_doed,visning_floruit,visning_titel,koen,privat,levende').order('id')),
    getAll<RawMember>(() => supabase.from('family_member').select('family_id,person_id,rolle,ordinal,konfidens').order('family_id').order('person_id').order('rolle')),
    // Linje/nr pr. person (grene) — tolerant: tabellen/kolonnerne kan mangle i ældre baser.
    // Review 15: log ved fejl, så en RLS/drifts-fejl ikke stiltiende ligner "ingen linjer"
    // (graceful degradation bevares, men degraderingen bliver synlig i konsol/telemetri).
    // 5c-2: koordinater fra public_person_source_coordinates (placement ved gældende membership, ellers legacy).
    // Bevidst intet fald tilbage til legacy-viewet: en fejlslagen deploy skal ses som manglende linjer, ikke skjules.
    // Kodereview 36 P2: ét kald (samlet jsonb); fald tilbage til rækkefunktionen via getAll, hvis DDL'en mangler.
    fetchPublicCoordinates(() => supabase.rpc(COORDINATES_RPC_SAMLET), () => supabase.rpc(COORDINATES_RPC_RAEKKER))
      .then((rows) => rows.map(coordinateRowToExtId))
      .catch((e) => { console.warn('[loadModel] public_person_source_coordinates utilgængelig — linjer/kilder degraderet:', e); return [] as RawExtId[]; }),
    // Linje-navne — lineage-tabellen findes måske ikke endnu (fallback til 'Linje {kode}').
    getAll<RawLineageContext>(() => supabase.from('lineage').select('id,source_id,kode,navn,canonical_label,slaegt_id,slaegtsnavn,parent_lineage_id').order('id')).catch((e) => { console.warn('[loadModel] lineage utilgængelig — bruger linje-koder som navne:', e); return [] as RawLineageContext[]; }),
    getAll<RawLineageScheme>(() => supabase.from('lineage_scheme').select('id,slaegt_id,source_id,kind').order('id')).catch((e) => { console.warn('[loadModel] lineage schemes utilgængelige ikke — bruger kanonisk lineage-kontekst:', e); return [] as RawLineageScheme[]; }),
    getAll<RawLineageSchemeEntry>(() => supabase.from('lineage_scheme_entry').select('id,scheme_id,code,label').order('id')).catch((e) => { console.warn('[loadModel] lineage scheme entries utilgængelige ikke — bruger kanonisk lineage-kontekst:', e); return [] as RawLineageSchemeEntry[]; }),
    getAll<RawLineageSchemeEntryLineage>(() => supabase.from('lineage_scheme_entry_lineage').select('entry_id,lineage_id,relation_kind').order('entry_id').order('lineage_id').order('relation_kind')).catch((e) => { console.warn('[loadModel] lineage scheme mapping utilgængelig ikke — bruger kanonisk lineage-kontekst:', e); return [] as RawLineageSchemeEntryLineage[]; }),
    // Kilder (trykt værk) — til "Kilde i Aarbogen" pr. person.
    getAll<RawSource>(() => supabase.from('source').select('id,slags,titel,udgave,aar,ekstern').order('id')).catch((e) => { console.warn('[loadModel] source utilgængelig — Kilde-i-Aarbogen degraderet:', e); return [] as RawSource[]; }),
    // samme_som-kanter (alias → kanonisk) til collapse — kun afklarede (review 37 Y2: kun samme_som-konklusionerne
    // hentes, og en fejl afviser loadModel efter ét genforsøg pr. kald i stedet for tavst at vise dubletpersoner).
    // Redaktionen (collapse: false) arbejder i det rå id-rum og henter dem slet ikke.
    opts?.collapse === false ? Promise.resolve([] as SammeSomKant[]) : hentSammeSomKanter(supabase),
    // estate (godser m. sted) er lille og bruges også af den ikke-geo gods-liste/tæller —
    // hentes eager. place+fact (den tunge geo-kæde, ~6.788 place-rækker) er UDSKUDT (review 27
    // P3): de hentes først af loadGeo() nedenfor, ved første kort-brug, ikke ved cold-start.
    getAll<RawEstate>(() => supabase.from('estate').select('id,navn,slags,sted_id').order('id')).catch((e) => { console.warn('[loadModel] estate utilgængelig — ingen godskort:', e); return [] as RawEstate[]; }),
  ]);

  // Barn uden navn vises som »Unavngivet barn« (#388); erBarn ud fra family_member, ikke et fast id.
  const boern = boernIder(members);
  const appPersons: AppPerson[] = persons.map((p) => ({
    id: String(p.id),
    // Fallback til visning_navn er MIDLERTIDIG kompat (spec §4.9) — visning_fuldt_navn er NULL
    // for personer der endnu ikke er regenereret efter udledt-slægtsnavn-backfillen.
    name: personVisningsnavn(p, boern.has(String(p.id))),
    born: parseYear(p.visning_foedt),
    died: parseYear(p.visning_doed),
    foedtSpaend: aarSpaend(p.visning_foedt),
    // »† s.å.« opløses mod fødslen, så et barn, der døde samme år, ikke får et åbent dødsår.
    doedSpaend: aarSpaend(p.visning_doed == null ? null : oploesRelativDato(p.visning_doed, p.visning_foedt ?? null) ?? p.visning_doed),
    floruit: p.visning_floruit ?? null,
    years: fmtVisningsAar(p.visning_foedt, p.visning_doed, p.visning_floruit),
    foedtTekst: p.visning_foedt ?? null,
    doedTekst: p.visning_doed ?? null,
    title: p.visning_titel ?? '',
    fornavne: p.visning_navn ?? null,
    bio: '',
    privat: Boolean(p.privat),
    levende: Boolean(p.levende),
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
  const edges = sameAsEdges;
  const extMap = new Map((extIds || []).map((x) => [String(x.person_id), { linje: x.linje, nr: x.nr, nr_label: x.nr_label ?? null }]));
  const collapsed = collapseSameAs(rawDb, edges, extMap);
  if (collapsed.quarantined.length) console.warn('[samme_som] karantæne (foldes ikke):', collapsed.quarantined);

  const puRows = await puRowsP;
  const parentsUnknownByPerson = buildParentsUnknown(puRows.facts, puRows.conclusions, puRows.assertions, puRows.citations, collapsed.canonicalIdById);

  const model: AppModel = {
    ...buildModel(collapsed.db),
    lineage: buildLineage(extIds, lineageRows, collapsed.canonicalIdById, {
      schemes, entries: schemeEntries, mappings: schemeMappings,
    }, sources),
    sourcesBy: buildSources(extIds, sources, collapsed.canonicalIdById, stamtavleSkemaOpslag({ schemes, entries: schemeEntries, mappings: schemeMappings })),
    linjeRaekkerBy: byggLinjeRaekker(extIds, sources, collapsed.canonicalIdById, { schemes, entries: schemeEntries, mappings: schemeMappings }),
    canonicalIdById: collapsed.canonicalIdById,
    // Review 37 M11: redaktionens fold-prognose skal se det rå grundlag (ægteskaber + alle forældrekanter).
    ...(opts?.collapse === false ? { grundlagDb: rawDb } : {}),
    ...byggUdgaveModel(sources, extIds),
    // Geo-lag: starter TOMT (review 27 P3, "lazy geo-kæde") — place+fact hentes ikke ved
    // cold-start. loadGeo() henter dem + bygger den rigtige Geo, kaldt af web-laget ved
    // første kort-brug (Godser-kort, Slægtens kort, livsrejse-minikort).
    geo: EMPTY_GEO,
    genCoordsByPerson: buildGenCoords(extIds, lineageRows, collapsed.canonicalIdById),
    bogNrBy: byggBogNr(extIds, collapsed.canonicalIdById, byggErStamtavle(lineageRows, schemes)),
    parentsUnknownByPerson,
    adelsnavne: await adelsnavneP,
    skilsmisser: await skilsmisserP,
    loadGeo: async (): Promise<Geo> => {
      // Geo-lag: godser m. sted (allerede hentet ovenfor), steder m. koordinater, geo-bærende
      // fakta. Alt tolerant (tomt = ingen kortpunkter). place.not('lat',...) → 0 rækker/ét
      // round-trip før berigelse; .order('id') giver stabil paginering når place >1000 rækker
      // (tng_places ~6.788) efter berigelse.
      const [places, facts] = await Promise.all([
        getAll<RawPlace>(() => supabase.from('place').select('id,navn,lat,lon').not('lat', 'is', null).order('id')).catch((e) => { console.warn('[loadModel] place utilgængelig — intet geo:', e); return [] as RawPlace[]; }),
        getAll<RawFact>(() => supabase.from('fact').select('subjekt_type,subjekt_id,faktatype,sted_id').not('sted_id', 'is', null).order('id')).catch((e) => { console.warn('[loadModel] fact utilgængelig — intet geo:', e); return [] as RawFact[]; }),
      ]);
      // Geo-lag bygget på den COLLAPSED + (RLS-)privat-filtrerede db.persons — samme mønster som mobile.
      return buildGeo(
        { facts, estates, places, persons: collapsed.db.persons, unions: collapsed.db.unions },
        collapsed.canonicalIdById,
      );
    },
  };
  // Påfør proveniens på de foldede kanoniske personer (til badge i detalje-panelet).
  for (const [canon, prov] of Object.entries(collapsed.mergedFrom)) {
    if (model.byId[canon]) model.byId[canon].mergedFrom = prov;
  }
  return model;
}

// Hent de RÅ rækker til "forældre ukendt"-markeringer (faktatype 'forældre_ukendt' + afklaret
// konklusion + valgt assertions grad + citationens proveniens). Bevidst UDEN canonicalIdById, så
// den kan startes FØR collapse og overlappe hoved-batchen (buildParentsUnknown kanoniserer bagefter).
// Kæden er kort-cirkuleret på det (typisk lille/tomme) markerings-sæt. Tolerant — en fejl degraderer
// til tomme rækker (→ ingen kandidat-ringe), aldrig et brud på stamtræet.
type ParentsUnknownRows = {
  facts: { id: number | string; subjekt_id: number | string }[];
  conclusions: { target_id: number | string; valgt_assertion_id: number | string | null }[];
  assertions: { id: number | string; vaerdi_tekst: string | null }[];
  citations: { assertion_id: number | string; citat_tekst: string | null }[];
};

async function fetchParentsUnknownRows(): Promise<ParentsUnknownRows> {
  const empty: ParentsUnknownRows = { facts: [], conclusions: [], assertions: [], citations: [] };
  try {
    const facts = await getAll<ParentsUnknownRows['facts'][number]>(() =>
      supabase.from('fact').select('id,subjekt_id').eq('subjekt_type', 'person').eq('faktatype', 'forældre_ukendt').order('id'),
    );
    if (!facts.length) return empty;
    const factIds = facts.map((f) => f.id);
    const conclusions = await getAll<ParentsUnknownRows['conclusions'][number]>(() =>
      supabase.from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact').eq('status', 'afklaret').in('target_id', factIds).order('id'),
    );
    const assertionIds = conclusions.map((c) => c.valgt_assertion_id).filter((v): v is number | string => v != null);
    if (!assertionIds.length) return { facts, conclusions, assertions: [], citations: [] };
    const [assertions, citations] = await Promise.all([
      getAll<ParentsUnknownRows['assertions'][number]>(() =>
        supabase.from('assertion').select('id,vaerdi_tekst').in('id', assertionIds).order('id')),
      getAll<ParentsUnknownRows['citations'][number]>(() =>
        supabase.from('citation').select('assertion_id,citat_tekst').in('assertion_id', assertionIds).order('id')),
    ]);
    return { facts, conclusions, assertions, citations };
  } catch (e) {
    console.warn('[loadModel] forældre_ukendt-markeringer utilgængelige — ingen kandidat-ringe:', e);
    return empty;
  }
}
