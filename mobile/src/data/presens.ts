// Præsensliste-grundlag: levende-flag + overhoved-fakta. RLS afgør hvad klienten ser —
// anon/medlem får ingen levende rækker (fail-closed), redaktør-JWT ser alt. Visningen
// tilføjer altså ingen eksponering (spec 2026-07-22 §8).
import { supabase } from '../lib/supabase';
import { getAll, parseOverhovedVaerdi, udenSlaegtsnavnTilSidst } from '@daa/core';
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
  if (!supabase) return { ankre: [], levendeById: {} };
  const sb = supabase;
  const persons = await getAll<RawLevende>(() => sb.from('person').select('id,levende').order('id'));
  const facts = await getAll<RawOverhovedFact>(() =>
    sb.from('fact').select('id,subjekt_id').eq('subjekt_type', 'person').eq('faktatype', 'overhoved').order('id'));
  if (!facts.length) return mapPresensGrundlag(persons, [], [], []);
  const factIds = facts.map((f) => f.id);
  const conclusions = await getAll<RawKonkl>(() =>
    sb.from('conclusion').select('target_id,valgt_assertion_id').eq('target_type', 'fact').eq('status', 'afklaret').in('target_id', factIds).order('id'));
  const assertionIds = conclusions.map((c) => c.valgt_assertion_id).filter((v): v is number | string => v != null);
  const assertions = assertionIds.length
    ? await getAll<RawAssert>(() => sb.from('assertion').select('id,vaerdi_tekst').in('id', assertionIds).order('id'))
    : [];
  return mapPresensGrundlag(persons, facts, conclusions, assertions);
}

// Navne-dele til bogens to navngivningsformater (DAA-konvention, fundet ved bruger-verifikation
// 2026-07-24): grenens overhoved vises med fulde fornavne + titel INDE i navnet (småt) +
// efternavn. Alle øvrige rækker nøjes med Titel (stort forbogstav) + fornavne, normalt UDEN
// efternavn. Det kan ikke bygges fra model.byId[id].name, hvor efternavnet allerede er indbagt.
//
// `tilgiftet` og `fodt` er BEVIDST to uafhængige oplysninger:
// - `tilgiftet` betyder, at en gift-ind kvindes titel/efternavn er overskrevet med ægtefællens,
//   og styrer om øvrige-række-formatet skal medtage efternavnet.
// - `fodt` er kun hendes registrerede fødeidentitet til en "født X"-klausul.
// En gift-ind kvinde uden registreret pigenavn har derfor tilgiftet=true, men fodt=undefined.
// At gate efternavnet på `fodt` var web-buggen rettet i commit 69596aa: ankerformatet viste da
// efternavnet, mens øvrige-række-formatet tabte det for præcis dette tilfælde.
export type PresensNavneDele = {
  navn: string;
  titel: string;
  efternavn: string;
  fodt?: string;
  tilgiftet?: boolean;
};

type RawNavneDele = {
  id: number | string;
  visning_navn: string | null;
  visning_efternavn: string | null;
  koen?: string | null;
};
type RawTitelFact = { subjekt_id: number | string; vaerdi_tekst: string };
type RawPartnerRow = { family_id: number | string; person_id: number | string };

// person.visning_titel bruges ikke: den cachede kolonne kan pege på et hverv/militærgrad frem
// for adelstitlen. Alle afklarede titel-fakta filtreres derfor gennem denne lukkede liste.
const ADELS_TITLER = new Set([
  'greve', 'grevinde', 'komtesse', 'comtesse', 'lensgreve', 'lensgrevinde',
  'baron', 'baronesse', 'friherre', 'friherreinde', 'rigsgreve', 'rigsgrevinde',
]);

export const erAdelsTitel = (s: string): boolean => ADELS_TITLER.has(s.trim().toLowerCase());

const FEMININ_TITEL: Record<string, string> = {
  greve: 'Grevinde',
  lensgreve: 'Lensgrevinde',
  baron: 'Baronesse',
  friherre: 'Friherreinde',
  rigsgreve: 'Rigsgrevinde',
};

export const feminiserTitel = (mandsTitel: string): string | null =>
  FEMININ_TITEL[mandsTitel.trim().toLowerCase()] ?? null;

function fodtKlausul(egenTitel: string, egetEfternavn: string): string | undefined {
  if (!egetEfternavn) return undefined;
  return egenTitel ? `${egenTitel.toLowerCase()} ${egetEfternavn}` : egetEfternavn;
}

// Projektejeren 20/11 (#401): pigenavnet står ikke dobbelt — se udenSlaegtsnavnTilSidst i @daa/core.
export function mapPresensNavneDele(
  personer: RawNavneDele[],
  adelsTitelFakta: RawTitelFact[],
  aegtefaelleIdById: Map<string, string> = new Map(),
  // #401: afklarede fødenavn-påstande vinder over visning_efternavn i født-klausulen (web/src/data/presens.ts).
  foedenavnFakta: RawTitelFact[] = [],
): Record<string, PresensNavneDele> {
  const foedenavnById = new Map<string, string>();
  for (const f of foedenavnFakta) {
    const id = String(f.subjekt_id);
    const v = f.vaerdi_tekst?.trim();
    if (v && !foedenavnById.has(id)) foedenavnById.set(id, v);
  }
  const titelById = new Map<string, string>();
  for (const t of adelsTitelFakta) {
    const id = String(t.subjekt_id);
    // Første fund vinder; fetcherne sorterer alle join-led efter id.
    if (!titelById.has(id)) titelById.set(id, t.vaerdi_tekst);
  }
  const personById = new Map(personer.map((p) => [String(p.id), p]));
  const out: Record<string, PresensNavneDele> = {};
  for (const p of personer) {
    const id = String(p.id);
    const egenTitel = titelById.get(id) ?? '';
    const egetEfternavn = p.visning_efternavn ?? '';
    const dele: PresensNavneDele = {
      navn: p.visning_navn ?? '',
      titel: egenTitel,
      efternavn: egetEfternavn,
    };

    if (p.koen === 'kvinde') {
      const aegtefaelleId = aegtefaelleIdById.get(id);
      const aegtefaelle = aegtefaelleId != null ? personById.get(aegtefaelleId) : undefined;
      const aegtefaelleTitel = aegtefaelleId != null ? titelById.get(aegtefaelleId) : undefined;
      const feminiseret = aegtefaelleTitel ? feminiserTitel(aegtefaelleTitel) : null;
      if (feminiseret && aegtefaelle?.visning_efternavn) {
        dele.titel = feminiseret;
        dele.efternavn = aegtefaelle.visning_efternavn;
        dele.tilgiftet = true;
        const foede = foedenavnById.get(id) ?? egetEfternavn;
        dele.fodt = fodtKlausul(egenTitel, foede);
        if (dele.fodt) dele.navn = udenSlaegtsnavnTilSidst(dele.navn, foede);
      }
    }
    out[id] = dele;
  }
  return out;
}

async function fetchFaktaVaerdier(faktatype: string, personIds: number[]): Promise<RawTitelFact[]> {
  if (!supabase || !personIds.length) return [];
  const sb = supabase;
  const facts = await getAll<{ id: number | string; subjekt_id: number | string }>(() =>
    sb.from('fact').select('id,subjekt_id')
      .eq('subjekt_type', 'person').eq('faktatype', faktatype).in('subjekt_id', personIds).order('id'));
  if (!facts.length) return [];
  const factIds = facts.map((f) => f.id);
  const conclusions = await getAll<RawKonkl>(() =>
    sb.from('conclusion').select('target_id,valgt_assertion_id')
      .eq('target_type', 'fact').eq('status', 'afklaret').in('target_id', factIds).order('id'));
  const assertionIds = conclusions
    .map((c) => c.valgt_assertion_id)
    .filter((v): v is number | string => v != null);
  if (!assertionIds.length) return [];
  const assertions = await getAll<RawAssert>(() =>
    sb.from('assertion').select('id,vaerdi_tekst').in('id', assertionIds).order('id'));
  const assertById = new Map(assertions.map((a) => [String(a.id), a.vaerdi_tekst]));
  const subjektByFact = new Map(facts.map((f) => [String(f.id), f.subjekt_id]));
  const out: RawTitelFact[] = [];
  for (const c of conclusions) {
    const vaerdi = c.valgt_assertion_id != null
      ? assertById.get(String(c.valgt_assertion_id))
      : null;
    const subjekt_id = subjektByFact.get(String(c.target_id));
    if (vaerdi && subjekt_id != null) {
      out.push({ subjekt_id, vaerdi_tekst: vaerdi });
    }
  }
  return out;
}

async function fetchAdelsTitelFakta(personIds: number[]): Promise<RawTitelFact[]> {
  return (await fetchFaktaVaerdier('titel', personIds)).filter((t) => erAdelsTitel(t.vaerdi_tekst));
}

async function fetchAegtefaelleIdById(personIds: number[]): Promise<Map<string, string>> {
  if (!supabase || !personIds.length) return new Map();
  const sb = supabase;
  const mine = await getAll<RawPartnerRow>(() =>
    sb.from('family_member').select('family_id,person_id')
      .eq('rolle', 'partner').in('person_id', personIds).order('family_id').order('person_id'));
  if (!mine.length) return new Map();
  const familyIds = [...new Set(mine.map((m) => m.family_id))];
  const alle = await getAll<RawPartnerRow>(() =>
    sb.from('family_member').select('family_id,person_id')
      .eq('rolle', 'partner').in('family_id', familyIds).order('family_id').order('person_id'));
  const partnereByFamily = new Map<string, string[]>();
  for (const r of alle) {
    const key = String(r.family_id);
    const partnere = partnereByFamily.get(key) ?? [];
    partnere.push(String(r.person_id));
    partnereByFamily.set(key, partnere);
  }
  const out = new Map<string, string>();
  for (const m of mine) {
    const id = String(m.person_id);
    const andenPart = (partnereByFamily.get(String(m.family_id)) ?? [])
      .find((personId) => personId !== id);
    if (andenPart) out.set(id, andenPart);
  }
  return out;
}

export async function fetchPresensNavneDele(
  ids: string[],
): Promise<Record<string, PresensNavneDele>> {
  if (!supabase || !ids.length) return {};
  const sb = supabase;
  const numIds = [...new Set(ids.map(Number).filter((n) => Number.isFinite(n)))];
  const aegtefaelleIdById = await fetchAegtefaelleIdById(numIds);
  const aegtefaelleIds = [...new Set([...aegtefaelleIdById.values()].map(Number))];
  const alleIds = [...new Set([...numIds, ...aegtefaelleIds])];
  const [personer, adelsTitelFakta, foedenavnFakta] = await Promise.all([
    getAll<RawNavneDele>(() =>
      sb.from('person').select('id,visning_navn,visning_efternavn,koen').in('id', alleIds).order('id')),
    fetchAdelsTitelFakta(alleIds),
    fetchFaktaVaerdier('fødenavn', alleIds),
  ]);
  return mapPresensNavneDele(personer, adelsTitelFakta, aegtefaelleIdById, foedenavnFakta);
}

const fodtSuffiks = (fodt: string | undefined): string => (fodt ? `, født ${fodt}` : '');

export function formatAnkerNavn(
  dele: PresensNavneDele | undefined,
  fallback: string,
): string {
  if (!dele || !dele.navn) return fallback;
  const titel = dele.titel ? ` ${dele.titel.toLowerCase()}` : '';
  const efternavn = dele.efternavn ? ` ${dele.efternavn}` : '';
  return `${dele.navn}${titel}${efternavn}${fodtSuffiks(dele.fodt)}`;
}

const capFirst = (s: string): string =>
  s ? s.charAt(0).toUpperCase() + s.slice(1) : s;

export function formatAndetNavn(
  dele: PresensNavneDele | undefined,
  fallback: string,
): string {
  if (!dele || !dele.navn) return fallback;
  const titelOgNavn = dele.titel ? `${capFirst(dele.titel)} ${dele.navn}` : dele.navn;
  // Gate på tilgiftet, ikke fodt: en gift-ind kvinde uden registreret pigenavn skal stadig
  // vise ægtefællens efternavn.
  if (!dele.tilgiftet) return titelOgNavn;
  const efternavn = dele.efternavn ? ` ${dele.efternavn}` : '';
  return `${titelOgNavn}${efternavn}${fodtSuffiks(dele.fodt)}`;
}
