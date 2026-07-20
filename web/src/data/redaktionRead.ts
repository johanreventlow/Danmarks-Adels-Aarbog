// Evidens-read-lag til web-redaktørbordet — porteret fra mobil (mobile/src/data/redaktionRead.ts).
// Modellen er polymorf (assertion/conclusion peger på fact via target_type/target_id UDEN rigtig
// FK), så vi henter N flade queries og joiner i klienten. citation→source HAR FK og nestes.
// joinEvidence er ren/testbar uden net.
import { supabase } from '../supabase';
import { fmtYears, parseYear, getAll, buildMatchPersoner, parseIkkeSammeSomPar, buildFamilyGraph } from '@daa/core';
import type { RedMatchPerson, MatchPersonRow, MatchFactRow, MatchConcRow, MatchAssertRow, MatchExtIdRow, RawFamilyMember, Union, ParentChild } from '@daa/core';
import { FELT_FAKTATYPE } from './redaktionWrite';
import { resolveOrgEstateNames } from './public';
import { signPaths, fetchThumbPathByMediaId } from './media';
import type { Model } from './types';

// --- Redaktions-person-liste (pagineret, inkl. levende/privat) ---

export type RedPerson = {
  id: string; navn: string; aar: string; born: number | null; levende: boolean; privat: boolean;
  // Proveniens/gennemsigtighed (udledt-slægtsnavn-design §4.4): true når visning_efternavn er
  // afledt af linje-medlemskab. `navn` forbliver den RÅ visning_navn — redaktion collapser/
  // omskriver aldrig bogens påstand, kun et badge markerer at et efternavn er tilføjet ved visning.
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

export async function fetchRedaktionPersoner(): Promise<RedPerson[]> {
  const rows = await getAll<RawRedPerson>(() =>
    supabase.from('person').select('id,visning_navn,visning_efternavn,visning_foedt,visning_doed,levende,privat'));
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
// felter: en LISTE af facts pr. felt — en person kan have flere facts af samme type (fx 6 titler
// gennem livet). uenig er PR. FACT (kilde-uenighed om samme forhold), ikke på tværs af distinkte facts.
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
    // uenig = >1 DISTINKT NON-TOM værdi inden for DETTE fact. Tomme værdier ekskluderes
    // (ellers ville en rigtig værdi + en tom assertion give falsk "uenig").
    const distinkte = new Set(opl.map((o) => o.vaerdi.trim()).filter(Boolean));
    (felter[felt] ??= []).push({
      felt, faktatype: f.faktatype, factId: f.id,
      konklusionAssertionId: valgt, oplysninger: opl, uenig: distinkte.size > 1,
    });
  }
  return { felter, koen: rows.koen };
}

export async function fetchPersonEvidence(personId: string): Promise<PersonEvidence> {
  const empty: PersonEvidence = { felter: {}, koen: null };
  if (!personId) return empty;
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

// --- "Forældre ukendt"-markering (docs/reviews/25): den aktuelle afklarede markering på en person ---
// Returnerer null hvis personen IKKE er markeret. factId bruges til fjern (tilbagetræk hele fakta-slottet).
export type ForaeldreUkendtMarkering = { factId: number; assertionId: number; grade: string; kilde: string | null };

export async function fetchForaeldreUkendtMarkering(personId: string): Promise<ForaeldreUkendtMarkering | null> {
  if (!personId) return null;
  const pid = Number(personId);
  const { data: facts, error: fErr } = await supabase
    .from('fact').select('id').eq('subjekt_type', 'person').eq('subjekt_id', pid).eq('faktatype', 'forældre_ukendt');
  if (fErr) throw fErr;
  const factIds = (facts ?? []).map((f: { id: number }) => f.id);
  if (!factIds.length) return null;
  const { data: conc, error: cErr } = await supabase
    .from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact').eq('status', 'afklaret')
    .in('target_id', factIds).order('target_id').limit(1).maybeSingle(); // deterministisk (laveste fact-id) — spejler PU-loaderens .order('id')
  if (cErr) throw cErr;
  const aid = conc?.valgt_assertion_id;
  const fid = conc?.target_id;
  if (aid == null || fid == null) return null;
  const [{ data: a }, { data: cit }] = await Promise.all([
    supabase.from('assertion').select('vaerdi_tekst').eq('id', aid).maybeSingle(),
    supabase.from('citation').select('citat_tekst').eq('assertion_id', aid).limit(1).maybeSingle(),
  ]);
  return { factId: Number(fid), assertionId: Number(aid), grade: a?.vaerdi_tekst ?? '', kilde: cit?.citat_tekst ?? null };
}

// --- Forældrefamilie-slot (Problem 2): konkurrerende forældre-påstande pr. barn ---
// Redaktion-only sti VED SIDEN AF den offentlige familie-læsning (model.ts rører IKKE slottet —
// blast-radius-vagt, spec §2/§8). Ren buildForaeldreSlot samler de flade queries (polymorf model).
export type ForaeldreForaelder = { personId: number; navn: string };
export type ForaeldrePaastand = {
  assertionId: number; familyId: number; foraeldre: ForaeldreForaelder[];
  udgave: string | null; side: string | null; citat: string | null; valgt: boolean;
};
export type ForaeldreSlot = { factId: number; status: string | null; paastande: ForaeldrePaastand[] };

type RawSlotAssert = { id: number; objekt_id: number | null };
type RawSlotCit = { assertion_id: number; side: string | null; citat_tekst: string | null;
  source: { udgave: string | null; titel: string | null } | null };
type RawSlotConc = { valgt_assertion_id: number | null; status: string | null };
type RawFamPartner = { family_id: number; person_id: number; visning_navn: string | null };

export function buildForaeldreSlot(
  factId: number, assertions: RawSlotAssert[], citations: RawSlotCit[],
  conclusion: RawSlotConc | null, partners: RawFamPartner[],
): ForaeldreSlot {
  const citByAssert = new Map<number, RawSlotCit>();
  for (const c of citations) if (!citByAssert.has(c.assertion_id)) citByAssert.set(c.assertion_id, c);
  const partnersByFam = new Map<number, ForaeldreForaelder[]>();
  for (const p of partners) {
    const arr = partnersByFam.get(p.family_id) ?? [];
    arr.push({ personId: p.person_id, navn: p.visning_navn ?? '(ukendt)' });
    partnersByFam.set(p.family_id, arr);
  }
  const valgt = conclusion?.valgt_assertion_id ?? null;
  const paastande = assertions
    .filter((a) => a.objekt_id != null)
    .map((a) => {
      const cit = citByAssert.get(a.id);
      return {
        assertionId: a.id, familyId: a.objekt_id as number,
        foraeldre: partnersByFam.get(a.objekt_id as number) ?? [],
        udgave: cit?.source?.udgave ?? cit?.source?.titel ?? null,
        side: cit?.side ?? null, citat: cit?.citat_tekst ?? null,
        valgt: a.id === valgt,
      };
    });
  return { factId, status: conclusion?.status ?? null, paastande };
}

export async function fetchForaeldreSlot(personId: string): Promise<ForaeldreSlot | null> {
  if (!personId) return null;
  const pid = Number(personId);
  const { data: facts } = await supabase.from('fact').select('id')
    .eq('subjekt_type', 'person').eq('subjekt_id', pid).eq('faktatype', 'forældrefamilie');
  const factId = (facts ?? [])[0]?.id;
  if (factId == null) return null;
  const { data: assertions } = await supabase.from('assertion').select('id,objekt_id')
    .eq('target_type', 'fact').eq('target_id', factId).eq('objekt_type', 'family');
  const aList = (assertions ?? []) as RawSlotAssert[];
  const aids = aList.map((a) => a.id);
  const famIds = aList.map((a) => a.objekt_id).filter((x): x is number => x != null);
  const [citRes, concRes, partRes] = await Promise.all([
    aids.length ? supabase.from('citation').select('assertion_id,side,citat_tekst,source(udgave,titel)').in('assertion_id', aids).order('id') : Promise.resolve({ data: [] as unknown[] }),
    supabase.from('conclusion').select('valgt_assertion_id,status').eq('target_type', 'fact').eq('target_id', factId).maybeSingle(),
    famIds.length ? supabase.from('family_member').select('family_id,person_id,person(visning_navn)').in('family_id', famIds).eq('rolle', 'partner') : Promise.resolve({ data: [] as unknown[] }),
  ]);
  const flatPartners: RawFamPartner[] = ((partRes.data ?? []) as { family_id: number; person_id: number; person: { visning_navn: string | null } | null }[])
    .map((p) => ({ family_id: p.family_id, person_id: p.person_id, visning_navn: p.person?.visning_navn ?? null }));
  return buildForaeldreSlot(Number(factId), aList, (citRes.data ?? []) as RawSlotCit[], (concRes.data ?? null) as RawSlotConc | null, flatPartners);
}

// En persons EGEN fødselsfamilie + kildeudgave — bruges til §6 trin (a): importér en samme_som-
// linket persons (anden udgaves) forældre som en rival-påstand på den kanoniske person.
export type BarnFamilie = { familyId: number; foraeldre: ForaeldreForaelder[]; sourceId: number | null; udgave: string | null };

export async function fetchBarnFamilie(personId: string): Promise<BarnFamilie | null> {
  if (!personId) return null;
  const pid = Number(personId);
  const { data: bm } = await supabase.from('family_member').select('family_id').eq('person_id', pid).eq('rolle', 'barn').maybeSingle();
  const familyId = (bm as { family_id: number } | null)?.family_id;
  if (familyId == null) return null;
  const [partRes, extRes] = await Promise.all([
    supabase.from('family_member').select('person_id,person(visning_navn)').eq('family_id', familyId).eq('rolle', 'partner'),
    supabase.from('person_external_id').select('source_id,source(udgave,titel)').eq('person_id', pid).order('source_id').limit(1).maybeSingle(),
  ]);
  const foraeldre: ForaeldreForaelder[] = ((partRes.data ?? []) as unknown as { person_id: number; person: { visning_navn: string | null } | null }[])
    .map((p) => ({ personId: p.person_id, navn: p.person?.visning_navn ?? '(ukendt)' }));
  const ext = extRes.data as unknown as { source_id: number | null; source: { udgave: string | null; titel: string | null } | null } | null;
  return { familyId, foraeldre, sourceId: ext?.source_id ?? null, udgave: ext?.source?.udgave ?? ext?.source?.titel ?? null };
}

export type ForaeldreKonflikt = { personId: number; factId: number; antalFamilier: number; antalPaastande: number; status: string | null; navn: string | null };

export async function fetchForaeldreKonflikter(): Promise<ForaeldreKonflikt[]> {
  // Kast fejl frem for tavst [] (review 30): dette er discovery-fladen — en brudt view/RLS må
  // IKKE maskeres som "ingen konflikter".
  const { data, error } = await supabase.from('red_foraeldre_konflikt').select('person_id,fact_id,antal_familier,antal_paastande,status');
  if (error) throw error;
  const rows = (data ?? []) as { person_id: number; fact_id: number; antal_familier: number; antal_paastande: number; status: string | null }[];
  if (!rows.length) return [];
  const { data: persons } = await supabase.from('person').select('id,visning_navn').in('id', rows.map((r) => r.person_id));
  const navnById = new Map(((persons ?? []) as { id: number; visning_navn: string | null }[]).map((p) => [p.id, p.visning_navn]));
  return rows.map((r) => ({ personId: r.person_id, factId: r.fact_id, antalFamilier: r.antal_familier,
    antalPaastande: r.antal_paastande, status: r.status, navn: navnById.get(r.person_id) ?? null }));
}

// --- Narrativ-læsning: ALLE udgaver pr. person (source-join til byline + ordning) ---
// Én narrativ pr. (person, source_id). Redaktøren viser en fane pr. udgave; skrive-målet
// (red_upsert_narrativ) nøgles på source_id, så prefill-kilde == skrive-mål pr. udgave.

// Generel slægtsbeskrivelse (billeder-i-narrativer 2026-07-05, Slice C3): subjekt_type='slaegt' har
// INGEN bagvedliggende tabel — subjekt_id er en FAST, delt sentinel-konstant (ikke en fremmednøgle
// til noget), nødvendig fordi narrative.subjekt_id er NOT NULL. Kanonisk ét sted (ikke ét pr.
// skærm) i dette read-lag, som allerede er fetchNarrativer's naturlige hjem.
export const SLAEGT_SUBJEKT_ID = 1;

export type PersonNarrativ = { id: number; sourceId: number | null; sourceTitel: string | null; udgave: string | null; side: string | null; tekst: string; privat: boolean };

type RawNarrativRow = { id: number; source_id: number | null; side: string | null; tekst: string | null; privat: boolean | null; source: { titel: string | null; udgave: string | null } | null };

export function mapNarrativer(rows: RawNarrativRow[]): PersonNarrativ[] {
  return rows
    .map((r) => ({
      id: r.id, sourceId: r.source_id, sourceTitel: r.source?.titel ?? null,
      udgave: r.source?.udgave ?? null, side: r.side, tekst: r.tekst ?? '', privat: Boolean(r.privat),
    }))
    .sort((a, b) => (a.sourceId ?? Infinity) - (b.sourceId ?? Infinity) || a.id - b.id);
}

// Generaliseret fra person-only til ethvert subjekt (billeder-i-narrativer 2026-07-05, Slice C3)
// — slægts/linje-narrativer bruger samme udgave-fane-mønster som person-narrativer, samme RPC
// (red_upsert_narrativ), blot en anden (subjekt_type, subjekt_id).
export async function fetchNarrativer(subjektType: string, subjektId: number): Promise<PersonNarrativ[]> {
  const { data, error } = await supabase
    .from('narrative').select('id,source_id,side,tekst,privat,source:source_id(titel,udgave)')
    .eq('subjekt_type', subjektType).eq('subjekt_id', subjektId)
    .order('source_id', { ascending: true }).order('id', { ascending: true });
  if (error) throw new Error(error.message);
  return mapNarrativer((data ?? []) as unknown as RawNarrativRow[]);
}

// --- Hændelses-tidslinje (levende feed fase 2) ---
export type HaendelsePost = {
  id: number; klausul: string; kategori: string | null;
  dato: { min: string | null; max: string | null; qualifier: string | null; raw: string | null };
  feedStatus: 'kandidat' | 'interessant' | 'skjult';
  narrativeId: number; spanStart: number | null; spanLaengde: number | null;
  sourceId?: number; sourceTitel?: string; side?: string;
  factId: number | null; relationId: number | null;
};
type RawHaendelseRow = {
  id: number; klausul: string; kategori: string | null;
  date_min: string | null; date_max: string | null; date_qualifier: string | null; date_raw: string | null;
  feed_status: 'kandidat' | 'interessant' | 'skjult'; narrative_id: number;
  span_start: number | null; span_laengde: number | null; fact_id: number | null; relation_id: number | null;
  narrative: { side: string | null; source: { id: number; titel: string | null; udgave: string | null } | null } | null;
};

export function mapHaendelser(rows: RawHaendelseRow[]): HaendelsePost[] {
  return rows.map((r) => ({
    id: Number(r.id), klausul: r.klausul, kategori: r.kategori,
    dato: { min: r.date_min, max: r.date_max, qualifier: r.date_qualifier, raw: r.date_raw },
    feedStatus: r.feed_status, narrativeId: Number(r.narrative_id),
    spanStart: r.span_start, spanLaengde: r.span_laengde,
    sourceId: r.narrative?.source?.id != null ? Number(r.narrative.source.id) : undefined,
    sourceTitel: r.narrative?.source?.titel ?? r.narrative?.source?.udgave ?? undefined,
    side: r.narrative?.side ?? undefined,
    factId: r.fact_id == null ? null : Number(r.fact_id),
    relationId: r.relation_id == null ? null : Number(r.relation_id),
  }));
}

export async function fetchHaendelserForPerson(personId: string): Promise<HaendelsePost[]> {
  if (!personId) return [];
  const { data, error } = await supabase.from('haendelse')
    .select('id,klausul,kategori,date_min,date_max,date_qualifier,date_raw,feed_status,narrative_id,span_start,span_laengde,fact_id,relation_id,narrative:narrative_id(side,source:source_id(id,titel,udgave))')
    .eq('subjekt_type', 'person').eq('subjekt_id', Number(personId)).order('id');
  if (error) throw new Error(error.message);
  return mapHaendelser((data ?? []) as unknown as RawHaendelseRow[]);
}

export type TidslinjePost = {
  art: 'haendelse' | 'rygrad'; id: string;
  dato: HaendelsePost['dato']; klausul: string; kategori: string | null;
  sourceId?: number; sourceTitel?: string; side?: string; narrativeId?: number;
  spanStart?: number | null; spanLaengde?: number | null;
  haendelseId?: number; feedStatus?: HaendelsePost['feedStatus']; factId?: number;
};

export function buildTidslinje(haendelser: HaendelsePost[], evidens: PersonEvidence): TidslinjePost[] {
  const poster: TidslinjePost[] = [];
  const linked = new Set<number>();
  for (const feltFacts of Object.values(evidens.felter)) for (const fact of feltFacts) {
    const valgt = fact.oplysninger.find((o) => o.erKonklusion && o.dato);
    if (!valgt?.dato) continue;
    const h = haendelser.find((x) => x.factId === fact.factId);
    if (h) linked.add(h.id);
    const kilde = valgt.kilder[0];
    poster.push({
      art: 'rygrad', id: `f:${fact.factId}`, factId: fact.factId, dato: valgt.dato,
      klausul: h?.klausul ?? valgt.vaerdi, kategori: h?.kategori ?? fact.faktatype,
      sourceId: h?.sourceId ?? kilde?.sourceId ?? undefined,
      sourceTitel: h?.sourceTitel ?? kilde?.sourceTitel, side: h?.side ?? kilde?.side,
      narrativeId: h?.narrativeId, spanStart: h?.spanStart, spanLaengde: h?.spanLaengde,
    });
  }
  for (const h of haendelser) if (!linked.has(h.id)) poster.push({
    art: 'haendelse', id: `h:${h.id}`, haendelseId: h.id, dato: h.dato,
    klausul: h.klausul, kategori: h.kategori, sourceId: h.sourceId,
    sourceTitel: h.sourceTitel, side: h.side,
    narrativeId: h.narrativeId, spanStart: h.spanStart, spanLaengde: h.spanLaengde,
    feedStatus: h.feedStatus, factId: h.factId ?? undefined,
  });
  return poster.sort((a, b) => {
    const ad = a.dato.min; const bd = b.dato.min;
    if (ad == null && bd != null) return 1;
    if (ad != null && bd == null) return -1;
    if (ad != null && bd != null && ad !== bd) return ad.localeCompare(bd);
    const ai = Number(a.id.slice(2)); const bi = Number(b.id.slice(2));
    return ai - bi || a.art.localeCompare(b.art);
  });
}

// Forudfyldning af story-editoren fra en hændelses-post (fase3-spec §7.2): klausulen er
// startpunkt; dato og narrativets kilde følger ankeret.
export function storyPrefillFraPost(post: TidslinjePost): {
  tekst: string; haendelseId: number | null;
  dateMin: string | null; dateMax: string | null;
  dateQualifier: string | null; dateRaw: string | null;
  kilder: { sourceId: number; side?: string }[];
} {
  return {
    tekst: post.klausul,
    haendelseId: post.haendelseId ?? null,
    dateMin: post.dato.min, dateMax: post.dato.max,
    dateQualifier: post.dato.qualifier, dateRaw: post.dato.raw,
    kilder: post.sourceId != null
      ? [{ sourceId: post.sourceId, ...(post.side != null ? { side: post.side } : {}) }]
      : [],
  };
}

export type StoryPost = {
  id: number; titel: string | null; tekst: string;
  dato: { min: string | null; max: string | null; qualifier: string | null; raw: string | null };
  status: 'kladde' | 'klar' | 'publiceret' | 'arkiveret';
  publiceretDato: string | null; privat: boolean;
  haendelseId: number | null; factId: number | null; relationId: number | null;
  historicalEventId: number | null;
  kilder: { sourceId: number; side: string | null; sourceTitel?: string }[];
};

export type RawStoryRow = {
  id: number; titel: string | null; tekst: string;
  date_min: string | null; date_max: string | null; date_qualifier: string | null; date_raw: string | null;
  status: StoryPost['status']; publiceret_dato: string | null; privat: boolean | null;
  haendelse_id: number | null; fact_id: number | null; relation_id: number | null;
  historical_event_id: number | null;
  story_kilde: Array<{ id: number; source_id: number; side: string | null;
    source: { titel: string | null; udgave: string | null } | null }> | null;
};

export function mapStories(rows: RawStoryRow[]): StoryPost[] {
  return rows.map((r) => ({
    id: Number(r.id), titel: r.titel, tekst: r.tekst,
    dato: { min: r.date_min, max: r.date_max, qualifier: r.date_qualifier, raw: r.date_raw },
    status: r.status, publiceretDato: r.publiceret_dato, privat: Boolean(r.privat),
    haendelseId: r.haendelse_id == null ? null : Number(r.haendelse_id),
    factId: r.fact_id == null ? null : Number(r.fact_id),
    relationId: r.relation_id == null ? null : Number(r.relation_id),
    historicalEventId: r.historical_event_id == null ? null : Number(r.historical_event_id),
    kilder: [...(r.story_kilde ?? [])].sort((a, b) => a.id - b.id).map((k) => ({
      sourceId: Number(k.source_id), side: k.side,
      sourceTitel: k.source?.titel ?? k.source?.udgave ?? undefined,
    })),
  }));
}

export async function fetchStoriesForPerson(personId: string): Promise<StoryPost[]> {
  if (!personId) return [];
  const { data, error } = await supabase.from('story')
    .select('id,titel,tekst,date_min,date_max,date_qualifier,date_raw,status,publiceret_dato,privat,haendelse_id,fact_id,relation_id,historical_event_id,story_kilde(id,source_id,side,source:source_id(titel,udgave))')
    .eq('subjekt_type', 'person').eq('subjekt_id', Number(personId)).order('id');
  if (error) throw new Error(error.message);
  return mapStories((data ?? []) as unknown as RawStoryRow[]);
}

export async function fetchPubliceredeStories(): Promise<(StoryPost & { subjektId: number })[]> {
  const { data, error } = await supabase.from('story')
    .select('id,subjekt_id,titel,tekst,date_min,date_max,date_qualifier,date_raw,status,publiceret_dato,privat,haendelse_id,fact_id,relation_id,historical_event_id,story_kilde(id,source_id,side,source:source_id(titel,udgave))')
    .eq('subjekt_type', 'person').eq('status', 'publiceret').order('id');
  if (error) throw new Error(error.message);
  return ((data ?? []) as unknown as Array<RawStoryRow & { subjekt_id: number }>).map((row) => ({
    ...mapStories([row])[0], subjektId: Number(row.subjekt_id),
  }));
}

export type SourceRow = { id: number; titel: string | null; udgave: string | null; slags: string | null; aar: number | null };

export async function fetchSources(): Promise<SourceRow[]> {
  const { data, error } = await supabase
    .from('source').select('id,titel,udgave,slags,aar')
    .order('aar', { ascending: false, nullsFirst: false });
  if (error) throw new Error(error.message);
  return (data ?? []) as SourceRow[];
}

// Rå lineage-rækker med deres RIGTIGE numeriske id (til subjekt_id på 'lineage'-narrativer, Slice
// C3) — bevidst IKKE genbrugt fra Følgesvend-modellens aux.linjeList (den bærer kun linje-KODEN
// 'I'/'II'/… som nøgle, ikke lineage.id).
export type LineageRow = { id: number; kode: string; navn: string | null };

export async function fetchLineages(): Promise<LineageRow[]> {
  const { data, error } = await supabase.from('lineage').select('id,kode,navn').order('kode', { ascending: true });
  if (error) throw new Error(error.message);
  return (data ?? []) as LineageRow[];
}

// --- Generiske entitets-lister (simple tabeller) til midter-panelet ---

export type EntityRecord = { id: string; label: string; sub: string; badge: string };

// Trivielt læsbare entiteter (én tabel). Family/majorat/hverv/medie har ikke en simpel
// liste-kilde og returnerer tom (UI viser "kommer"-tilstand) — dedikerede reads er follow-up.
export async function fetchEntityRecords(entity: string): Promise<EntityRecord[]> {
  const sel = async <T>(table: string, cols: string): Promise<T[]> =>
    getAll<T>(() => supabase.from(table).select(cols));
  if (entity === 'estate') {
    const rows = await sel<{ id: number; navn: string | null; slags: string | null }>('estate', 'id,navn,slags');
    return rows.map((r) => ({ id: String(r.id), label: r.navn ?? '(uden navn)', sub: r.slags ?? 'gods', badge: '⌂' }));
  }
  if (entity === 'source') {
    const rows = await sel<{ id: number; titel: string | null; slags: string | null }>('source', 'id,titel,slags');
    return rows.map((r) => ({ id: String(r.id), label: r.titel ?? '(uden titel)', sub: r.slags ?? 'kilde', badge: '§' }));
  }
  if (entity === 'org') {
    const rows = await sel<{ id: number; navn: string | null; slags: string | null }>('organisation', 'id,navn,slags');
    return rows.map((r) => ({ id: String(r.id), label: r.navn ?? '(uden navn)', sub: r.slags ?? 'organisation', badge: '◈' }));
  }
  if (entity === 'arms') {
    const rows = await sel<{ id: number; blasonering: string | null }>('coat_of_arms', 'id,blasonering');
    return rows.map((r) => ({ id: String(r.id), label: (r.blasonering ?? '(uden blasonering)').slice(0, 48), sub: 'våben', badge: '⛨' }));
  }
  if (entity === 'narrative') {
    const rows = await sel<{ id: number; subjekt_type: string | null; tekst: string | null; privat: boolean | null }>(
      'narrative', 'id,subjekt_type,tekst,privat');
    return rows.map((r) => ({ id: String(r.id), label: (r.tekst ?? '(tom)').slice(0, 48),
      sub: (r.subjekt_type ?? '?') + (r.privat ? ' · privat' : ' · offentlig'), badge: '¶' }));
  }
  return [];
}

// --- Slet-preview (relations-advarsel til slet-modalen) ---

export type SletPreview = {
  antalRelationer: number;
  antalFacts: number;
  relationer: { rolle: string; retning: string; modpartId: number }[];
};

export async function fetchSletPreview(personId: string): Promise<SletPreview> {
  const tom: SletPreview = { antalRelationer: 0, antalFacts: 0, relationer: [] };
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

// --- Familie-læsning til person-editor (porteret fra mobil 2C-2b — hold i sync) ---

export type FamiliePartner = { personId: string; navn: string; aar: string; konfidens: string | null; ordinal: number | null };
export type FamilieBarn = { personId: string; navn: string; aar: string; rolle: string; konfidens: string | null; ordinal: number | null };
export type FamilieUnion = { familyId: string; type: string; partnere: FamiliePartner[]; boern: FamilieBarn[] };
export type SomBarn = { familyId: string; rolle: string; konfidens: string | null; foraeldre: { personId: string; navn: string }[] };
export type PersonFamilie = { somPartner: FamilieUnion[]; somBarn: SomBarn[] };
type RawFamRow = { family_id: number; person_id: number; rolle: string; ordinal: number | null; konfidens: string | null };
type RawFamilyMeta = { id: number; type: string | null };
export const BARN_ROLLER = ['barn', 'adopteret_barn', 'plejebarn', 'stedbarn'] as const;

// Beregner ny ordinal-værdi til at flytte ét barn ét skridt op/ned i søskende-visningsrækkefølgen
// (porteret fra mobile/src/data/redaktionRead.ts — hold i sync). "Klem ind"-teknik: sætter KUN
// det flyttede barns ordinal (ét red_set_familie_ordinal-kald), til en værdi der sorterer lige
// før/efter naboen — rører aldrig naboens egen ordinal-værdi. `boern` skal være i NUVÆRENDE
// visningsrækkefølge (som fetchPersonFamilie allerede leverer).
export function nudgeOrdinal(
  boern: { ordinal: number | null }[],
  index: number,
  retning: 'op' | 'ned',
): number | null {
  const effektiv = (i: number) => boern[i].ordinal ?? (i + 1) * 10;
  if (retning === 'op') return index > 0 ? effektiv(index - 1) - 1 : null;
  return index < boern.length - 1 ? effektiv(index + 1) + 1 : null;
}

export function mapFamilieRows(personId: string, families: RawFamilyMeta[], members: RawFamRow[], model: Model | null): PersonFamilie {
  const navnAf = (pid: number) => model?.byId?.[String(pid)]?.name ?? `#${pid}`;
  // Fødsels/dødsår slås op fra samme cache som navnet (model.byId[pid].years, fx "1650–1700",
  // "* 1675") — ingen ekstra query. Tom streng når personen ikke er i model (graceful).
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
    // Bucket ALLE fokus-personens medlemskaber (PK inkl. rolle → flere barn-roller muligt).
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

export async function fetchPersonFamilie(id: string, model: Model | null): Promise<PersonFamilie> {
  const mine = await getAll<{ family_id: number }>(() =>
    supabase.from('family_member').select('family_id').eq('person_id', Number(id)));
  const famIds = Array.from(new Set(mine.map((m) => m.family_id)));
  if (!famIds.length) return { somPartner: [], somBarn: [] };
  const [members, families] = await Promise.all([
    getAll<RawFamRow>(() =>
      supabase.from('family_member').select('family_id,person_id,rolle,ordinal,konfidens').in('family_id', famIds)
        .order('ordinal', { ascending: true, nullsFirst: false }).order('person_id')),
    getAll<RawFamilyMeta>(() => supabase.from('family').select('id,type').in('id', famIds)),
  ]);
  return mapFamilieRows(id, families, members, model);
}

// --- Relationer pr. person (hverv/godser) — navne slås op direkte (ingen Aux i web) ---

export type PersonRelation = { relationId: number; art: 'hverv' | 'gods' | 'event'; objektType: string; objektId: string; navn: string; rolle: string; periode: string };
type RawRelRow = { id: number; objekt_type: string; objekt_id: number; rolle: string | null; periode_raw: string | null };

export async function fetchPersonRelationer(id: string): Promise<PersonRelation[]> {
  const rows = await getAll<RawRelRow>(() =>
    supabase.from('relation').select('id,objekt_type,objekt_id,rolle,periode_raw')
      .eq('subjekt_type', 'person').eq('subjekt_id', Number(id))
      .in('objekt_type', ['organisation', 'estate', 'historical_event']).order('id'));
  const orgIds = rows.filter((r) => r.objekt_type === 'organisation').map((r) => r.objekt_id);
  const estIds = rows.filter((r) => r.objekt_type === 'estate').map((r) => r.objekt_id);
  const { org: orgNavn, estate: estNavn } = await resolveOrgEstateNames(orgIds, estIds);
  return rows.map((r) => {
    const objektId = String(r.objekt_id);
    let art: PersonRelation['art'] = 'event';
    let navn = `Begivenhed #${objektId}`;
    if (r.objekt_type === 'organisation') { art = 'hverv'; navn = orgNavn.get(objektId) || `#${objektId}`; }
    else if (r.objekt_type === 'estate') { art = 'gods'; navn = estNavn.get(objektId) || `#${objektId}`; }
    return { relationId: r.id, art, objektType: r.objekt_type, objektId, navn, rolle: r.rolle ?? '', periode: r.periode_raw ?? '' };
  });
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
  const { data } = await supabase
    .from('relation')
    .select('id,subjekt_id,objekt_id')
    .eq('rolle', 'samme_som')
    .eq('subjekt_type', 'person')
    .eq('objekt_type', 'person')
    .or(`subjekt_id.eq.${Number(personId)},objekt_id.eq.${Number(personId)}`);
  return mapSammeSomLinks(personId, (data ?? []) as never);
}

// --- Medier pr. person, redaktør-scope (mediehåndtering Slice 0g, porteret fra mobile) ---
// Adskilt fra data/media.ts's fetchPersonMedia (den er RLS-gatet til 'klar'+maa_publiceres for
// anon/medlem); redaktionens redaktion_read-politik viser ALLE upload_status, så redaktøren ser
// egne uploads (også 'kladde') uanset rettigheds-/publikationsstatus. Navngivet forskelligt fra
// media.ts's samme-formåls-funktion for at undgå importforveksling i Redaktion.tsx.
// Fase 1: redaktionen beholder også upload_status='fjernet', så mediet kan genoprettes fra filsiden.
export type PersonMedia = {
  id: string; relationId: string; slags: string; titel: string | null; storagePath: string | null;
  kunstner: string | null; datering: string | null; rettighederStatus: string;
  mimeType: string | null; byteSize: number | null; bredde: number | null; hoejde: number | null;
  originalFilnavn: string | null; uploadStatus: string; maaPubliceres: boolean; createdAt: string | null;
  url: string | null; thumbUrl: string | null;
};
type RawPersonMediaRow = { id: number | string; slags: string | null; titel: string | null; kunstner: string | null;
  datering: string | null; storage_path: string | null; upload_status: string | null;
  maa_publiceres: boolean | null; rettigheder_status: string | null; mime_type: string | null;
  byte_size: number | null; bredde: number | null; hoejde: number | null; original_filnavn: string | null;
  created_at?: string | null };

// signed/relByMediaId/thumbPathByMediaId er valgfri (default tomme Maps) så testen kan kalde ren,
// netværksfri — kun fetch-funktionerne nedenfor sender reelt udfyldte Maps (signeret ét sted,
// ligesom media.ts's loadMediaItems, i stedet for at kalderen holder separat state + effekt).
// thumbUrl (billedstørrelser 2026-07-05, Slice B3): falder tilbage til url hvis ingen thumb-variant
// findes (rækker fra før Slice B, eller ren pre-variant-fejl).
export function mapPersonMediaRows(
  rows: RawPersonMediaRow[],
  signed: Map<string, string> = new Map(),
  relByMediaId: Map<string, string> = new Map(),
  thumbPathByMediaId: Map<string, string> = new Map(),
): PersonMedia[] {
  return rows.map((m) => {
      const url = m.storage_path ? signed.get(m.storage_path) ?? null : null;
      const thumbPath = thumbPathByMediaId.get(String(m.id));
      return {
        id: String(m.id),
        relationId: relByMediaId.get(String(m.id)) ?? '',
        slags: m.slags ?? '',
        titel: m.titel,
        storagePath: m.storage_path,
        kunstner: m.kunstner,
        datering: m.datering,
        rettighederStatus: m.rettigheder_status ?? 'ukendt',
        mimeType: m.mime_type,
        byteSize: m.byte_size,
        bredde: m.bredde,
        hoejde: m.hoejde,
        originalFilnavn: m.original_filnavn,
        uploadStatus: m.upload_status ?? 'kladde',
        maaPubliceres: Boolean(m.maa_publiceres),
        createdAt: m.created_at ?? null,
        url,
        thumbUrl: (thumbPath ? signed.get(thumbPath) : null) ?? url,
      };
    });
}

// Fælles hale: rel-par (media-id + relation-id) → signede/mappede PersonMedia. Retningen af selve
// relations-forespørgslen (person→media vs. media→objekt) afgøres af kalderne nedenfor.
async function mediaFromRelPairs(pairs: { mediaId: number; relationId: number }[]): Promise<PersonMedia[]> {
  if (!pairs.length) return [];
  const relByMediaId = new Map(pairs.map((p) => [String(p.mediaId), String(p.relationId)]));
  const mediaIds = pairs.map((p) => p.mediaId);
  const [rows, thumbPathByMediaId] = await Promise.all([
    getAll<RawPersonMediaRow>(() =>
      supabase.from('media').select('id,slags,titel,kunstner,datering,storage_path,upload_status,maa_publiceres,rettigheder_status,mime_type,byte_size,bredde,hoejde,original_filnavn,created_at').in('id', mediaIds)),
    fetchThumbPathByMediaId(mediaIds),
  ]);
  const signed = await signPaths([
    ...rows.map((r) => r.storage_path ?? ''),
    ...thumbPathByMediaId.values(),
  ].filter(Boolean));
  return mapPersonMediaRows(rows, signed, relByMediaId, thumbPathByMediaId);
}

export async function fetchRedPersonMedia(id: string): Promise<PersonMedia[]> {
  const rels = await getAll<{ id: number; objekt_id: number }>(() =>
    supabase.from('relation').select('id,objekt_id')
      .eq('subjekt_type', 'person').eq('subjekt_id', Number(id))
      .eq('objekt_type', 'media').eq('rolle', 'afbildet'));
  return mediaFromRelPairs(rels.map((r) => ({ mediaId: r.objekt_id, relationId: r.id })));
}

// Objekt-foto (gods/våben m.fl.): relationen går OMVENDT af person-varianten — media er subjekt,
// objektet (estate/coat_of_arms) er objekt (jf. red_upload_media's p_objekt_type-gren).
export async function fetchRedObjectMedia(objektType: string, objektId: string): Promise<PersonMedia[]> {
  const rels = await getAll<{ id: number; subjekt_id: number }>(() =>
    supabase.from('relation').select('id,subjekt_id')
      .eq('subjekt_type', 'media')
      .eq('objekt_type', objektType).eq('objekt_id', Number(objektId))
      .eq('rolle', 'afbildet'));
  return mediaFromRelPairs(rels.map((r) => ({ mediaId: r.subjekt_id, relationId: r.id })));
}

// --- Tværgående mediebibliotek + "bruges på" (mediehåndtering fase 2) ---

export type MedieKoe = 'rettigheder' | 'loese' | 'strandede' | 'papirkurv' | 'dubletter';

const TIME = 60 * 60 * 1000;
const DAG = 24 * TIME;
const UGE = 7 * DAG;
const MAANED = 30 * DAG;

export function formatMedieAlder(createdAt: string | null, nu: Date = new Date()): string {
  if (!createdAt) return 'ukendt alder';
  const oprettet = Date.parse(createdAt);
  const nuTid = nu.getTime();
  if (!Number.isFinite(oprettet) || !Number.isFinite(nuTid) || oprettet > nuTid) return 'ukendt alder';
  const alder = nuTid - oprettet;
  if (alder < TIME) return 'under 1 time — muligvis i gang';
  if (alder < DAG) {
    const timer = Math.floor(alder / TIME);
    return `${timer} ${timer === 1 ? 'time' : 'timer'}`;
  }
  if (alder < UGE) {
    const dage = Math.floor(alder / DAG);
    return `${dage} ${dage === 1 ? 'dag' : 'dage'}`;
  }
  if (alder < MAANED) {
    const uger = Math.floor(alder / UGE);
    return `${uger} ${uger === 1 ? 'uge' : 'uger'}`;
  }
  const maaneder = Math.floor(alder / MAANED);
  return `${maaneder} ${maaneder === 1 ? 'måned' : 'måneder'}`;
}

export type MedieDubletGrundlag = {
  id: number | string;
  upload_status?: string | null;
  byte_size?: number | null;
  bredde?: number | null;
  hoejde?: number | null;
};

export function findMedieDubletKandidatIds(mediaRows: MedieDubletGrundlag[]): ReadonlySet<string> {
  const idsByNoegle = new Map<string, Set<string>>();
  for (const media of mediaRows) {
    if (media.upload_status !== 'klar'
      || media.byte_size == null || media.bredde == null || media.hoejde == null) continue;
    // Fase 3 bruger empirisk den planlagte 3-feltsnøgle. mime_type medtages ikke: testen
    // bevarer et signal på tværs af containerformat, mens køen fortsat kun er en mistanke.
    const noegle = JSON.stringify([media.byte_size, media.bredde, media.hoejde]);
    const ids = idsByNoegle.get(noegle) ?? new Set<string>();
    ids.add(String(media.id));
    idsByNoegle.set(noegle, ids);
  }
  const kandidater = new Set<string>();
  for (const ids of idsByNoegle.values()) {
    if (ids.size > 1) ids.forEach((id) => kandidater.add(id));
  }
  return kandidater;
}

export function klassificerMedie(
  m: { uploadStatus: string; rettighederStatus: string; maaPubliceres: boolean },
  antalAfbildet: number,
  antalMentions: number,
  harDubletKandidat: boolean,
): MedieKoe[] {
  const koeer: MedieKoe[] = [];
  if (m.uploadStatus === 'klar' && (m.rettighederStatus === 'ukendt' || !m.maaPubliceres)) {
    koeer.push('rettigheder');
  }
  if (m.uploadStatus === 'klar' && antalAfbildet === 0 && antalMentions === 0) {
    koeer.push('loese');
  }
  if (m.uploadStatus === 'kladde' || m.uploadStatus === 'fejlet') koeer.push('strandede');
  if (m.uploadStatus === 'fjernet') koeer.push('papirkurv');
  if (m.uploadStatus === 'klar' && harDubletKandidat) koeer.push('dubletter');
  return koeer;
}

export type MediaBibliotekPost = Omit<PersonMedia, 'relationId'> & {
  antalAfbildet: number;
  antalMentions: number;
  koeer: MedieKoe[];
};

type RawPersonMediaRelation = { subjekt_id: number | string; objekt_id: number | string };
type RawObjectMediaRelation = { subjekt_id: number | string; objekt_type: string; objekt_id: number | string };
type RawMediaMentionCount = { maal_id: number | string };

// Query-specs er eksporterede, så bigint-grænsen kan testes uden netværk. Castet ligger i selve
// PostgREST SELECT'en og sker dermed før JSON-dekodning; filtre nedenfor bruger fortsat rå kolonner.
export function mediaBibliotekQuerySpecs() {
  return {
    media: { table: 'media', select: 'id::text,slags,titel,kunstner,datering,storage_path,upload_status,maa_publiceres,rettigheder_status,mime_type,byte_size,bredde,hoejde,original_filnavn,created_at' },
    personRelationer: { table: 'relation', select: 'subjekt_id::text,objekt_id::text' },
    objektRelationer: { table: 'relation', select: 'subjekt_id::text,objekt_type,objekt_id::text' },
    mentions: { table: 'text_mention', select: 'maal_id::text' },
  } as const;
}

function countById(rows: Array<number | string>): Map<string, number> {
  const out = new Map<string, number>();
  for (const id of rows) {
    const key = String(id);
    out.set(key, (out.get(key) ?? 0) + 1);
  }
  return out;
}

export function mapMediaBibliotekRows(
  mediaRows: RawPersonMediaRow[],
  personRelationer: RawPersonMediaRelation[],
  objektRelationer: RawObjectMediaRelation[],
  mentions: RawMediaMentionCount[],
  signed: Map<string, string> = new Map(),
  thumbPathByMediaId: Map<string, string> = new Map(),
): MediaBibliotekPost[] {
  const afbildetByMediaId = new Map<string, Set<string>>();
  const tilfoej = (mediaId: number | string, target: string) => {
    const targets = afbildetByMediaId.get(String(mediaId)) ?? new Set<string>();
    targets.add(target); afbildetByMediaId.set(String(mediaId), targets);
  };
  personRelationer.forEach((r) => tilfoej(r.objekt_id, `person:${r.subjekt_id}`));
  objektRelationer.forEach((r) => tilfoej(r.subjekt_id, `${r.objekt_type}:${r.objekt_id}`));
  const mentionCount = countById(mentions.map((m) => m.maal_id));
  const dubletKandidatIds = findMedieDubletKandidatIds(mediaRows);

  return mapPersonMediaRows(mediaRows, signed, new Map(), thumbPathByMediaId).map(({ relationId: _relationId, ...media }) => {
    const antalAfbildet = afbildetByMediaId.get(media.id)?.size ?? 0;
    const antalMentions = mentionCount.get(media.id) ?? 0;
    return {
      ...media,
      antalAfbildet,
      antalMentions,
      koeer: klassificerMedie(media, antalAfbildet, antalMentions, dubletKandidatIds.has(media.id)),
    };
  });
}

export async function fetchMediaBibliotek(): Promise<MediaBibliotekPost[]> {
  // Ingen upload_status-filter her: kladder, fejl og fjernede rækker er selve grundlaget for
  // bibliotekets strandede-/papirkurvskøer. RLS afgør fortsat, hvem der må se dem.
  const specs = mediaBibliotekQuerySpecs();
  const [mediaRows, personRelationer, objektRelationer, mentions] = await Promise.all([
    getAll<RawPersonMediaRow>(() =>
      supabase.from(specs.media.table).select(specs.media.select)),
    getAll<RawPersonMediaRelation>(() =>
      supabase.from(specs.personRelationer.table).select(specs.personRelationer.select).eq('subjekt_type', 'person').eq('objekt_type', 'media').eq('rolle', 'afbildet')),
    getAll<RawObjectMediaRelation>(() =>
      supabase.from(specs.objektRelationer.table).select(specs.objektRelationer.select).eq('subjekt_type', 'media').in('objekt_type', ['estate','coat_of_arms','lineage']).eq('rolle', 'afbildet')),
    getAll<RawMediaMentionCount>(() =>
      supabase.from(specs.mentions.table).select(specs.mentions.select).eq('maal_type', 'media')),
  ]);
  const mediaIds = mediaRows.map((m) => m.id);
  const thumbPathByMediaId = await fetchThumbPathByMediaId(mediaIds);
  const signed = await signPaths([
    ...mediaRows.map((m) => m.storage_path ?? ''),
    ...thumbPathByMediaId.values(),
  ].filter(Boolean));
  return mapMediaBibliotekRows(mediaRows, personRelationer, objektRelationer, mentions, signed, thumbPathByMediaId);
}

export type MediaAnvendelse = {
  afbildet: { type: string; id: string; navn: string; relationId: string }[];
  mentions: { kildeType: string; kildeId: string; subjektNavn: string }[];
};

type RawMediaPersonAnvendelse = { id: number | string; subjekt_id: number | string };
type RawMediaObjektAnvendelse = { id: number | string; objekt_type: string; objekt_id: number | string };
type RawMediaMention = { kilde_type: string; kilde_id: number | string };
type RawNarrativeSubject = { id: number | string; subjekt_type: string; subjekt_id: number | string };

export function mediaAnvendelseQuerySpecs() {
  return {
    personRelationer: { table: 'relation', select: 'id::text,subjekt_id::text' },
    objektRelationer: { table: 'relation', select: 'id::text,objekt_type,objekt_id::text' },
    mentions: { table: 'text_mention', select: 'kilde_type,kilde_id::text' },
    narrativer: { table: 'narrative', select: 'id::text,subjekt_type,subjekt_id::text' },
  } as const;
}

const subjectKey = (type: string, id: number | string) => `${type}:${id}`;
const fallbackSubjectName = (type: string, id: number | string) => `${type} #${id}`;

export function mapMediaAnvendelse(rows: {
  personRelationer: RawMediaPersonAnvendelse[];
  objektRelationer: RawMediaObjektAnvendelse[];
  mentions: RawMediaMention[];
  narrativer: RawNarrativeSubject[];
  navneBySubjekt: Map<string, string>;
}): MediaAnvendelse {
  const narrativById = new Map(rows.narrativer.map((n) => [String(n.id), n]));
  return {
    afbildet: [
      ...rows.personRelationer.map((r) => ({
        type: 'person',
        id: String(r.subjekt_id),
        navn: rows.navneBySubjekt.get(subjectKey('person', r.subjekt_id)) ?? fallbackSubjectName('person', r.subjekt_id),
        relationId: String(r.id),
      })),
      ...rows.objektRelationer.map((r) => ({
        type: r.objekt_type,
        id: String(r.objekt_id),
        navn: rows.navneBySubjekt.get(subjectKey(r.objekt_type, r.objekt_id)) ?? fallbackSubjectName(r.objekt_type, r.objekt_id),
        relationId: String(r.id),
      })),
    ],
    mentions: rows.mentions.map((m) => {
      const narrativ = m.kilde_type === 'narrative' ? narrativById.get(String(m.kilde_id)) : undefined;
      return {
        kildeType: m.kilde_type,
        kildeId: String(m.kilde_id),
        subjektNavn: narrativ
          ? rows.navneBySubjekt.get(subjectKey(narrativ.subjekt_type, narrativ.subjekt_id))
            ?? fallbackSubjectName(narrativ.subjekt_type, narrativ.subjekt_id)
          : '(ukendt subjekt)',
      };
    }),
  };
}

function parseDatabaseId(value: string): number | string | null {
  const trimmed = value.trim();
  if (!/^[1-9][0-9]*$/.test(trimmed) || trimmed.length > 19 || (trimmed.length === 19 && trimmed > '9223372036854775807')) return null;
  const id = Number(trimmed);
  return Number.isSafeInteger(id) ? id : trimmed;
}

async function fetchMediaSubjectNames(subjects: { type: string; id: number | string }[]): Promise<Map<string, string>> {
  const idsByType = new Map<string, Set<number | string>>();
  for (const subject of subjects) {
    const ids = idsByType.get(subject.type) ?? new Set<number | string>();
    ids.add(subject.id);
    idsByType.set(subject.type, ids);
  }
  const out = new Map<string, string>();
  await Promise.all([...idsByType].map(async ([type, idSet]) => {
    const ids = [...idSet];
    if (!ids.length) return;
    if (type === 'person') {
      const rows = await getAll<{ id: number | string; visning_navn: string | null }>(() =>
        supabase.from('person').select('id::text,visning_navn').in('id', ids));
      rows.forEach((r) => out.set(subjectKey(type, r.id), r.visning_navn ?? fallbackSubjectName(type, r.id)));
    } else if (type === 'estate') {
      const rows = await getAll<{ id: number | string; navn: string | null }>(() =>
        supabase.from('estate').select('id::text,navn').in('id', ids));
      rows.forEach((r) => out.set(subjectKey(type, r.id), r.navn ?? fallbackSubjectName(type, r.id)));
    } else if (type === 'coat_of_arms') {
      const rows = await getAll<{ id: number | string; blasonering: string | null }>(() =>
        supabase.from('coat_of_arms').select('id::text,blasonering').in('id', ids));
      rows.forEach((r) => out.set(subjectKey(type, r.id), r.blasonering ?? fallbackSubjectName(type, r.id)));
    } else if (type === 'lineage') {
      const rows = await getAll<{ id: number | string; navn: string | null }>(() =>
        supabase.from('lineage').select('id::text,navn').in('id', ids));
      rows.forEach((r) => out.set(subjectKey(type, r.id), r.navn ?? fallbackSubjectName(type, r.id)));
    } else if (type === 'slaegt') {
      ids.forEach((id) => out.set(subjectKey(type, id), 'Slægten (generelt)'));
    }
  }));
  return out;
}

export async function fetchMediaAnvendelse(mediaId: string): Promise<MediaAnvendelse> {
  const id = parseDatabaseId(mediaId);
  if (id == null) return { afbildet: [], mentions: [] };
  const specs = mediaAnvendelseQuerySpecs();
  const [personRelationer, objektRelationer, mentions] = await Promise.all([
    getAll<RawMediaPersonAnvendelse>(() =>
      supabase.from(specs.personRelationer.table).select(specs.personRelationer.select)
        .eq('subjekt_type', 'person').eq('objekt_type', 'media').eq('objekt_id', id).eq('rolle', 'afbildet').order('id')),
    getAll<RawMediaObjektAnvendelse>(() =>
      supabase.from(specs.objektRelationer.table).select(specs.objektRelationer.select)
        .eq('subjekt_type', 'media').eq('subjekt_id', id).eq('rolle', 'afbildet').order('id')),
    getAll<RawMediaMention>(() =>
      supabase.from(specs.mentions.table).select(specs.mentions.select)
        .eq('maal_type', 'media').eq('maal_id', id).order('kilde_type').order('kilde_id')),
  ]);
  const narrativIds = [...new Set(mentions.filter((m) => m.kilde_type === 'narrative').map((m) => m.kilde_id))];
  const narrativer = narrativIds.length
    ? await getAll<RawNarrativeSubject>(() =>
      supabase.from(specs.narrativer.table).select(specs.narrativer.select).in('id', narrativIds))
    : [];
  const navneBySubjekt = await fetchMediaSubjectNames([
    ...personRelationer.map((r) => ({ type: 'person', id: r.subjekt_id })),
    ...objektRelationer.map((r) => ({ type: r.objekt_type, id: r.objekt_id })),
    ...narrativer.map((n) => ({ type: n.subjekt_type, id: n.subjekt_id })),
  ]);
  return mapMediaAnvendelse({ personRelationer, objektRelationer, mentions, narrativer, navneBySubjekt });
}

// ---- Tværudgave-matching: MatchFrame-input fra DB (Problem 3 §11) ----
// Tynde supabase-fetches; de rene mappere (buildMatchPersoner/parseIkkeSammeSomPar) bor i
// @daa/core (samme delt-logik-split som matcher-kernen). Re-eksportér RedMatchPerson for forbrugere.
export type { RedMatchPerson };

/** Hent MatchFrame-input for hele redaktions-datasættet (tynd; @daa/core-mappere gør arbejdet).
 *  NB (skala): conclusion/assertion hentes for ALLE fact-typer og filtreres klient-side til
 *  fødsel/død, fordi et batch-`.in('target_id', factIds)`-filter sprænger PostgREST's URL-længde
 *  ved ~900 personer. Rigtig fix ved skala: et server-side view (fact→conclusion→assertion → ét
 *  fødsels-/døds-interval pr. person). Udskudt — PoC-volumen er håndterbar. */
export async function fetchMatchPersoner(): Promise<RedMatchPerson[]> {
  const [persons, facts, concs, assertions, extIds] = await Promise.all([
    getAll<MatchPersonRow>(() => supabase.from('person').select('id,visning_navn,koen,staged')),
    getAll<MatchFactRow>(() => supabase.from('fact').select('id,subjekt_id,faktatype').eq('subjekt_type', 'person').in('faktatype', ['fødsel', 'død'])),
    getAll<MatchConcRow>(() => supabase.from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact').eq('status', 'afklaret')),
    getAll<MatchAssertRow>(() => supabase.from('assertion').select('id,date_min,date_max').eq('target_type', 'fact')),
    getAll<MatchExtIdRow>(() => supabase.from('person_external_id').select('person_id,source_id')),
  ]);
  return buildMatchPersoner(persons, facts, concs, assertions, extIds);
}

/** Hent eksisterende ikke_samme_som-afvisninger (person→person). */
export async function fetchIkkeSammeSomPar(): Promise<{ aId: string; bId: string }[]> {
  const rows = await getAll<{ subjekt_id: number; objekt_id: number }>(() =>
    supabase.from('relation').select('subjekt_id,objekt_id')
      .eq('rolle', 'ikke_samme_som').eq('subjekt_type', 'person').eq('objekt_type', 'person'));
  return parseIkkeSammeSomPar(rows);
}

/** Hent alle samme_som-links (person→person) — til arbejdslistens "afklaret"-markering. */
export async function fetchSammeSomPar(): Promise<{ aId: string; bId: string }[]> {
  const rows = await getAll<{ subjekt_id: number; objekt_id: number }>(() =>
    supabase.from('relation').select('subjekt_id,objekt_id')
      .eq('rolle', 'samme_som').eq('subjekt_type', 'person').eq('objekt_type', 'person'));
  return parseIkkeSammeSomPar(rows); // samme (subjekt,objekt)→(aId,bId)-form
}

/** Hent hele familie-grafen (union + forælder→barn) til den rådgivende samme_som-fold-preview
 *  (§7.18) — bruges sammen med fetchMatchPersoner til at bygge et Db der kan køres gennem
 *  collapseSameAs/previewSammeSom i redaktionen. Bevidst UDEN far-før-mor-ordinal-sortering
 *  (buildFamilyGraph, kommentar deri) — rækkefølgen er uden betydning for karantæne-tjek. */
export async function fetchFamilyGraph(): Promise<{ unions: Union[]; parentChild: ParentChild[] }> {
  const members = await getAll<RawFamilyMember>(() =>
    supabase.from('family_member').select('family_id,person_id,rolle'));
  return buildFamilyGraph(members);
}
