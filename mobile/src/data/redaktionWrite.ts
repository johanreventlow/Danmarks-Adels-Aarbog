// Oversætter en UI-redigering ("change") til ét RPC-kald mod skrive-laget (Task 3–6).
// Ren build-funktion (buildRpcCall) er netværksfri og unit-testes; submitChange udfører.
// (mediaUpload.ts importeres dynamisk i submitChange, ikke statisk her — den rører native
// device-API'er (billedvælger/filsystem) som ellers ville kræve jest-mocks for HELE denne fil,
// selv i tests der kun øver buildRpcCall's rene logik.)
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
     | 'setFamilieOrdinal' | 'flytBarn'
     | 'sammeSom' | 'fjernSammeSom' // redaktionel identitets-sammenkædning (samme_som)
     | 'opretPerson' | 'opretEstate' | 'opretKilde' | 'opretOrganisation' | 'fortryd'
     | 'uploadMedia' // mediehåndtering Slice 0g — redaktør-upload (portræt/objekt-foto)
     | 'fjernMedia'; // Slice 0h — blødt fjern (upload_status='fjernet'); unlink går via sletRelation
  subjektType: string;
  subjektId: string;
  assertionId?: string;
  factId?: string;
  relationId?: string;
  mediaId?: string;
  familyId?: string;
  tilFamilyId?: string;
  personId?: string;
  rolle?: string;
  konfidens?: string | null;
  ordinal?: number | null;
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
    // p_source_id default 1 (primær DAA-udgave) hvis prefill ikke gav en kilde — mobil
    // redigerer den source-korrekte primær-række (single-narrativ-UI; faner er follow-up).
    return { fn: 'red_upsert_narrativ', args: {
      p_subjekt_type: c.subjektType, p_subjekt_id: sid, p_tekst: c.vaerdi,
      p_privat: Boolean(c.payload?.privat),
      p_source_id: (c.payload?.sourceId as number | null | undefined) ?? 1,
      p_side: (c.payload?.side as string | null | undefined) ?? null } };
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
  if (c.art === 'setFamilieOrdinal') { const b = famLinkBase(c); if (!b || c.ordinal == null) return null;
    return { fn: 'red_set_familie_ordinal', args: { ...b, p_ordinal: c.ordinal } }; }
  if (c.art === 'sammeSom') {
    const p = c.payload || {};
    if (p.aliasId == null || p.objektId == null) return null;
    return { fn: 'red_samme_som', args: { p_alias_id: Number(p.aliasId), p_objekt_id: Number(p.objektId) } };
  }
  if (c.art === 'fjernSammeSom') {
    if (c.relationId == null) return null;
    return { fn: 'red_fjern_samme_som', args: { p_relation_id: Number(c.relationId) } };
  }
  if (c.art === 'flytBarn') {
    if (c.familyId == null || c.tilFamilyId == null || c.personId == null || !c.rolle) return null;
    return { fn: 'red_flyt_barn', args: {
      p_fra_family_id: Number(c.familyId), p_til_family_id: Number(c.tilFamilyId),
      p_barn_id: Number(c.personId), p_rolle: c.rolle } };
  }
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
  // Portræt (p_afbildet_person_id) ELLER objekt-foto (p_objekt_type/p_objekt_id) — aldrig
  // begge (red_upload_media/red_relation håndhæver dette server-side, GDPR-invarianten).
  // p_titel er PÅKRÆVET af RPC'en (intet DEFAULT) — payload skal altid sætte et.
  if (c.art === 'uploadMedia') {
    const p = c.payload || {};
    if (!p.slags || !p.titel || !p.storagePath || !p.mimeType) return null;
    const args: Record<string, unknown> = {
      p_slags: p.slags, p_titel: p.titel, p_storage_path: p.storagePath, p_mime: p.mimeType,
      p_byte_size: p.byteSize ?? null, p_bredde: p.bredde ?? null, p_hoejde: p.hoejde ?? null,
      p_original_filnavn: p.originalFilnavn ?? null,
      p_rettigheder_status: p.rettighederStatus ?? 'ukendt', p_maa_publiceres: Boolean(p.maaPubliceres),
    };
    if (p.afbildetPersonId != null) args.p_afbildet_person_id = Number(p.afbildetPersonId);
    else if (p.objektType != null && p.objektId != null) {
      args.p_objekt_type = p.objektType;
      args.p_objekt_id = Number(p.objektId);
    }
    return { fn: 'red_upload_media', args };
  }
  // Blødt fjern (Slice 0h): sætter upload_status='fjernet', rører aldrig Storage-bytes eller
  // relationen. At AFKOBLE et billede fra én person (uden at slette det andre steder) er derimod
  // bare en almindelig 'sletRelation' på den specifikke afbildet-relation (håndteret ovenfor).
  if (c.art === 'fjernMedia') {
    if (c.mediaId == null) return null;
    return { fn: 'red_fjern_media', args: { p_media_id: Number(c.mediaId) } };
  }
  return null;
}

// Menneskelæselig forhåndsvisning til dry-run-sheet (matcher prototypens kode-blok-stil).
export function describeCall(call: RpcCall): string {
  return `rpc ${call.fn}\n${JSON.stringify(call.args, null, 2)}`;
}

// dry-run: returnér det planlagte kald (UI viser fn+args). live: udfør via supabase.rpc.
// uploadMedia er særligt: bytes skal lande i Storage FØR RPC'en (Postgres-txn og Storage-upload
// kan ikke dele transaktion, jf. planens to-fase-upload). Sker KUN i LIVE — dry-run rører hverken
// Storage eller basen, ellers ville "Forhåndsvis" efterlade en rigtig fil i den private bucket.
// red_upload_media opretter ALTID rækken som upload_status='kladde' (schema-default); først når
// bytes reelt ligger i Storage (lige udført ovenfor) er det sandt at bekræfte 'klar' — derfor et
// eksplicit andet RPC-kald bagefter, ikke en del af red_upload_media selv.
export async function submitChange(c: Change, opts: { dryRun: boolean }) {
  const call = buildRpcCall(c);
  if (!call) throw new Error(`Kan ikke bygge RPC-kald for art=${c.art} felt=${c.felt}`);
  if (opts.dryRun) return { dryRun: true as const, call };
  if (!supabase) throw new Error('Supabase ikke konfigureret');
  if (c.art === 'uploadMedia') {
    const p = c.payload || {};
    if (!p.localUri || !p.storagePath) throw new Error('Mangler lokal fil eller sti til upload');
    const { performUpload } = await import('../lib/mediaUpload');
    await performUpload(String(p.localUri), String(p.storagePath), String(p.mimeType ?? 'application/octet-stream'));
  }
  const { data, error } = await supabase.rpc(call.fn, call.args);
  if (error) throw new Error(error.message);
  if (c.art === 'uploadMedia') {
    const { error: bekraeftError } = await supabase.rpc('red_bekraeft_media_upload', { p_media_id: data });
    if (bekraeftError) throw new Error(bekraeftError.message);
  }
  return { dryRun: false as const, call, result: data };
}

// Genkender red_fortryd_change_set's B9-divergens-RAISE ("... afvist (brug force)").
// Co-lokaliseret med oversaetFejl (samme rå-besked-klassifikations-mønster). Regex'en pinner
// IKKE mod den levende DB-tekst — kun mod testens hardkodede kopi; drifter schema.sql's
// RAISE-formulering, skal matchen opdateres her manuelt.
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
