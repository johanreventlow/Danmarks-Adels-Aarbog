// Evidens-read-lag til person-editoren. Modellen er polymorf (assertion/conclusion peger på
// fact via target_type/target_id UDEN rigtig FK), så vi henter N flade queries og joiner i
// klienten. citation→source HAR FK og nestes (spec §3). Ren joinEvidence er testbar uden net.
import { supabase } from '../lib/supabase';
import { FELT_FAKTATYPE } from './redaktionWrite';

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
export type PersonEvidence = { felter: Record<string, FeltEvidens>; koen: string | null };

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
  const felter: Record<string, FeltEvidens> = {};
  for (const f of rows.facts) {
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
    const distinkte = new Set(opl.map((o) => o.vaerdi));
    felter[felt] = {
      felt, faktatype: f.faktatype, factId: f.id,
      konklusionAssertionId: valgt, oplysninger: opl, uenig: distinkte.size > 1,
    };
  }
  return { felter, koen: rows.koen };
}

export type Konflikt = { personId: string; felt: string; antalVaerdier: number };

export function mapKonfliktRow(r: { person_id: number; faktatype: string; antal_vaerdier: number }): Konflikt {
  return { personId: String(r.person_id), felt: FAKTATYPE_FELT[r.faktatype] ?? r.faktatype, antalVaerdier: r.antal_vaerdier };
}

export async function fetchKonflikter(): Promise<Konflikt[]> {
  if (!supabase) return [];
  const { data } = await supabase.from('red_konflikt').select('person_id,faktatype,antal_vaerdier');
  return (data ?? []).map(mapKonfliktRow);
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
