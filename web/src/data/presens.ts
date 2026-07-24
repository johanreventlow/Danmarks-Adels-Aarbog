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
//
// `fodt` (valgfri): gift-ind kvinder tager ægtefællens køns-bøjede titel + efternavn i BEGGE
// formater (inkl. efternavn i det ellers efternavn-løse "øvrige rækker"-format), med egen
// fødeidentitet i en født-klausul — "Lensgrevinde Hedwig Reventlow, født Mundhenke" (fundet ved
// bruger-verifikation 2026-07-24). Se beregningen i mapPresensNavneDele nedenfor.
export type PresensNavneDele = { navn: string; titel: string; efternavn: string; fodt?: string };

type RawNavneDele = { id: number | string; visning_navn: string | null; visning_efternavn: string | null; koen?: string | null };

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

// Køns-bøjning af adelstitler — gift-ind kvinder overtager ægtefællens RANG (ikke egen fødetitel)
// som deres visnings-titel; kun mænd-formerne fra ADELS_TITLER er nøgler her, da 'komtesse' (ugift
// datter) og de kvindelige varianter i øvrigt ikke er noget en kvinde "gifter sig til" via ægtefællen.
const FEMININ_TITEL: Record<string, string> = {
  greve: 'Grevinde', lensgreve: 'Lensgrevinde', baron: 'Baronesse',
  friherre: 'Friherreinde', rigsgreve: 'Rigsgrevinde',
};
// Eksporteret til test.
export const feminiserTitel = (mandsTitel: string): string | null => FEMININ_TITEL[mandsTitel.trim().toLowerCase()] ?? null;

// Født-klausul af EGEN (ikke ægtefællens) titel+efternavn — titel med lille forbogstav som i
// hovedrække-formatet ("født komtesse Ahlefeldt-Laurvig"), aldrig stort (det ville fejlagtigt
// signalere at "komtesse" var en del af hendes NUVÆRENDE, tilgiftede rang).
function fodtKlausul(egenTitel: string, egetEfternavn: string): string | undefined {
  if (!egetEfternavn) return undefined;
  return egenTitel ? `${egenTitel.toLowerCase()} ${egetEfternavn}` : egetEfternavn;
}

export function mapPresensNavneDele(
  personer: RawNavneDele[],
  adelsTitelFakta: RawTitelFact[],
  aegtefaelleIdById: Map<string, string> = new Map(),
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
  const personById = new Map(personer.map((p) => [String(p.id), p]));
  const out: Record<string, PresensNavneDele> = {};
  for (const p of personer) {
    const id = String(p.id);
    const egenTitel = titelById.get(id) ?? '';
    const egetEfternavn = p.visning_efternavn ?? '';
    const dele: PresensNavneDele = { navn: p.visning_navn ?? '', titel: egenTitel, efternavn: egetEfternavn };

    // Gift-ind kvinde: ægtefællens køns-bøjede rang + efternavn overtages som visnings-titel,
    // egen fødeidentitet flyttes til en "født"-klausul (bruger-verifikation 2026-07-24, se øverst).
    if (p.koen === 'kvinde') {
      const aegtefaelleId = aegtefaelleIdById.get(id);
      const aegtefaelle = aegtefaelleId != null ? personById.get(aegtefaelleId) : undefined;
      const aegtefaelleTitel = aegtefaelleId != null ? titelById.get(aegtefaelleId) : undefined;
      const feminiseret = aegtefaelleTitel ? feminiserTitel(aegtefaelleTitel) : null;
      if (feminiseret && aegtefaelle?.visning_efternavn) {
        dele.titel = feminiseret;
        dele.efternavn = aegtefaelle.visning_efternavn;
        dele.fodt = fodtKlausul(egenTitel, egetEfternavn);
      }
    }
    out[id] = dele;
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

type RawPartnerRow = { family_id: number | string; person_id: number | string };

// Ægtefælle pr. person (kun 'partner'-rollen, jf. family_member.rolle) — antager monogamt par pr.
// family_id (ordinal-feltet modellerer flere ægteskaber som SEPARATE family-rækker, ikke flere
// partnere i samme). Har en person flere ægteskaber (enke, gengift), vinder den sidst behandlede
// familie i family_id-orden (ORDER BY family_id, jf. filens øvrige queries) — ikke en semantisk
// "seneste ægteskab"-regel, men deterministisk, og proportionalt med det aktuelle behov (kun
// gift-ind-titel-visning).
async function fetchAegtefaelleIdById(personIds: number[]): Promise<Map<string, string>> {
  if (!personIds.length) return new Map();
  const mine = await getAll<RawPartnerRow>(() =>
    supabase.from('family_member').select('family_id,person_id').eq('rolle', 'partner').in('person_id', personIds).order('family_id'));
  if (!mine.length) return new Map();
  const familyIds = [...new Set(mine.map((m) => m.family_id))];
  const alle = await getAll<RawPartnerRow>(() =>
    supabase.from('family_member').select('family_id,person_id').eq('rolle', 'partner').in('family_id', familyIds).order('family_id'));
  const partnereByFamily = new Map<string, string[]>();
  for (const r of alle) {
    const k = String(r.family_id);
    const arr = partnereByFamily.get(k) ?? [];
    arr.push(String(r.person_id));
    partnereByFamily.set(k, arr);
  }
  const aegtefaelleIdById = new Map<string, string>();
  for (const m of mine) {
    const id = String(m.person_id);
    const partnere = partnereByFamily.get(String(m.family_id)) ?? [];
    const andenPart = partnere.find((pid) => pid !== id);
    if (andenPart) aegtefaelleIdById.set(id, andenPart);
  }
  return aegtefaelleIdById;
}

export async function fetchPresensNavneDele(ids: string[]): Promise<Record<string, PresensNavneDele>> {
  if (!ids.length) return {};
  const numIds = [...new Set(ids.map(Number).filter((n) => Number.isFinite(n)))];
  const aegtefaelleIdById = await fetchAegtefaelleIdById(numIds);
  const aegtefaelleIds = [...new Set([...aegtefaelleIdById.values()].map(Number))];
  const alleIds = [...new Set([...numIds, ...aegtefaelleIds])];
  const [personer, adelsTitelFakta] = await Promise.all([
    getAll<RawNavneDele>(() => supabase.from('person').select('id,visning_navn,visning_efternavn,koen').in('id', alleIds)),
    fetchAdelsTitelFakta(alleIds),
  ]);
  return mapPresensNavneDele(personer, adelsTitelFakta, aegtefaelleIdById);
}

const fodtSuffiks = (fodt: string | undefined): string => (fodt ? `, født ${fodt}` : '');

export function formatAnkerNavn(dele: PresensNavneDele | undefined, fallback: string): string {
  if (!dele || !dele.navn) return fallback;
  const titel = dele.titel ? ` ${dele.titel.toLowerCase()}` : '';
  const efternavn = dele.efternavn ? ` ${dele.efternavn}` : '';
  return `${dele.navn}${titel}${efternavn}${fodtSuffiks(dele.fodt)}`;
}

// Stort forbogstav uafhængigt af hvordan titlen faktisk er lagret (ingen DB-CHECK håndhæver
// stort forbogstav på visning_titel — reviewfund; loaderen gemmer titel-fakta verbatim).
const capFirst = (s: string): string => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s);

export function formatAndetNavn(dele: PresensNavneDele | undefined, fallback: string): string {
  if (!dele || !dele.navn) return fallback;
  const titelOgNavn = dele.titel ? `${capFirst(dele.titel)} ${dele.navn}` : dele.navn;
  // født-klausul til stede = tilgiftet titel (se mapPresensNavneDele) → efternavnet skal med,
  // i modsætning til det almindelige "øvrige rækker"-format der ellers udelader det.
  if (!dele.fodt) return titelOgNavn;
  const efternavn = dele.efternavn ? ` ${dele.efternavn}` : '';
  return `${titelOgNavn}${efternavn}${fodtSuffiks(dele.fodt)}`;
}
