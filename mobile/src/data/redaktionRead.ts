// Evidens-read-lag til person-editoren. Modellen er polymorf (assertion/conclusion peger på
// fact via target_type/target_id UDEN rigtig FK), så vi henter N flade queries og joiner i
// klienten. citation→source HAR FK og nestes (spec §3). Ren joinEvidence er testbar uden net.
import { supabase } from '../lib/supabase';
import { parseYear, fmtYears, getAll, buildMatchPersoner, parseIkkeSammeSomPar } from '@daa/core';
import type { RedMatchPerson, MatchPersonRow, MatchFactRow, MatchConcRow, MatchAssertRow, MatchExtIdRow } from '@daa/core';
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

// "Forældre ukendt"-markering (docs/reviews/25): den aktuelle afklarede markering på en person,
// eller null hvis umarkeret. factId bruges til fjern (tilbagetræk hele fakta-slottet). Spejler web/src/data/redaktionRead.ts.
export type ForaeldreUkendtMarkering = { factId: number; assertionId: number; grade: string; kilde: string | null };

export async function fetchForaeldreUkendtMarkering(personId: string): Promise<ForaeldreUkendtMarkering | null> {
  if (!supabase || !personId) return null;
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
// Redaktion-only sti VED SIDEN AF den offentlige familie-læsning (load.ts rører IKKE slottet —
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
  const sb = supabase;
  if (!sb || !personId) return null;
  const pid = Number(personId);
  const { data: facts } = await sb.from('fact').select('id')
    .eq('subjekt_type', 'person').eq('subjekt_id', pid).eq('faktatype', 'forældrefamilie');
  const factId = (facts ?? [])[0]?.id;
  if (factId == null) return null;
  const { data: assertions } = await sb.from('assertion').select('id,objekt_id')
    .eq('target_type', 'fact').eq('target_id', factId).eq('objekt_type', 'family');
  const aList = (assertions ?? []) as RawSlotAssert[];
  const aids = aList.map((a) => a.id);
  const famIds = aList.map((a) => a.objekt_id).filter((x): x is number => x != null);
  const [citRes, concRes, partRes] = await Promise.all([
    aids.length ? sb.from('citation').select('assertion_id,side,citat_tekst,source(udgave,titel)').in('assertion_id', aids).order('id') : Promise.resolve({ data: [] as unknown[] }),
    sb.from('conclusion').select('valgt_assertion_id,status').eq('target_type', 'fact').eq('target_id', factId).maybeSingle(),
    famIds.length ? sb.from('family_member').select('family_id,person_id,person(visning_navn)').in('family_id', famIds).eq('rolle', 'partner') : Promise.resolve({ data: [] as unknown[] }),
  ]);
  const flatPartners: RawFamPartner[] = ((partRes.data ?? []) as { family_id: number; person_id: number; person: { visning_navn: string | null } | null }[])
    .map((p) => ({ family_id: p.family_id, person_id: p.person_id, visning_navn: p.person?.visning_navn ?? null }));
  return buildForaeldreSlot(Number(factId), aList, (citRes.data ?? []) as RawSlotCit[], (concRes.data ?? null) as RawSlotConc | null, flatPartners);
}

// En persons EGEN fødselsfamilie + kildeudgave — bruges til §6 trin (a): importér en samme_som-
// linket persons (anden udgaves) forældre som en rival-påstand på den kanoniske person.
export type BarnFamilie = { familyId: number; foraeldre: ForaeldreForaelder[]; sourceId: number | null; udgave: string | null };

export async function fetchBarnFamilie(personId: string): Promise<BarnFamilie | null> {
  const sb = supabase;
  if (!sb || !personId) return null;
  const pid = Number(personId);
  const { data: bm } = await sb.from('family_member').select('family_id').eq('person_id', pid).eq('rolle', 'barn').maybeSingle();
  const familyId = (bm as { family_id: number } | null)?.family_id;
  if (familyId == null) return null;
  const [partRes, extRes] = await Promise.all([
    sb.from('family_member').select('person_id,person(visning_navn)').eq('family_id', familyId).eq('rolle', 'partner'),
    sb.from('person_external_id').select('source_id,source(udgave,titel)').eq('person_id', pid).order('source_id').limit(1).maybeSingle(),
  ]);
  const foraeldre: ForaeldreForaelder[] = ((partRes.data ?? []) as unknown as { person_id: number; person: { visning_navn: string | null } | null }[])
    .map((p) => ({ personId: p.person_id, navn: p.person?.visning_navn ?? '(ukendt)' }));
  const ext = extRes.data as unknown as { source_id: number | null; source: { udgave: string | null; titel: string | null } | null } | null;
  return { familyId, foraeldre, sourceId: ext?.source_id ?? null, udgave: ext?.source?.udgave ?? ext?.source?.titel ?? null };
}

export type ForaeldreKonflikt = { personId: number; factId: number; antalFamilier: number; antalPaastande: number; status: string | null; navn: string | null };

export async function fetchForaeldreKonflikter(): Promise<ForaeldreKonflikt[]> {
  const sb = supabase;
  if (!sb) return [];
  // Kast fejl frem for tavst [] (review 30): discovery-fladen må ikke maskere en brudt view/RLS.
  const { data, error } = await sb.from('red_foraeldre_konflikt').select('person_id,fact_id,antal_familier,antal_paastande,status');
  if (error) throw error;
  const rows = (data ?? []) as { person_id: number; fact_id: number; antal_familier: number; antal_paastande: number; status: string | null }[];
  if (!rows.length) return [];
  const { data: persons } = await sb.from('person').select('id,visning_navn').in('id', rows.map((r) => r.person_id));
  const navnById = new Map(((persons ?? []) as { id: number; visning_navn: string | null }[]).map((p) => [p.id, p.visning_navn]));
  return rows.map((r) => ({ personId: r.person_id, factId: r.fact_id, antalFamilier: r.antal_familier,
    antalPaastande: r.antal_paastande, status: r.status, navn: navnById.get(r.person_id) ?? null }));
}

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

// --- Narrativ-læsning: ALLE udgaver pr. subjekt (billeder-i-narrativer 2026-07-05, Slice C3) ---
// Generaliseret fra person-only enkelt-række (Codex 2B #1: prefill-kilde == skrive-mål) til ALLE
// udgaver af ethvert subjekt — spejler web's redaktionRead.ts (fetchNarrativer/mapNarrativer),
// så person-editorens udgave-faner og den nye slægts/linje-editor deler ét read-lag.

// Generel slægtsbeskrivelse: subjekt_type='slaegt' har INGEN bagvedliggende tabel — subjekt_id er
// en FAST, delt sentinel-konstant (ikke en fremmednøgle til noget), nødvendig fordi
// narrative.subjekt_id er NOT NULL. Kanonisk ét sted, spejler web's redaktionRead.ts.
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

export async function fetchNarrativer(subjektType: string, subjektId: number): Promise<PersonNarrativ[]> {
  if (!supabase) return [];
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
  if (!personId || !supabase) return [];
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
  if (!personId || !supabase) return [];
  const { data, error } = await supabase.from('story')
    .select('id,titel,tekst,date_min,date_max,date_qualifier,date_raw,status,publiceret_dato,privat,haendelse_id,fact_id,relation_id,historical_event_id,story_kilde(id,source_id,side,source:source_id(titel,udgave))')
    .eq('subjekt_type', 'person').eq('subjekt_id', Number(personId)).order('id');
  if (error) throw new Error(error.message);
  return mapStories((data ?? []) as unknown as RawStoryRow[]);
}

export type SourceRow = { id: number; titel: string | null; udgave: string | null; slags: string | null; aar: number | null };

export async function fetchSources(): Promise<SourceRow[]> {
  if (!supabase) return [];
  const { data, error } = await supabase
    .from('source').select('id,titel,udgave,slags,aar')
    .order('aar', { ascending: false, nullsFirst: false });
  if (error) throw new Error(error.message);
  return (data ?? []) as SourceRow[];
}

// Rå lineage-rækker med deres RIGTIGE numeriske id (til subjekt_id på 'lineage'-narrativer) —
// bevidst IKKE genbrugt fra redaktionAux's linjeList (den bærer kun linje-KODEN 'I'/'II'/… som
// nøgle, ikke lineage.id).
export type LineageRow = { id: number; kode: string; navn: string | null };

export async function fetchLineages(): Promise<LineageRow[]> {
  if (!supabase) return [];
  const { data, error } = await supabase.from('lineage').select('id,kode,navn').order('kode', { ascending: true });
  if (error) throw new Error(error.message);
  return (data ?? []) as LineageRow[];
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
// Fase 1: redaktionen beholder også upload_status='fjernet', så filsiden kan genoprette mediet.
export type PersonMedia = {
  id: string; relationId: string; slags: string; titel: string | null; storagePath: string | null;
  kunstner: string | null; datering: string | null; rettighederStatus: string;
  mimeType: string | null; byteSize: number | null; bredde: number | null; hoejde: number | null;
  originalFilnavn: string | null; uploadStatus: string; maaPubliceres: boolean; thumbStoragePath: string | null;
};
type RawPersonMediaRow = { id: number; slags: string | null; titel: string | null; kunstner: string | null;
  datering: string | null; storage_path: string | null; upload_status: string | null;
  maa_publiceres: boolean | null; rettigheder_status: string | null; mime_type: string | null;
  byte_size: number | null; bredde: number | null; hoejde: number | null; original_filnavn: string | null };

// thumbPathByMediaId (billedstørrelser 2026-07-05, Slice B3) er valgfri (default tom Map) så testen
// kan kalde ren, netværksfri — kun mediaFromRelPairs nedenfor sender reelt en udfyldt Map.
export function mapPersonMediaRows(
  rows: RawPersonMediaRow[],
  relByMediaId: Map<string, string> = new Map(),
  thumbPathByMediaId: Map<string, string> = new Map(),
): PersonMedia[] {
  return rows.map((m) => ({
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
      thumbStoragePath: thumbPathByMediaId.get(String(m.id)) ?? null,
    }));
}

export type MedieKoe = 'rettigheder' | 'loese' | 'strandede' | 'papirkurv';

export function klassificerMedie(
  m: { uploadStatus: string; rettighederStatus: string; maaPubliceres: boolean },
  antalAfbildet: number,
  antalMentions: number,
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
  return koeer;
}

type RawMediaRelationRow = {
  id?: number;
  subjekt_type: string;
  subjekt_id: number;
  objekt_type: string;
  objekt_id: number;
  rolle: string | null;
};
type RawMediaMentionRow = {
  kilde_type: string;
  kilde_id: number;
  maal_type: string;
  maal_id: number;
};
type RawMediaNarrativeRow = { id: number; subjekt_type: string; subjekt_id: number };

export type MediaBibliotekPost = Omit<PersonMedia, 'relationId'> & {
  antalAfbildet: number;
  antalMentions: number;
  koeer: MedieKoe[];
};

export function mapMediaBibliotekRows(
  mediaRows: RawPersonMediaRow[],
  relationRows: RawMediaRelationRow[],
  mentionRows: RawMediaMentionRow[],
  thumbPathByMediaId: Map<string, string> = new Map(),
): MediaBibliotekPost[] {
  const afbildetByMediaId = new Map<string, Set<string>>();
  for (const r of relationRows) {
    if (r.rolle !== 'afbildet') continue;
    const pair = r.subjekt_type === 'person' && r.objekt_type === 'media'
      ? { mediaId: String(r.objekt_id), target: `person:${r.subjekt_id}` }
      : r.subjekt_type === 'media' && ['estate','coat_of_arms','lineage'].includes(r.objekt_type)
        ? { mediaId: String(r.subjekt_id), target: `${r.objekt_type}:${r.objekt_id}` }
        : null;
    if (pair) {
      const targets = afbildetByMediaId.get(pair.mediaId) ?? new Set<string>();
      targets.add(pair.target);
      afbildetByMediaId.set(pair.mediaId, targets);
    }
  }
  const antalMentionsById = new Map<string, number>();
  for (const m of mentionRows) {
    if (m.maal_type !== 'media') continue;
    const mediaId = String(m.maal_id);
    antalMentionsById.set(mediaId, (antalMentionsById.get(mediaId) ?? 0) + 1);
  }
  return mapPersonMediaRows(mediaRows, new Map(), thumbPathByMediaId).map((media) => {
    const { relationId: _relationId, ...udenRelation } = media;
    const antalAfbildet = afbildetByMediaId.get(media.id)?.size ?? 0;
    const antalMentions = antalMentionsById.get(media.id) ?? 0;
    return {
      ...udenRelation,
      antalAfbildet,
      antalMentions,
      koeer: klassificerMedie(media, antalAfbildet, antalMentions),
    };
  });
}

export async function fetchMediaBibliotek(): Promise<MediaBibliotekPost[]> {
  if (!supabase) return [];
  const sb = supabase;
  const [mediaRows, personRelationer, objektRelationer, mentions] = await Promise.all([
    getAll<RawPersonMediaRow>(() =>
      sb.from('media').select('id,slags,titel,kunstner,datering,storage_path,upload_status,maa_publiceres,rettigheder_status,mime_type,byte_size,bredde,hoejde,original_filnavn')),
    getAll<RawMediaRelationRow>(() =>
      sb.from('relation').select('subjekt_type,subjekt_id,objekt_type,objekt_id,rolle')
        .eq('subjekt_type', 'person').eq('objekt_type', 'media').eq('rolle', 'afbildet')),
    getAll<RawMediaRelationRow>(() =>
      sb.from('relation').select('subjekt_type,subjekt_id,objekt_type,objekt_id,rolle')
        .eq('subjekt_type', 'media').in('objekt_type', ['estate','coat_of_arms','lineage']).eq('rolle', 'afbildet')),
    getAll<RawMediaMentionRow>(() =>
      sb.from('text_mention').select('kilde_type,kilde_id,maal_type,maal_id').eq('maal_type', 'media')),
  ]);
  const mediaIds = mediaRows.map((m) => m.id);
  const variants = mediaIds.length
    ? await getAll<{ media_id: number; storage_path: string }>(() =>
        sb.from('media_variant').select('media_id,storage_path').eq('tier', 'thumb').in('media_id', mediaIds))
    : [];
  return mapMediaBibliotekRows(
    mediaRows,
    [...personRelationer, ...objektRelationer],
    mentions,
    new Map(variants.map((v) => [String(v.media_id), v.storage_path])),
  );
}

export type MediaAnvendelse = {
  afbildet: { type: string; id: string; navn: string; relationId: string }[];
  mentions: { kildeType: string; kildeId: string; subjektNavn: string }[];
};

const entityKey = (type: string, id: number | string) => `${type}:${id}`;
const fallbackEntityName = (type: string, id: number | string) => `${type} #${id}`;

export function mapMediaAnvendelse(
  mediaId: string,
  relationRows: RawMediaRelationRow[],
  mentionRows: RawMediaMentionRow[],
  narrativeRows: RawMediaNarrativeRow[],
  navnBySubjekt: ReadonlyMap<string, string>,
): MediaAnvendelse {
  const narrativeById = new Map(narrativeRows.map((n) => [String(n.id), n]));
  const afbildet: MediaAnvendelse['afbildet'] = [];
  for (const r of relationRows) {
    if (r.id == null || r.rolle !== 'afbildet') continue;
    let type: string;
    let id: number;
    if (r.objekt_type === 'media' && String(r.objekt_id) === mediaId) {
      type = r.subjekt_type;
      id = r.subjekt_id;
    } else if (r.subjekt_type === 'media' && String(r.subjekt_id) === mediaId) {
      type = r.objekt_type;
      id = r.objekt_id;
    } else {
      continue;
    }
    afbildet.push({
      type,
      id: String(id),
      navn: navnBySubjekt.get(entityKey(type, id)) ?? fallbackEntityName(type, id),
      relationId: String(r.id),
    });
  }
  const mentions = mentionRows
    .filter((m) => m.maal_type === 'media' && String(m.maal_id) === mediaId)
    .map((m) => {
      const narrative = m.kilde_type === 'narrative' ? narrativeById.get(String(m.kilde_id)) : undefined;
      const subjektNavn = narrative
        ? navnBySubjekt.get(entityKey(narrative.subjekt_type, narrative.subjekt_id))
          ?? fallbackEntityName(narrative.subjekt_type, narrative.subjekt_id)
        : '(ukendt subjekt)';
      return { kildeType: m.kilde_type, kildeId: String(m.kilde_id), subjektNavn };
    });
  return { afbildet, mentions };
}

async function fetchMediaEntityNames(
  sb: NonNullable<typeof supabase>,
  targets: { type: string; id: number }[],
): Promise<Map<string, string>> {
  const idsFor = (type: string) => [...new Set(targets.filter((t) => t.type === type).map((t) => t.id))];
  const personIds = idsFor('person');
  const estateIds = idsFor('estate');
  const armsIds = idsFor('coat_of_arms');
  const lineageIds = idsFor('lineage');
  const [persons, estates, arms, lineages] = await Promise.all([
    personIds.length ? getAll<{ id: number; visning_navn: string | null }>(() =>
      sb.from('person').select('id,visning_navn').in('id', personIds)) : [],
    estateIds.length ? getAll<{ id: number; navn: string | null }>(() =>
      sb.from('estate').select('id,navn').in('id', estateIds)) : [],
    armsIds.length ? getAll<{ id: number; blasonering: string | null }>(() =>
      sb.from('coat_of_arms').select('id,blasonering').in('id', armsIds)) : [],
    lineageIds.length ? getAll<{ id: number; navn: string | null }>(() =>
      sb.from('lineage').select('id,navn').in('id', lineageIds)) : [],
  ]);
  const names = new Map<string, string>();
  persons.forEach((r) => names.set(entityKey('person', r.id), r.visning_navn ?? fallbackEntityName('person', r.id)));
  estates.forEach((r) => names.set(entityKey('estate', r.id), r.navn ?? fallbackEntityName('estate', r.id)));
  arms.forEach((r) => names.set(entityKey('coat_of_arms', r.id), r.blasonering ?? fallbackEntityName('coat_of_arms', r.id)));
  lineages.forEach((r) => names.set(entityKey('lineage', r.id), r.navn ?? fallbackEntityName('lineage', r.id)));
  targets.filter((t) => t.type === 'slaegt').forEach((t) => names.set(entityKey('slaegt', t.id), 'Slægten (generelt)'));
  return names;
}

export async function fetchMediaAnvendelse(mediaId: string): Promise<MediaAnvendelse> {
  if (!supabase) return { afbildet: [], mentions: [] };
  const trimmedMediaId = mediaId.trim();
  if (!/^[1-9][0-9]*$/.test(trimmedMediaId) || trimmedMediaId.length > 19 || (trimmedMediaId.length === 19 && trimmedMediaId > '9223372036854775807')) return { afbildet: [], mentions: [] };
  const parsedMediaId = Number(trimmedMediaId);
  const numericMediaId: number | string = Number.isSafeInteger(parsedMediaId) ? parsedMediaId : trimmedMediaId;
  const sb = supabase;
  const [personRelationer, objektRelationer, mentions] = await Promise.all([
    getAll<RawMediaRelationRow>(() =>
      sb.from('relation').select('id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle')
        .eq('subjekt_type', 'person').eq('objekt_type', 'media').eq('objekt_id', numericMediaId)
        .eq('rolle', 'afbildet').order('id')),
    getAll<RawMediaRelationRow>(() =>
      sb.from('relation').select('id,subjekt_type,subjekt_id,objekt_type,objekt_id,rolle')
        .eq('subjekt_type', 'media').eq('subjekt_id', numericMediaId).eq('rolle', 'afbildet').order('id')),
    getAll<RawMediaMentionRow>(() =>
      sb.from('text_mention').select('kilde_type,kilde_id,maal_type,maal_id')
        .eq('maal_type', 'media').eq('maal_id', numericMediaId).order('kilde_type').order('kilde_id')),
  ]);
  const narrativeIds = [...new Set(mentions.filter((m) => m.kilde_type === 'narrative').map((m) => m.kilde_id))];
  const narratives = narrativeIds.length
    ? await getAll<RawMediaNarrativeRow>(() =>
        sb.from('narrative').select('id,subjekt_type,subjekt_id').in('id', narrativeIds))
    : [];
  const targets = [
    ...personRelationer.map((r) => ({ type: r.subjekt_type, id: r.subjekt_id })),
    ...objektRelationer.map((r) => ({ type: r.objekt_type, id: r.objekt_id })),
    ...narratives.map((n) => ({ type: n.subjekt_type, id: n.subjekt_id })),
  ];
  const names = await fetchMediaEntityNames(sb, targets);
  return mapMediaAnvendelse(String(numericMediaId), [...personRelationer, ...objektRelationer], mentions, narratives, names);
}

// Fælles hale: rel-par (media-id + relation-id) → signede/mappede PersonMedia. Retningen af selve
// relations-forespørgslen (person→media vs. media→objekt) afgøres af kalderne nedenfor.
async function mediaFromRelPairs(sb: NonNullable<typeof supabase>, pairs: { mediaId: number; relationId: number }[]): Promise<PersonMedia[]> {
  if (!pairs.length) return [];
  const relByMediaId = new Map(pairs.map((p) => [String(p.mediaId), String(p.relationId)]));
  const mediaIds = pairs.map((p) => p.mediaId);
  const [rows, variants] = await Promise.all([
    getAll<RawPersonMediaRow>(() =>
      sb.from('media').select('id,slags,titel,kunstner,datering,storage_path,upload_status,maa_publiceres,rettigheder_status,mime_type,byte_size,bredde,hoejde,original_filnavn').in('id', mediaIds)),
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

// ---- Tværudgave-matching: MatchFrame-input fra DB (Problem 3 §11) ----
// Tynde supabase-fetches; de rene mappere bor i @daa/core (delt m. web). Re-eksportér typen.
export type { RedMatchPerson };

/** Hent MatchFrame-input for hele redaktions-datasættet (tynd; @daa/core-mappere gør arbejdet).
 *  NB (skala): conclusion/assertion hentes for alle fact-typer og filtreres klient-side til
 *  fødsel/død (batch-`.in`-filter sprænger URL-længde). Rigtig fix: server-side view. Udskudt. */
export async function fetchMatchPersoner(): Promise<RedMatchPerson[]> {
  if (!supabase) return [];
  const sb = supabase;
  const [persons, facts, concs, assertions, extIds] = await Promise.all([
    getAll<MatchPersonRow>(() => sb.from('person').select('id,visning_navn,koen,staged')),
    getAll<MatchFactRow>(() => sb.from('fact').select('id,subjekt_id,faktatype').eq('subjekt_type', 'person').in('faktatype', ['fødsel', 'død'])),
    getAll<MatchConcRow>(() => sb.from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact').eq('status', 'afklaret')),
    getAll<MatchAssertRow>(() => sb.from('assertion').select('id,date_min,date_max').eq('target_type', 'fact')),
    getAll<MatchExtIdRow>(() => sb.from('person_external_id').select('person_id,source_id')),
  ]);
  return buildMatchPersoner(persons, facts, concs, assertions, extIds);
}

/** Hent eksisterende ikke_samme_som-afvisninger (person→person). */
export async function fetchIkkeSammeSomPar(): Promise<{ aId: string; bId: string }[]> {
  if (!supabase) return [];
  const sb = supabase;
  const rows = await getAll<{ subjekt_id: number; objekt_id: number }>(() =>
    sb.from('relation').select('subjekt_id,objekt_id')
      .eq('rolle', 'ikke_samme_som').eq('subjekt_type', 'person').eq('objekt_type', 'person'));
  return parseIkkeSammeSomPar(rows);
}

/** Hent alle samme_som-links (person→person) — til arbejdslistens "afklaret"-markering. */
export async function fetchSammeSomPar(): Promise<{ aId: string; bId: string }[]> {
  if (!supabase) return [];
  const sb = supabase;
  const rows = await getAll<{ subjekt_id: number; objekt_id: number }>(() =>
    sb.from('relation').select('subjekt_id,objekt_id')
      .eq('rolle', 'samme_som').eq('subjekt_type', 'person').eq('objekt_type', 'person'));
  return parseIkkeSammeSomPar(rows);
}
