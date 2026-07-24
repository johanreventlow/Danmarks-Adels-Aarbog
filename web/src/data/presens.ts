// Præsensliste-grundlag: levende-flag + overhoved-fakta. RLS afgør hvad klienten ser —
// anon/medlem får ingen levende rækker (fail-closed), redaktør-JWT ser alt. Visningen
// tilføjer altså ingen eksponering (spec 2026-07-22 §8).
import { supabase } from '../supabase';
import { getAll, parseOverhovedVaerdi } from '@daa/core';
import type { PresensAnker } from '@daa/core';

export type PresensGrundlag = { ankre: PresensAnker[]; levendeById: Record<string, boolean> };

type RawLevende = { id: number | string; levende: boolean | null };
type RawOverhovedFact = { id: number | string; subjekt_id: number | string };
type RawKonkl = { target_id: number | string; valgt_assertion_id: number | string | null };
type RawAssert = { id: number | string; vaerdi_tekst: string | null };

export function mapPresensGrundlag(
  persons: RawLevende[],
  facts: RawOverhovedFact[],
  conclusions: RawKonkl[],
  assertions: RawAssert[],
): PresensGrundlag {
  const levendeById: Record<string, boolean> = {};
  for (const p of persons) levendeById[String(p.id)] = p.levende === true;
  const assertById = new Map(assertions.map((a) => [String(a.id), a.vaerdi_tekst]));
  const valgtByFact = new Map(conclusions.map((c) => [String(c.target_id), c.valgt_assertion_id]));
  const ankre: PresensAnker[] = [];
  for (const f of facts) {
    const valgt = valgtByFact.get(String(f.id));
    if (valgt == null) continue; // ingen afklaret konklusion → intet anker
    const vaerdi = assertById.get(String(valgt));
    if (vaerdi == null) continue;
    const anker = parseOverhovedVaerdi(String(f.subjekt_id), vaerdi);
    if (anker) ankre.push(anker); // uparsebar værdi droppes fail-closed
  }
  return { ankre, levendeById };
}

export async function fetchPresensGrundlag(): Promise<PresensGrundlag> {
  const persons = await getAll<RawLevende>(() => supabase.from('person').select('id,levende'));
  const facts = await getAll<RawOverhovedFact>(() =>
    supabase.from('fact').select('id,subjekt_id').eq('subjekt_type', 'person').eq('faktatype', 'overhoved').order('id'));
  if (!facts.length) return mapPresensGrundlag(persons, [], [], []);
  const factIds = facts.map((f) => f.id);
  const conclusions = await getAll<RawKonkl>(() =>
    supabase.from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact').eq('status', 'afklaret').in('target_id', factIds).order('id'));
  const assertionIds = conclusions.map((c) => c.valgt_assertion_id).filter((v): v is number | string => v != null);
  const assertions = assertionIds.length
    ? await getAll<RawAssert>(() => supabase.from('assertion').select('id,vaerdi_tekst').in('id', assertionIds).order('id'))
    : [];
  return mapPresensGrundlag(persons, facts, conclusions, assertions);
}

// Navne-dele til bogens to navngivningsformater (DAA-konvention, fundet ved bruger-verifikation
// 2026-07-24): grenens overhoved ("hovedrækken", gren.ankerBlok) vises med fulde fornavne + titel
// INDE i navnet (småt) + efternavn — "Christian Ditlev Ludvig lensgreve Reventlow". Alle øvrige
// rækker (søskende, efterkommere, forbindelsesled) nøjes med Titel (stort forbogstav) + fornavne,
// UDEN efternavn — det er underforstået: "Greve Johan Martin", "Komtesse Julie". Titelløse
// personer (typisk gift-ind ægtefæller) vises uden præfiks. Adskilt fra `model.byId[id].name`
// (= visning_fuldt_navn, som allerede har efternavnet indbagt og derfor ikke kan bruges til
// "øvrige rækker"-formatet uden det).
export type PresensNavneDele = { navn: string; titel: string; efternavn: string };

type RawNavneDele = { id: number | string; visning_navn: string | null; visning_efternavn: string | null };

// BEVIDST IKKE person.visning_titel (den cachede visnings-kolonne): faktatypen 'titel' er i praksis
// et bredt "titler og hverv"-felt (militærgrad, hofembede, akademisk grad, ordensbånd, gods-
// tilknytning …), og en person kan have FLERE afklarede titel-fakta samtidig. Cachen vælger kun
// én (typisk den senest afklarede), ikke nødvendigvis adelstitlen — fundet empirisk (person 469
// "Einar…" har to afklarede titel-fakta, "Greve" og "Premierløjtnant i vesttyske Pionier
// Bataillons reserve"; cachen valgte den sidste, hvilket ville have givet "Einar Karl Ludwig
// premierløjtnant i vesttyske pionier bataillons reserve Reventlow" i hovedrække-formatet).
// Derfor slås alle afklarede titel-fakta op direkte og filtreres til en lukket adels-titel-liste.
const ADELS_TITLER = new Set([
  'greve', 'grevinde', 'komtesse', 'comtesse', 'lensgreve', 'lensgrevinde',
  'baron', 'baronesse', 'friherre', 'friherreinde', 'rigsgreve', 'rigsgrevinde',
]);
// Eksporteret til test — den præcise mekanisme der udelukker fx "Premierløjtnant i vesttyske
// Pionier Bataillons reserve" (fundet i prod for person 469) fra at blive brugt som adelstitel.
export const erAdelsTitel = (s: string): boolean => ADELS_TITLER.has(s.trim().toLowerCase());

type RawTitelFact = { subjekt_id: number | string; vaerdi_tekst: string };

export function mapPresensNavneDele(
  personer: RawNavneDele[],
  adelsTitelFakta: RawTitelFact[],
): Record<string, PresensNavneDele> {
  const titelById = new Map<string, string>();
  for (const t of adelsTitelFakta) {
    const id = String(t.subjekt_id);
    // Første fund vinder — deterministisk fordi fetchAdelsTitelFakta ORDER BY id på alle tre led,
    // så rækkefølgen her altid er laveste-conclusion-id-først. Ved to konkurrerende adelstitler
    // for samme person (fx grevelig OG friherre-arv) vinder den tidligst afklarede — en rimelig,
    // men vilkårlig, standardregel; ingen semantisk "vigtigst titel"-rangordning er indbygget.
    if (!titelById.has(id)) titelById.set(id, t.vaerdi_tekst);
  }
  const out: Record<string, PresensNavneDele> = {};
  for (const p of personer) {
    const id = String(p.id);
    out[id] = { navn: p.visning_navn ?? '', titel: titelById.get(id) ?? '', efternavn: p.visning_efternavn ?? '' };
  }
  return out;
}

// Fælles fact→conclusion→assertion-join (samme mønster som fetchPresensGrundlag's 'overhoved'-
// opslag ovenfor), filtreret til afklarede 'titel'-fakta der matcher den lukkede adelstitel-liste.
async function fetchAdelsTitelFakta(personIds: number[]): Promise<RawTitelFact[]> {
  if (!personIds.length) return [];
  const facts = await getAll<{ id: number | string; subjekt_id: number | string }>(() =>
    supabase.from('fact').select('id,subjekt_id').eq('subjekt_type', 'person').eq('faktatype', 'titel').in('subjekt_id', personIds).order('id'));
  if (!facts.length) return [];
  const factIds = facts.map((f) => f.id);
  const conclusions = await getAll<RawKonkl>(() =>
    supabase.from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact').eq('status', 'afklaret').in('target_id', factIds).order('id'));
  const assertionIds = conclusions.map((c) => c.valgt_assertion_id).filter((v): v is number | string => v != null);
  if (!assertionIds.length) return [];
  const assertions = await getAll<RawAssert>(() => supabase.from('assertion').select('id,vaerdi_tekst').in('id', assertionIds).order('id'));
  const assertById = new Map(assertions.map((a) => [String(a.id), a.vaerdi_tekst]));
  const subjektByFact = new Map(facts.map((f) => [String(f.id), f.subjekt_id]));
  const out: RawTitelFact[] = [];
  for (const c of conclusions) {
    const vaerdi = c.valgt_assertion_id != null ? assertById.get(String(c.valgt_assertion_id)) : null;
    const subjekt_id = subjektByFact.get(String(c.target_id));
    if (vaerdi && subjekt_id != null && erAdelsTitel(vaerdi)) out.push({ subjekt_id, vaerdi_tekst: vaerdi });
  }
  return out;
}

export async function fetchPresensNavneDele(ids: string[]): Promise<Record<string, PresensNavneDele>> {
  if (!ids.length) return {};
  const numIds = [...new Set(ids.map(Number).filter((n) => Number.isFinite(n)))];
  const [personer, adelsTitelFakta] = await Promise.all([
    getAll<RawNavneDele>(() => supabase.from('person').select('id,visning_navn,visning_efternavn').in('id', numIds)),
    fetchAdelsTitelFakta(numIds),
  ]);
  return mapPresensNavneDele(personer, adelsTitelFakta);
}

export function formatAnkerNavn(dele: PresensNavneDele | undefined, fallback: string): string {
  if (!dele || !dele.navn) return fallback;
  const titel = dele.titel ? ` ${dele.titel.toLowerCase()}` : '';
  const efternavn = dele.efternavn ? ` ${dele.efternavn}` : '';
  return `${dele.navn}${titel}${efternavn}`;
}

// Stort forbogstav uafhængigt af hvordan titlen faktisk er lagret (ingen DB-CHECK håndhæver
// stort forbogstav på visning_titel — reviewfund; loaderen gemmer titel-fakta verbatim).
const capFirst = (s: string): string => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s);

export function formatAndetNavn(dele: PresensNavneDele | undefined, fallback: string): string {
  if (!dele || !dele.navn) return fallback;
  return dele.titel ? `${capFirst(dele.titel)} ${dele.navn}` : dele.navn;
}
