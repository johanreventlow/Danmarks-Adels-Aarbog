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
};
type RawRedPerson = {
  id: number; visning_navn: string | null; visning_foedt: string | null;
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
  };
}

// Pagineret (PostgREST capper ved 1000 lydløst — getAll gentager .range indtil tomt).
// getAll kaster videre ved Supabase-error → ingen tom-som-clean (cycle 03 NEW1).
export async function fetchRedaktionPersoner(): Promise<RedPerson[]> {
  if (!supabase) return [];
  const sb = supabase;
  const rows = await getAll<RawRedPerson>(() =>
    sb.from('person').select('id,visning_navn,visning_foedt,visning_doed,levende,privat'));
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

export type PersonNarrativ = { tekst: string; privat: boolean };

export function mapNarrativRow(rows: { tekst: string | null; privat: boolean | null }[]): PersonNarrativ | null {
  const first = rows[0];
  if (!first) return null;
  return { tekst: first.tekst ?? '', privat: Boolean(first.privat) };
}

// Henter FØRSTE narrativ by id (uanset privat) = præcis den række red_upsert_narrativ redigerer.
// Prefill-kilde == skrive-mål; privat-flaget bevares af editoren på Gem (Codex 2B #1).
export async function fetchPersonNarrativ(id: string): Promise<PersonNarrativ | null> {
  if (!supabase) return null;
  const { data, error } = await supabase
    .from('narrative').select('tekst,privat')
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

export type FamiliePartner = { personId: string; navn: string; konfidens: string | null; ordinal: number | null };
export type FamilieBarn = { personId: string; navn: string; rolle: string; konfidens: string | null };
export type FamilieUnion = { familyId: string; type: string; partnere: FamiliePartner[]; boern: FamilieBarn[] };
export type SomBarn = { familyId: string; rolle: string; konfidens: string | null; foraeldre: { personId: string; navn: string }[] };
export type PersonFamilie = { somPartner: FamilieUnion[]; somBarn: SomBarn[] };
type RawFamRow = { family_id: number; person_id: number; rolle: string; ordinal: number | null; konfidens: string | null };
type RawFamilyMeta = { id: number; type: string | null };
const BARN_ROLLER = ['barn', 'adopteret_barn', 'plejebarn', 'stedbarn'];

export function mapFamilieRows(personId: string, families: RawFamilyMeta[], members: RawFamRow[], model: import('./types').Model | null): PersonFamilie {
  const navnAf = (pid: number) => model?.byId?.[String(pid)]?.name ?? `#${pid}`;
  const typeAf = new Map(families.map((f) => [String(f.id), f.type ?? '']));
  const byFamily = new Map<string, RawFamRow[]>();
  members.forEach((m) => {
    const k = String(m.family_id);
    (byFamily.get(k) ?? byFamily.set(k, []).get(k)!).push(m);
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
          .map((r) => ({ personId: String(r.person_id), navn: navnAf(r.person_id), konfidens: r.konfidens, ordinal: r.ordinal })),
        boern: rows.filter((r) => BARN_ROLLER.includes(r.rolle) && String(r.person_id) !== personId)
          .map((r) => ({ personId: String(r.person_id), navn: navnAf(r.person_id), rolle: r.rolle, konfidens: r.konfidens })),
      });
    }
    migRows.filter((r) => BARN_ROLLER.includes(r.rolle)).forEach((mig) => {
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
  const members = await getAll<RawFamRow>(() =>
    sb.from('family_member').select('family_id,person_id,rolle,ordinal,konfidens').in('family_id', famIds)
      .order('ordinal', { ascending: true, nullsFirst: false }).order('person_id'));
  const families = await getAll<RawFamilyMeta>(() =>
    sb.from('family').select('id,type').in('id', famIds));
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
