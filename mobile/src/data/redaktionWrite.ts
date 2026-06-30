// Oversætter en UI-redigering ("change") til ét RPC-kald mod skrive-laget (Task 3–6).
// Ren build-funktion (buildRpcCall) er netværksfri og unit-testes; submitChange udfører.
import { supabase } from '../lib/supabase';

// felt → fact.faktatype. koen er BEVIDST udeladt: arbejdsværdi på person, ikke et fact.
export const FELT_FAKTATYPE: Record<string, string> = {
  navn: 'navn', foedt: 'fødsel', doed: 'død', titel: 'titel',
};
const DATE_FELT = new Set(['foedt', 'doed']);

export type Change = {
  art: 'fakta' | 'narrativ' | 'relation' | 'gods' | 'hverv'
     | 'redigerOplysning' | 'sletOplysning' | 'setKonklusion' | 'setPrivat' | 'sletPerson'
     | 'tilfoejOplysning' | 'opretFakta' | 'sletRelation' | 'tilfoejRelation'
     | 'opretUnion' | 'tilfoejBarn' | 'setFamilieKonfidens' | 'sletFamilieLink'
     | 'opretPerson' | 'opretEstate' | 'opretKilde' | 'opretOrganisation' | 'fortryd';
  subjektType: string;
  subjektId: string;
  assertionId?: string;
  factId?: string;
  relationId?: string;
  familyId?: string;
  personId?: string;
  rolle?: string;
  konfidens?: string | null;
  felt?: string;
  vaerdi?: string;
  kildeFritekst?: string;
  payload?: Record<string, unknown>;
};

export type RpcCall = { fn: string; args: Record<string, unknown> };

function famLinkBase(c: Change): { p_family_id: number; p_person_id: number; p_rolle: string } | null {
  if (c.familyId == null || c.personId == null || !c.rolle) return null;
  return { p_family_id: Number(c.familyId), p_person_id: Number(c.personId), p_rolle: c.rolle };
}

export function buildRpcCall(c: Change): RpcCall | null {
  const sid = Number(c.subjektId);
  const aid = c.assertionId != null ? Number(c.assertionId) : null;
  if (c.art === 'setKonklusion') {
    if (aid == null) return null;
    return { fn: 'red_set_konklusion', args: { p_assertion_id: aid } };
  }
  if (c.art === 'fortryd') {
    const csId = c.payload?.changeSetId;
    if (csId == null) return null;
    return { fn: 'red_fortryd_change_set',
             args: { p_change_set_id: Number(csId), p_force: Boolean(c.payload?.force) } };
  }
  if (c.art === 'redigerOplysning') {
    if (aid == null) return null;
    const args: Record<string, unknown> = { p_assertion_id: aid, p_vaerdi: c.vaerdi };
    if (c.felt && DATE_FELT.has(c.felt)) args.p_date_raw = c.vaerdi;
    if (c.kildeFritekst != null) args.p_kilde_fritekst = c.kildeFritekst;
    return { fn: 'red_edit_oplysning', args };
  }
  if (c.art === 'sletOplysning') {
    if (aid == null) return null;
    return { fn: 'red_slet_oplysning', args: { p_assertion_id: aid } };
  }
  if (c.art === 'setPrivat') {
    return { fn: 'red_set_privat', args: { p_person_id: sid, p_privat: Boolean(c.payload?.privat) } };
  }
  if (c.art === 'sletPerson') {
    return { fn: 'red_slet_person', args: { p_person_id: sid } };
  }
  // Operation A: tilføj oplysning til EKSISTERENDE fact (fact-målrettet, fact-kardinalitet).
  if (c.art === 'tilfoejOplysning') {
    const fid = c.factId != null ? Number(c.factId) : null;
    if (fid == null) return null;
    const args: Record<string, unknown> = { p_fact_id: fid, p_vaerdi: c.vaerdi };
    if (c.felt && DATE_FELT.has(c.felt)) args.p_date_raw = c.vaerdi;
    if (c.kildeFritekst != null) args.p_kilde_fritekst = c.kildeFritekst;
    return { fn: 'red_tilfoej_oplysning', args };
  }
  // Operation B: opret NYT distinkt fact (fx ny titel).
  if (c.art === 'opretFakta' && c.felt && FELT_FAKTATYPE[c.felt]) {
    const args: Record<string, unknown> = {
      p_subjekt_type: c.subjektType, p_subjekt_id: sid,
      p_faktatype: FELT_FAKTATYPE[c.felt], p_vaerdi: c.vaerdi,
    };
    if (DATE_FELT.has(c.felt)) args.p_date_raw = c.vaerdi;
    if (c.kildeFritekst != null) args.p_kilde_fritekst = c.kildeFritekst;
    return { fn: 'red_opret_fakta', args };
  }
  if (c.art === 'fakta' && c.felt === 'koen') {
    return { fn: 'red_set_koen', args: { p_person_id: sid, p_koen: c.vaerdi } };
  }
  if (c.art === 'fakta' && c.felt && FELT_FAKTATYPE[c.felt]) {
    const args: Record<string, unknown> = {
      p_subjekt_type: c.subjektType, p_subjekt_id: sid,
      p_faktatype: FELT_FAKTATYPE[c.felt], p_vaerdi: c.vaerdi,
    };
    if (DATE_FELT.has(c.felt)) args.p_date_raw = c.vaerdi;
    if (c.kildeFritekst != null) args.p_kilde_fritekst = c.kildeFritekst;
    return { fn: 'red_upsert_fakta', args };
  }
  if (c.art === 'narrativ') {
    return { fn: 'red_upsert_narrativ', args: {
      p_subjekt_type: c.subjektType, p_subjekt_id: sid, p_tekst: c.vaerdi,
      p_privat: Boolean(c.payload?.privat) } };
  }
  if (c.art === 'relation' || c.art === 'gods' || c.art === 'hverv') {
    const p = c.payload || {};
    return { fn: 'red_relation', args: {
      p_subjekt_type: c.subjektType, p_subjekt_id: sid,
      p_objekt_type: p.objektType, p_objekt_id: p.objektId,
      p_rolle: p.rolle, p_periode_raw: p.periodeRaw ?? null } };
  }
  if (c.art === 'sletRelation') {
    const rid = c.relationId != null ? Number(c.relationId) : null;
    if (rid == null) return null;
    return { fn: 'red_slet_relation', args: { p_relation_id: rid } };
  }
  if (c.art === 'tilfoejRelation') {
    const p = c.payload || {};
    return { fn: 'red_tilfoej_relation', args: {
      p_subjekt_id: sid, p_objekt_type: p.objektType, p_objekt_id: Number(p.objektId),
      p_rolle: p.rolle, p_periode_raw: p.periodeRaw ?? null } };
  }
  if (c.art === 'opretUnion') {
    const p = c.payload || {};
    if (p.partnerA == null || p.partnerB == null || !p.type) return null;
    return { fn: 'red_opret_union', args: {
      p_partner_a: Number(p.partnerA), p_partner_b: Number(p.partnerB), p_type: p.type,
      p_ordinal: p.ordinal != null ? Number(p.ordinal) : null } };
  }
  if (c.art === 'tilfoejBarn') {
    const p = c.payload || {};
    if (p.familyId == null || p.barnId == null) return null;
    return { fn: 'red_tilfoej_barn', args: {
      p_family_id: Number(p.familyId), p_barn_id: Number(p.barnId),
      p_rolle: p.rolle || 'barn', p_konfidens: p.konfidens ?? null } };
  }
  if (c.art === 'setFamilieKonfidens') { const b = famLinkBase(c); if (!b) return null;
    return { fn: 'red_set_familie_konfidens', args: { ...b, p_konfidens: c.konfidens ?? null } }; }
  if (c.art === 'sletFamilieLink') { const b = famLinkBase(c); if (!b) return null;
    return { fn: 'red_slet_familie_link', args: b }; }
  if (c.art === 'opretPerson') {
    const p = c.payload || {};
    if (!p.navn) return null;
    const args: Record<string, unknown> = { p_navn: p.navn };
    if (p.koen != null) args.p_koen = p.koen;
    if (p.levende != null) args.p_levende = p.levende;
    if (p.foedtRaw) args.p_foedt_raw = p.foedtRaw;
    if (p.doedRaw) args.p_doed_raw = p.doedRaw;
    if (p.titelRaw) args.p_titel_raw = p.titelRaw;
    return { fn: 'red_opret_person', args };
  }
  if (c.art === 'opretEstate') {
    const p = c.payload || {};
    if (!p.navn) return null;
    const args: Record<string, unknown> = { p_navn: p.navn };
    if (p.slags) args.p_slags = p.slags;
    if (p.stedId != null) args.p_sted_id = Number(p.stedId);
    return { fn: 'red_opret_estate', args };
  }
  if (c.art === 'opretKilde') {
    const p = c.payload || {};
    if (!p.titel) return null;
    const args: Record<string, unknown> = { p_titel: p.titel };
    if (p.slags) args.p_slags = p.slags;
    if (p.udgave) args.p_udgave = p.udgave;
    if (p.ekstern != null) args.p_ekstern = p.ekstern;
    return { fn: 'red_opret_kilde', args };
  }
  if (c.art === 'opretOrganisation') {
    const p = c.payload || {};
    if (!p.navn) return null;
    const args: Record<string, unknown> = { p_navn: p.navn };
    if (p.slags) args.p_slags = p.slags;
    return { fn: 'red_opret_organisation', args };
  }
  return null;
}

// Menneskelæselig forhåndsvisning til dry-run-sheet (matcher prototypens kode-blok-stil).
export function describeCall(call: RpcCall): string {
  return `rpc ${call.fn}\n${JSON.stringify(call.args, null, 2)}`;
}

// dry-run: returnér det planlagte kald (UI viser fn+args). live: udfør via supabase.rpc.
export async function submitChange(c: Change, opts: { dryRun: boolean }) {
  const call = buildRpcCall(c);
  if (!call) throw new Error(`Kan ikke bygge RPC-kald for art=${c.art} felt=${c.felt}`);
  if (opts.dryRun) return { dryRun: true as const, call };
  if (!supabase) throw new Error('Supabase ikke konfigureret');
  const { data, error } = await supabase.rpc(call.fn, call.args);
  if (error) throw new Error(error.message);
  return { dryRun: false as const, call, result: data };
}

// Genkender red_fortryd_change_set's B9-divergens-RAISE ("... afvist (brug force)").
// Co-lokaliseret med oversaetFejl (samme rå-besked-klassifikations-mønster); beskeds-
// matchen skal holdes i sync med DB-RAISE-teksten (schema.sql/db-migrations.sql).
export function erFortrydKonflikt(rawMessage: string): boolean {
  return /afvist.*force/i.test(rawMessage);
}

// PostgREST/Postgres-fejl → dansk UI-tekst (spec §9). Fald tilbage til rå besked.
export function oversaetFejl(message: string): string {
  if (/kun redaktion/i.test(message)) return 'Kræver redaktør-rettigheder.';
  if (/duplicate key|unique/i.test(message)) return 'Findes allerede.';
  if (/not configured|ikke konfigureret/i.test(message)) return 'Ingen forbindelse til basen.';
  // Defensivt fald-tilbage (review10 H2): UI'en skal skjule Fortryd-knappen for allerede
  // fortrudte poster, men hvis en race/forældet liste alligevel rammer DB-guarden direkte.
  if (/allerede fortrudt/i.test(message)) return 'Denne ændring er allerede fortrudt.';
  return message;
}
