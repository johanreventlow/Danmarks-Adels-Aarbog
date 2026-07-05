// Evidens-read-lag til person-editoren. Modellen er polymorf (assertion/conclusion peger på
// fact via target_type/target_id UDEN rigtig FK), så vi henter N flade queries og joiner i
// klienten. citation→source HAR FK og nestes (spec §3). Ren joinEvidence er testbar uden net.
import { supabase } from '../lib/supabase';
import { getAll } from './load';
import { parseYear, fmtYears } from './fields';
import { FELT_FAKTATYPE } from './redaktionWrite';

// --- Redaktions-person-liste (pagineret, inkl. levende/privat) ---

export type RedPerson = {
  id: string; navn: string; aar: string; born: number | null; levende: boolean; privat: boolean;
  // Proveniens/gennemsigtighed (udledt-slægtsnavn-design §4.4): true når visning_efternavn er
  // afledt af linje-medlemskab. `navn` forbliver den RÅ visning_navn.
  efternavnAfledt: boolean;
};
type RawRedPerson = {
  id: number; visning_navn: string | null; visning_efternavn: string | null; visning_foedt: string | null;
  visning_doed: string | null; levende: boolean | null; privat: boolean | null;
};

export function mapRedPerson(r: RawRedPerson): RedPerson {
  return {
    id: String(r.id),
    navn: r.visning_navn ?? '(uden navn)',
    aar: fmtYears(r.visning_foedt, r.visning_doed),
    born: parseYear(r.visning_foedt), // DIREKTE fra fødselsfeltet — aldrig dødsår
    levende: Boolean(r.levende),
    privat: Boolean(r.privat),
    efternavnAfledt: r.visning_efternavn != null,
  };
}

// Pagineret (PostgREST capper ved 1000 lydløst — getAll gentager .range indtil tomt).
// getAll kaster videre ved Supabase-error → ingen tom-som-clean (cycle 03 NEW1).
export async function fetchRedaktionPersoner(): Promise<RedPerson[]> {
  if (!supabase) return [];
  const sb = supabase;
  const rows = await getAll<RawRedPerson>(() =>
    sb.from('person').select('id,visning_navn,visning_efternavn,visning_foedt,visning_doed,levende,privat'));
  return rows.map(mapRedPerson);
}

// --- Evidens-læsning til person-editor ---

// faktatype → UI-felt (omvendt af FELT_FAKTATYPE).
const FAKTATYPE_FELT: Record<string, string> = Object.fromEntries(
  Object.entries(FELT_FAKTATYPE).map(([felt, ft]) => [ft, felt]),
);

export type Kilde = {
  sourceId: number | null;
  sourceTitel?: string;
  side?: string;
  citatTekst?: string;
  citatDato?: string;
};
export type Oplysning = {
  assertionId: number;
  vaerdi: string;
  dato?: { min: string | null; max: string | null; qualifier: string | null; raw: string | null };
  kilder: Kilde[];
  erKonklusion: boolean;
};
export type FeltEvidens = {
  felt: string;
  faktatype: string;
  factId: number;
  konklusionAssertionId: number | null;
  oplysninger: Oplysning[];
  uenig: boolean;
};
// felter: en LISTE af facts pr. felt — en person kan have flere facts af samme type
// (fx 6 titler gennem livet). Hvert fact er sin egen FeltEvidens (egne oplysninger +
// konklusion + uenig). uenig er PR. FACT (kilde-uenighed om samme forhold), ikke på tværs
// af distinkte facts (bruger-feedback 2026-06-28, fact-kardinalitet).
export type PersonEvidence = { felter: Record<string, FeltEvidens[]>; koen: string | null };

type RawFact = { id: number; faktatype: string };
type RawAssert = { id: number; target_id: number; vaerdi_tekst: string | null;
  date_min: string | null; date_max: string | null; date_qualifier: string | null; date_raw: string | null };
type RawConc = { target_id: number; valgt_assertion_id: number | null };
type RawCit = { assertion_id: number; source_id: number | null; side: string | null;
  citat_tekst: string | null; citat_dato: string | null; source?: { titel?: string } | null };

export function joinEvidence(rows: {
  facts: RawFact[]; assertions: RawAssert[]; conclusions: RawConc[]; citations: RawCit[]; koen: string | null;
}): PersonEvidence {
  const concByFact = new Map(rows.conclusions.map((c) => [c.target_id, c.valgt_assertion_id]));
  const citByAssert = new Map<number, Kilde[]>();
  for (const c of rows.citations) {
    const list = citByAssert.get(c.assertion_id) ?? [];
    list.push({
      sourceId: c.source_id, sourceTitel: c.source?.titel ?? undefined,
      side: c.side ?? undefined, citatTekst: c.citat_tekst ?? undefined, citatDato: c.citat_dato ?? undefined,
    });
    citByAssert.set(c.assertion_id, list);
  }
  const felter: Record<string, FeltEvidens[]> = {};
  // Stabil rækkefølge: facts pr. felt sorteres på fact-id (samme orden hver gang).
  const sortedFacts = [...rows.facts].sort((a, b) => a.id - b.id);
  for (const f of sortedFacts) {
    const felt = FAKTATYPE_FELT[f.faktatype];
    if (!felt) continue; // kun kerne-fakta (navn/foedt/doed/titel)
    const valgt = concByFact.get(f.id) ?? null;
    const opl = rows.assertions
      .filter((a) => a.target_id === f.id)
      .map<Oplysning>((a) => ({
        assertionId: a.id,
        vaerdi: a.vaerdi_tekst ?? a.date_raw ?? '',
        dato: a.date_raw != null || a.date_min != null
          ? { min: a.date_min, max: a.date_max, qualifier: a.date_qualifier, raw: a.date_raw } : undefined,
        kilder: citByAssert.get(a.id) ?? [],
        erKonklusion: a.id === valgt,
      }));
    // uenig = >1 DISTINKT NON-TOM værdi inden for DETTE fact (ægte kilde-uenighed). Tomme
    // værdier (manglende vaerdi_tekst+date_raw → '') ekskluderes — ellers ville en rigtig
    // værdi + en tom assertion give falsk "uenig" (Codex cycle 03 H1).
    const distinkte = new Set(opl.map((o) => o.vaerdi.trim()).filter(Boolean));
    (felter[felt] ??= []).push({
      felt, faktatype: f.faktatype, factId: f.id,
      konklusionAssertionId: valgt, oplysninger: opl, uenig: distinkte.size > 1,
    });
  }
  return { felter, koen: rows.koen };
}

export type Konflikt = { personId: string; felt: string; antalVaerdier: number; factId: number };

export function mapKonfliktRow(r: { person_id: number; faktatype: string; antal_vaerdier: number; fact_id?: number }): Konflikt {
  return {
    personId: String(r.person_id),
    felt: FAKTATYPE_FELT[r.faktatype] ?? r.faktatype,
    antalVaerdier: r.antal_vaerdier,
    factId: r.fact_id ?? 0,
  };
}

export async function fetchKonflikter(): Promise<Konflikt[]> {
  if (!supabase) return [];
  const { data, error } = await supabase.from('red_konflikt').select('person_id,faktatype,antal_vaerdier,fact_id');
  // Kast ved fejl — ellers ville en RLS/grant/migration-fejl vise sig som en TOM kø
  // ("ingen konflikter"), hvilket skjuler præcis de poster der skal gennemses (cycle 03 NEW1).
  if (error) throw new Error(error.message);
  return (data ?? []).map(mapKonfliktRow);
}

export type SletPreview = {
  antalRelationer: number;
  antalFacts: number;
  relationer: { rolle: string; retning: string; modpartId: number }[];
};

export async function fetchSletPreview(personId: string): Promise<SletPreview> {
  const tom: SletPreview = { antalRelationer: 0, antalFacts: 0, relationer: [] };
  if (!supabase) return tom;
  const { data, error } = await supabase.rpc('red_slet_person_preview', { p_person_id: Number(personId) });
  if (error || !data) return tom;
  return {
    antalRelationer: data.antal_relationer ?? 0,
    antalFacts: data.antal_facts ?? 0,
    relationer: (data.relationer ?? []).map((r: { rolle: string; retning: string; modpart_id: number }) => ({
      rolle: r.rolle,
      retning: r.retning,
      modpartId: r.modpart_id,
    })),
  };
}

// --- Narrativ-læsning til person-editor (Codex 2B #1: prefill-kilde == skrive-mål) ---

export type PersonNarrativ = { tekst: string; privat: boolean; sourceId: number | null };

export function mapNarrativRow(rows: { tekst: string | null; privat: boolean | null; source_id?: number | null }[]): PersonNarrativ | null {
  const first = rows[0];
  if (!first) return null;
  return { tekst: first.tekst ?? '', privat: Boolean(first.privat), sourceId: first.source_id ?? null };
}

// Henter FØRSTE narrativ by id (uanset privat) = præcis den række red_upsert_narrativ redigerer.
// Prefill-kilde == skrive-mål; privat-flaget bevares af editoren på Gem (Codex 2B #1).
export async function fetchPersonNarrativ(id: string): Promise<PersonNarrativ | null> {
  if (!supabase) return null;
  const { data, error } = await supabase
    .from('narrative').select('tekst,privat,source_id')
    .eq('subjekt_type', 'person').eq('subjekt_id', Number(id))
    .order('id', { ascending: true }).limit(1);
  if (error) throw new Error(error.message);
  return mapNarrativRow(data ?? []);
}

// --- Relationer pr. person (pagineret, inkl. id til redaktøren) ---

export type PersonRelation = {
  relationId: number; art: 'hverv' | 'gods' | 'event';
  objektType: string; objektId: string; navn: string; rolle: string; periode: string;
};
type RawRelRow = { id: number; objekt_type: string; objekt_id: number; rolle: string | null; periode_raw: string | null };

export function mapRelationRow(rows: RawRelRow[], aux: import('./types').Aux | null): PersonRelation[] {
  const orgNavn = new Map((aux?.orgListe ?? []).map((o) => [o.id, o.navn]));
  const godsNavn = new Map((aux?.godsListe ?? []).map((g) => [g.id, g.navn]));
  return rows.map((r) => {
    const objektId = String(r.objekt_id);
    let art: PersonRelation['art'] = 'event';
    let navn = `Begivenhed #${objektId}`;
    if (r.objekt_type === 'organisation') { art = 'hverv'; navn = orgNavn.get(objektId) ?? `#${objektId}`; }
    else if (r.objekt_type === 'estate') { art = 'gods'; navn = godsNavn.get(objektId) ?? `#${objektId}`; }
    return { relationId: r.id, art, objektType: r.objekt_type, objektId, navn, rolle: r.rolle ?? '', periode: r.periode_raw ?? '' };
  });
}

export async function fetchPersonRelationer(id: string, aux: import('./types').Aux | null): Promise<PersonRelation[]> {
  if (!supabase) return [];
  const sb = supabase;
  const rows = await getAll<RawRelRow>(() =>
    sb.from('relation').select('id,objekt_type,objekt_id,rolle,periode_raw')
      .eq('subjekt_type', 'person').eq('subjekt_id', Number(id))
      .in('objekt_type', ['organisation', 'estate', 'historical_event']).order('id'));
  return mapRelationRow(rows, aux);
}

// --- Familie-læsning til person-editor (2C-2b) ---

export type FamiliePartner = { personId: string; navn: string; aar: string; konfidens: string | null; ordinal: number | null };
export type FamilieBarn = { personId: string; navn: string; aar: string; rolle: string; konfidens: string | null; ordinal: number | null };
export type FamilieUnion = { familyId: string; type: string; partnere: FamiliePartner[]; boern: FamilieBarn[] };
export type SomBarn = { familyId: string; rolle: string; konfidens: string | null; foraeldre: { personId: string; navn: string }[] };
export type PersonFamilie = { somPartner: FamilieUnion[]; somBarn: SomBarn[] };
type RawFamRow = { family_id: number; person_id: number; rolle: string; ordinal: number | null; konfidens: string | null };
type RawFamilyMeta = { id: number; type: string | null };

// Beregner ny ordinal-værdi til at flytte ét barn ét skridt op/ned i søskende-visningsrækkefølgen
// (brugerfund 2026-07-02: rækkefølgen kan være kendt selvom fødselsår mangler/er upræcist).
// "Klem ind"-teknik: sætter KUN det flyttede barns ordinal (ét red_set_familie_ordinal-kald),
// til en værdi der sorterer lige før/efter naboen — rører aldrig naboens egen ordinal-værdi.
// `boern` skal være i NUVÆRENDE visningsrækkefølge (som fetchPersonFamilie allerede leverer).
// Ordinal har ingen DB-unikhedstvang, så et evt. sammenfald efter mange gentagne flytninger er
// harmløst (falder tilbage til person_id-sortering) — ikke en fejltilstand.
export function nudgeOrdinal(
  boern: { ordinal: number | null }[],
  index: number,
  retning: 'op' | 'ned',
): number | null {
  const effektiv = (i: number) => boern[i].ordinal ?? (i + 1) * 10;
  if (retning === 'op') return index > 0 ? effektiv(index - 1) - 1 : null;
  return index < boern.length - 1 ? effektiv(index + 1) + 1 : null;
}
export const BARN_ROLLER = ['barn', 'adopteret_barn', 'plejebarn', 'stedbarn'] as const;

export function mapFamilieRows(personId: string, families: RawFamilyMeta[], members: RawFamRow[], model: import('./types').Model | null): PersonFamilie {
  const navnAf = (pid: number) => model?.byId?.[String(pid)]?.name ?? `#${pid}`;
  // Fødsels/dødsår fra samme cache som navnet (model.byId[pid].years) — ingen ekstra query.
  const aarAf = (pid: number) => model?.byId?.[String(pid)]?.years ?? '';
  const typeAf = new Map(families.map((f) => [String(f.id), f.type ?? '']));
  const byFamily = new Map<string, RawFamRow[]>();
  members.forEach((m) => {
    const k = String(m.family_id);
    if (!byFamily.has(k)) byFamily.set(k, []);
    byFamily.get(k)!.push(m);
  });
  const somPartner: FamilieUnion[] = [];
  const somBarn: SomBarn[] = [];
  byFamily.forEach((rows, familyId) => {
    // Bucket ALLE fokus-personens medlemskaber i denne familie — ikke kun det første
    // (cycle 07 Codex H2): family_member-PK inkluderer rolle, så samme person kan have flere
    // barn-roller i samme familie; find-first ville skjule de øvrige links (uredigerbare).
    const migRows = rows.filter((r) => String(r.person_id) === personId);
    if (!migRows.length) return;
    if (migRows.some((r) => r.rolle === 'partner')) {
      somPartner.push({
        familyId, type: typeAf.get(familyId) ?? '',
        partnere: rows.filter((r) => r.rolle === 'partner' && String(r.person_id) !== personId)
          .map((r) => ({ personId: String(r.person_id), navn: navnAf(r.person_id), aar: aarAf(r.person_id), konfidens: r.konfidens, ordinal: r.ordinal })),
        boern: rows.filter((r) => (BARN_ROLLER as readonly string[]).includes(r.rolle) && String(r.person_id) !== personId)
          .map((r) => ({ personId: String(r.person_id), navn: navnAf(r.person_id), aar: aarAf(r.person_id), rolle: r.rolle, konfidens: r.konfidens, ordinal: r.ordinal })),
      });
    }
    migRows.filter((r) => (BARN_ROLLER as readonly string[]).includes(r.rolle)).forEach((mig) => {
      somBarn.push({
        familyId, rolle: mig.rolle, konfidens: mig.konfidens,
        foraeldre: rows.filter((r) => r.rolle === 'partner')
          .map((r) => ({ personId: String(r.person_id), navn: navnAf(r.person_id) })),
      });
    });
  });
  return { somPartner, somBarn };
}

export async function fetchPersonFamilie(id: string, model: import('./types').Model | null): Promise<PersonFamilie> {
  if (!supabase) return { somPartner: [], somBarn: [] };
  const sb = supabase;
  const mine = await getAll<{ family_id: number }>(() =>
    sb.from('family_member').select('family_id').eq('person_id', Number(id)));
  const famIds = Array.from(new Set(mine.map((m) => m.family_id)));
  if (!famIds.length) return { somPartner: [], somBarn: [] };
  const [members, families] = await Promise.all([
    getAll<RawFamRow>(() =>
      sb.from('family_member').select('family_id,person_id,rolle,ordinal,konfidens').in('family_id', famIds)
        .order('ordinal', { ascending: true, nullsFirst: false }).order('person_id')),
    getAll<RawFamilyMeta>(() =>
      sb.from('family').select('id,type').in('id', famIds)),
  ]);
  return mapFamilieRows(id, families, members, model);
}

export async function fetchPersonEvidence(personId: string): Promise<PersonEvidence> {
  const empty: PersonEvidence = { felter: {}, koen: null };
  if (!supabase) return empty;
  const pid = Number(personId);
  const { data: facts } = await supabase
    .from('fact').select('id,faktatype').eq('subjekt_type', 'person').eq('subjekt_id', pid);
  const factIds = (facts ?? []).map((f: RawFact) => f.id);
  if (!factIds.length) {
    const { data: p0 } = await supabase.from('person').select('koen').eq('id', pid).maybeSingle();
    return { felter: {}, koen: p0?.koen ?? null };
  }
  const [{ data: assertions }, { data: conclusions }, { data: person }] = await Promise.all([
    supabase.from('assertion').select('id,target_id,vaerdi_tekst,date_min,date_max,date_qualifier,date_raw')
      .eq('target_type', 'fact').in('target_id', factIds),
    supabase.from('conclusion').select('target_id,valgt_assertion_id')
      .eq('target_type', 'fact').in('target_id', factIds),
    supabase.from('person').select('koen').eq('id', pid).maybeSingle(),
  ]);
  const assertIds = (assertions ?? []).map((a: RawAssert) => a.id);
  const { data: citations } = assertIds.length
    ? await supabase.from('citation')
        .select('assertion_id,source_id,side,citat_tekst,citat_dato,source(titel)')
        .in('assertion_id', assertIds)
    : { data: [] };
  return joinEvidence({
    facts: (facts ?? []) as RawFact[],
    assertions: (assertions ?? []) as RawAssert[],
    conclusions: (conclusions ?? []) as RawConc[],
    citations: (citations ?? []) as RawCit[],
    koen: person?.koen ?? null,
  });
}

// ---------- Historik (versionering — DB-lag T2/T3/T11) ----------
export type HistPost = { id: string; hvem: string; hvornaar: string; resume: string; reverteret: boolean };
type RawHist = { id: number; actor_navn: string | null; created_at: string;
                 summary: string | null; reverterer_id: number | null };

// revertedIds: id'er på rækker der ER blevet fortrudt af en ANDEN række i samme liste
// (review10 H2). r.reverterer_id peger omvendt — fra fortrydelsen TIL den fortrudte —
// så status kan ikke afgøres af rækken selv; den kræver hele listens reverterer_id-mængde.
export function mapHistRow(r: RawHist, revertedIds: ReadonlySet<number> = new Set()): HistPost {
  return {
    id: String(r.id),
    hvem: r.actor_navn ?? 'ukendt',
    hvornaar: new Date(r.created_at).toLocaleString('da-DK'),
    resume: r.summary ?? '(uden beskrivelse)',
    reverteret: revertedIds.has(r.id),
  };
}

export async function fetchHistorik(personId: string): Promise<HistPost[]> {
  if (!supabase) return [];
  const { data, error } = await supabase.rpc('hist_for_subjekt', { p_type: 'person', p_id: Number(personId) });
  if (error) throw new Error(error.message);
  const rows: RawHist[] = data ?? [];
  const revertedIds = new Set(rows.map((r) => r.reverterer_id).filter((id): id is number => id != null));
  return rows.map((r) => mapHistRow(r, revertedIds));
}

// ---------- Døde links (hyperlinks — DB-lag T10/T11) ----------
export type DoedLink = { kilde: string; maalType: string; maalId: string };
export function mapDoedLinkRow(r: { kilde_type: string; kilde_id: number; maal_type: string; maal_id: number }): DoedLink {
  return { kilde: `${r.kilde_type}#${r.kilde_id}`, maalType: r.maal_type, maalId: String(r.maal_id) };
}
export async function fetchDoedeLinks(): Promise<DoedLink[]> {
  if (!supabase) return [];
  const { data, error } = await supabase.from('red_doede_links').select('*');
  if (error) throw new Error(error.message);
  return (data ?? []).map(mapDoedLinkRow);
}

// --- Medier pr. person/objekt (mediehåndtering Slice 0g+0h) ---
// relation er polymorf uden FK (samme mønster som fakta/relationer ovenfor) — to flade queries:
// afbildet-links (til at finde media-id + relation-id), så media-rækkerne selv. redaktion_read-RLS
// viser ALLE upload_status (også 'kladde'), så redaktøren ser egne uploads uanset rettigheds-status.
// upload_status='fjernet' (Slice 0h "slet billede") filtreres altid væk her — den ligger stadig i
// basen (fortrydbar via historik), men skal ikke vises i den almindelige materiale-galleri.
export type PersonMedia = {
  id: string; relationId: string; slags: string; titel: string | null; storagePath: string | null;
  uploadStatus: string; maaPubliceres: boolean; thumbStoragePath: string | null;
};
type RawPersonMediaRow = { id: number; slags: string | null; titel: string | null;
  storage_path: string | null; upload_status: string | null; maa_publiceres: boolean | null };

// thumbPathByMediaId (billedstørrelser 2026-07-05, Slice B3) er valgfri (default tom Map) så testen
// kan kalde ren, netværksfri — kun mediaFromRelPairs nedenfor sender reelt en udfyldt Map.
export function mapPersonMediaRows(
  rows: RawPersonMediaRow[],
  relByMediaId: Map<string, string> = new Map(),
  thumbPathByMediaId: Map<string, string> = new Map(),
): PersonMedia[] {
  return rows
    .filter((m) => m.upload_status !== 'fjernet')
    .map((m) => ({
      id: String(m.id),
      relationId: relByMediaId.get(String(m.id)) ?? '',
      slags: m.slags ?? '',
      titel: m.titel,
      storagePath: m.storage_path,
      uploadStatus: m.upload_status ?? 'kladde',
      maaPubliceres: Boolean(m.maa_publiceres),
      thumbStoragePath: thumbPathByMediaId.get(String(m.id)) ?? null,
    }));
}

// Fælles hale: rel-par (media-id + relation-id) → signede/mappede PersonMedia. Retningen af selve
// relations-forespørgslen (person→media vs. media→objekt) afgøres af kalderne nedenfor.
async function mediaFromRelPairs(sb: NonNullable<typeof supabase>, pairs: { mediaId: number; relationId: number }[]): Promise<PersonMedia[]> {
  if (!pairs.length) return [];
  const relByMediaId = new Map(pairs.map((p) => [String(p.mediaId), String(p.relationId)]));
  const mediaIds = pairs.map((p) => p.mediaId);
  const [rows, variants] = await Promise.all([
    getAll<RawPersonMediaRow>(() =>
      sb.from('media').select('id,slags,titel,storage_path,upload_status,maa_publiceres').in('id', mediaIds)),
    getAll<{ media_id: number; storage_path: string }>(() =>
      sb.from('media_variant').select('media_id,storage_path').eq('tier', 'thumb').in('media_id', mediaIds)),
  ]);
  const thumbPathByMediaId = new Map(variants.map((v) => [String(v.media_id), v.storage_path]));
  return mapPersonMediaRows(rows, relByMediaId, thumbPathByMediaId);
}

export async function fetchPersonMedia(id: string): Promise<PersonMedia[]> {
  if (!supabase) return [];
  const sb = supabase;
  const rels = await getAll<{ id: number; objekt_id: number }>(() =>
    sb.from('relation').select('id,objekt_id')
      .eq('subjekt_type', 'person').eq('subjekt_id', Number(id))
      .eq('objekt_type', 'media').eq('rolle', 'afbildet'));
  return mediaFromRelPairs(sb, rels.map((r) => ({ mediaId: r.objekt_id, relationId: r.id })));
}

// Objekt-foto (gods/våben m.fl.): relationen går OMVENDT af person-varianten — media er subjekt,
// objektet (estate/coat_of_arms) er objekt (jf. red_upload_media's p_objekt_type-gren).
export async function fetchObjectMediaRed(objektType: string, objektId: string): Promise<PersonMedia[]> {
  if (!supabase) return [];
  const sb = supabase;
  const rels = await getAll<{ id: number; subjekt_id: number }>(() =>
    sb.from('relation').select('id,subjekt_id')
      .eq('subjekt_type', 'media')
      .eq('objekt_type', objektType).eq('objekt_id', Number(objektId))
      .eq('rolle', 'afbildet'));
  return mediaFromRelPairs(sb, rels.map((r) => ({ mediaId: r.subjekt_id, relationId: r.id })));
}

// --- samme_som identitets-links (spec 2026-07-02) ---
export type SammeSomLink = { relationId: string; retning: 'alias' | 'kanonisk'; modpartId: string };

// Klassificér rå samme_som-rækker set fra personId: alias hvis personen er subjekt (peger på en
// kanonisk), kanonisk hvis personen er objekt (andre peger på den). Ren/testbar.
export function mapSammeSomLinks(
  personId: string,
  rows: { id: number | string; subjekt_id: number | string; objekt_id: number | string }[],
): SammeSomLink[] {
  return rows.map((r) =>
    String(r.subjekt_id) === personId
      ? { relationId: String(r.id), retning: 'alias' as const, modpartId: String(r.objekt_id) }
      : { relationId: String(r.id), retning: 'kanonisk' as const, modpartId: String(r.subjekt_id) },
  );
}

// Hent alle samme_som-links der involverer personId (begge retninger).
export async function fetchSammeSomLinks(personId: string): Promise<SammeSomLink[]> {
  if (!supabase) return [];
  const { data } = await supabase
    .from('relation')
    .select('id,subjekt_id,objekt_id')
    .eq('rolle', 'samme_som')
    .eq('subjekt_type', 'person')
    .eq('objekt_type', 'person')
    .or(`subjekt_id.eq.${Number(personId)},objekt_id.eq.${Number(personId)}`);
  return mapSammeSomLinks(personId, (data ?? []) as never);
}
