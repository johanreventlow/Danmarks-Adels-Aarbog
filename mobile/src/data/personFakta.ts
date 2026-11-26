// Personens fakta med kilde pr. udgave (paritetsplanens batch 7) — mobilens pendant til web's fakta-hentning i
// fetchPersonDetail (web/src/data/public.ts): RPC'en public_person_facts for den foldede persons medlems-id'er
// (physicalPersonIds, som web's personMemberIds) og redaktørens fritekstkilder fra citation. Visningen bygges af
// @daa/core's byggUdgaveFakta med præcis samme input som web, så rækkerne er de samme.
//
// RPC'en har i dag intet loft på array-længden (docs/decisions.md, »Hul 1«); mobilen holder sig alligevel til få
// id'er pr. kald (FAKTA_BID), så et kald aldrig nærmer sig gæsternes 3 s-loft. En person har typisk 1-3 medlemmer.
// En fejl i RPC'en giver fejl = true (skærmen siger »Fakta kunne ikke hentes«); fritekstkilderne er tolerante.
import {
  FAKTA_UDELADT, physicalPersonIds, SLUKKET_ENIGHED,
  type Model, type Provenance, type PublicPersonFactRow, type UdgaveFaktaInput,
} from '@daa/core';
import type { supabase } from '../lib/supabase';
import { chunks } from './bidder';

export const FAKTA_BID = 20;
const CITATION_BID = 200;

type Sb = NonNullable<typeof supabase>;
export type PersonFaktaResultat = { input: UdgaveFaktaInput | null; fejl: boolean };

// Faktarækkerne for alle id'erne, i bidder à højst FAKTA_BID; null ved enhver fejl (også et kast i svarbehandlingen).
export async function hentFaktaRaekker(sb: Sb, personIds: readonly string[]): Promise<PublicPersonFactRow[] | null> {
  const numIds = [...new Set(personIds)].map(Number).filter((n) => !Number.isNaN(n));
  try {
    const ud: PublicPersonFactRow[] = [];
    for (const bid of chunks(numIds, FAKTA_BID)) {
      const res = await sb.rpc('public_person_facts', { p_person_ids: bid });
      if (!res || res.error || !Array.isArray(res.data)) return null;
      ud.push(...(res.data as PublicPersonFactRow[]));
    }
    return ud;
  } catch {
    return null;
  }
}

// Redaktørens fritekstkilder (citationer uden source_id) for de valgte påstande uden bogkilde — port af web's
// fetchFritekstKilde. Tolerant: en fejl giver {} (faktummet står så med »Kilde ikke registreret«).
export async function hentFritekstKilde(sb: Sb, rows: readonly PublicPersonFactRow[]): Promise<Record<string, string[]>> {
  const ids = [...new Set(rows
    .filter((r) => r.chosen === true && r.source_id == null && !r.record_ref && !FAKTA_UDELADT.includes(r.faktatype))
    .map((r) => r.assertion_id))];
  if (!ids.length) return {};
  try {
    const ud: Record<string, string[]> = {};
    for (const bid of chunks(ids, CITATION_BID)) {
      const res = await sb.from('citation').select('assertion_id,citat_tekst').is('source_id', null).in('assertion_id', bid as number[]);
      if (res.error) return {};
      for (const c of (res.data ?? []) as unknown as { assertion_id: number | string; citat_tekst: string | null }[]) {
        if (!c.citat_tekst || !c.citat_tekst.trim()) continue;
        (ud[String(c.assertion_id)] ??= []).push(c.citat_tekst);
      }
    }
    return ud;
  } catch {
    return {};
  }
}

// Input til byggUdgaveFakta — samme felter som web (public.ts: rows, udgaver, udgaveForPersonRaekke, fritekstKilde,
// SLUKKET_ENIGHED).
export function byggFaktaInput(
  rows: PublicPersonFactRow[],
  model: Pick<Model, 'udgaver' | 'udgaveForPersonRaekke'>,
  fritekstKilde: Record<string, string[]>,
): UdgaveFaktaInput {
  return {
    rows,
    udgaver: model.udgaver ?? [],
    udgaveForPersonRaekke: model.udgaveForPersonRaekke ?? {},
    fritekstKilde,
    slukketEnighed: SLUKKET_ENIGHED,
  };
}

export async function hentPersonFakta(
  sb: Sb | null,
  canonicalId: string,
  mergedFrom: readonly Provenance[] | undefined,
  model: Pick<Model, 'udgaver' | 'udgaveForPersonRaekke'>,
): Promise<PersonFaktaResultat> {
  if (!sb) return { input: null, fejl: true };
  const rows = await hentFaktaRaekker(sb, physicalPersonIds(canonicalId, mergedFrom));
  if (rows === null) return { input: null, fejl: true };
  const fritekst = await hentFritekstKilde(sb, rows);
  return { input: byggFaktaInput(rows, model, fritekst), fejl: false };
}
