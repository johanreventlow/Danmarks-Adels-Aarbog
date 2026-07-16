// PORTERET fra mobile/src/data/redaktionWrite.ts — hold i sync (web udvider med buildSuggestCall
// + planCall rolle-routing). Delt-pakke-ekstraktion er en follow-up.
// Oversætter en UI-redigering ("change") til ét RPC-kald mod skrive-laget (Task 3–6).
// Ren build-funktion (buildRpcCall) er netværksfri og unit-testes; submitChange udfører.
import { supabase } from '../supabase';
import { performUpload } from './mediaUpload';

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
     | 'ikkeSammeSom' | 'fjernIkkeSammeSom' // persisteret identitets-afvisning (tværudgave §4)
     | 'markerForaeldreUkendt' // "forældre ukendt"-markering (docs/reviews/25); fjern = 'tilbagetraekFakta'
     | 'tilbagetraekFakta' // tilbagetræk et fakta-slots konklusion (fjern markering korrekt — review 26 HIGH 2)
     | 'opretKilde' // opret ny source (DAA-udgave) — routes gennem submitChange (dry-run/staging)
     | 'uploadMedia' // mediehåndtering Slice 0g — redaktør-upload (portræt/objekt-foto)
     | 'fjernMedia' // Slice 0h — blødt fjern (upload_status='fjernet'); unlink går via sletRelation
     | 'forslag'; // generisk entitets-feltredigering uden direkte RPC → red_suggest
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
  // "Forældre ukendt"-markering (docs/reviews/25): find-or-create ét fact pr. person via
  // red_upsert_fakta (re-markering opdaterer grad+kilde på samme slot). Grad = c.vaerdi
  // ('forælder ukendt' | 'ingen forbindelse angivet'); kilde = proveniens. Skriver ALDRIG en kant.
  if (c.art === 'markerForaeldreUkendt') {
    if (!c.vaerdi) return null;
    return { fn: 'red_upsert_fakta', args: {
      p_subjekt_type: 'person', p_subjekt_id: sid,
      p_faktatype: 'forældre_ukendt', p_vaerdi: c.vaerdi,
      p_kilde_fritekst: c.kildeFritekst ?? null } };
  }
  // FJERN markering: tilbagetræk fakta-slottets konklusion (status → 'tilbagetrukket'). IKKE
  // sletOplysning — den re-peger til ældste påstand og genopliver markeringen efter Opdatér (HIGH 2).
  if (c.art === 'tilbagetraekFakta') {
    const raw = (c.factId ?? '').trim();
    const fid = raw === '' ? NaN : Number(raw); // Number('')===0 → afvis tom/blank eksplicit
    if (!Number.isFinite(fid)) return null; // afvis "", "x", NaN — ikke kun null
    return { fn: 'red_tilbagetraek_fakta', args: { p_fact_id: fid } };
  }
  if (c.art === 'narrativ') {
    return { fn: 'red_upsert_narrativ', args: {
      p_subjekt_type: c.subjektType, p_subjekt_id: sid, p_tekst: c.vaerdi,
      p_privat: Boolean(c.payload?.privat),
      p_source_id: (c.payload?.sourceId as number | null | undefined) ?? null,
      p_side: (c.payload?.side as string | null | undefined) ?? null } };
  }
  if (c.art === 'opretKilde') {
    const p = c.payload || {};
    if (!p.titel) return null;
    return { fn: 'red_opret_kilde', args: {
      p_titel: p.titel, p_slags: (p.slags as string | null | undefined) ?? null,
      p_udgave: (p.udgave as string | null | undefined) ?? null,
      p_ekstern: Boolean(p.ekstern ?? false),
      p_aar: (p.aar as number | null | undefined) ?? null } };
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
  if (c.art === 'ikkeSammeSom') {
    const p = c.payload || {};
    if (p.aId == null || p.bId == null) return null;
    return { fn: 'red_ikke_samme_som', args: { p_a: Number(p.aId), p_b: Number(p.bId) } };
  }
  if (c.art === 'fjernIkkeSammeSom') {
    if (c.relationId == null) return null;
    return { fn: 'red_fjern_ikke_samme_som', args: { p_relation_id: Number(c.relationId) } };
  }
  if (c.art === 'flytBarn') {
    if (c.familyId == null || c.tilFamilyId == null || c.personId == null || !c.rolle) return null;
    return { fn: 'red_flyt_barn', args: {
      p_fra_family_id: Number(c.familyId), p_til_family_id: Number(c.tilFamilyId),
      p_barn_id: Number(c.personId), p_rolle: c.rolle } };
  }
  // Portræt (p_afbildet_person_id) ELLER objekt-foto (p_objekt_type/p_objekt_id) — aldrig begge
  // (red_upload_media/red_relation håndhæver GDPR-invarianten server-side). p_titel er PÅKRÆVET
  // af RPC'en (intet DEFAULT) — payload skal altid sætte et.
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

// Forslag → staging (red_suggest). Routing-fallback: ikke-redaktion, eller redaktion på en
// art uden direkte RPC (fx generisk entitets-feltredigering). Bygger ALTID et gyldigt kald.
export function buildSuggestCall(c: Change): RpcCall {
  return { fn: 'red_suggest', args: {
    p_art: c.art,
    p_subjekt_type: c.subjektType,
    p_subjekt_id: c.subjektId != null && c.subjektId !== '' ? Number(c.subjektId) : null,
    p_felt: c.felt ?? null,
    p_vaerdi: c.vaerdi ?? null,
    p_kilde_fritekst: c.kildeFritekst ?? null,
    p_payload: c.payload ?? {},
    p_note: null,
  } };
}

// Vælg kald efter rolle: redaktion + kendt art → direkte red_*-RPC; ellers → red_suggest (staging).
export function planCall(c: Change, role: string | undefined): RpcCall {
  const direct = role === 'redaktion' ? buildRpcCall(c) : null;
  return direct ?? buildSuggestCall(c);
}

// dry-run: returnér det planlagte kald (UI viser fn+args). live: udfør via supabase.rpc.
// uploadMedia er særligt: bytes skal lande i Storage FØR RPC'en (Postgres-txn og Storage-upload
// kan ikke dele transaktion). Sker KUN når kaldet reelt går direkte (direkte===true, dvs. rolle
// redaktion) — falder changen igennem til red_suggest (ikke-redaktion) uploades intet, da
// forslags-laget ikke ejer nogen fil-bytes at pege på.
export async function submitChange(c: Change, opts: { dryRun: boolean; role?: string }) {
  const call = planCall(c, opts.role);
  const direkte = call.fn !== 'red_suggest';
  // uploadMedia kan IKKE degradere til red_suggest: forslags-laget gemmer kun p_payload som jsonb,
  // og en rå File-værdi JSON-serialiserer til '{}' (ingen egne enumerable felter) — en sådan
  // "forslag sendt"-kvittering ville lyve. UI'en skjuler allerede knappen for ikke-redaktion
  // (Redaktion.tsx), men denne gate er den robuste, ikke UI-afhængige grænse (fejler tydeligt
  // fremfor at oprette et korrupt forslag med falsk succes).
  if (c.art === 'uploadMedia' && !direkte) {
    throw new Error('Medieupload kræver redaktør-rettigheder — kan ikke sendes som forslag.');
  }
  if (opts.dryRun) return { dryRun: true as const, call, direkte };
  if (c.art === 'uploadMedia') {
    const p = c.payload || {};
    if (!p.file || !p.storagePath) throw new Error('Mangler fil eller sti til upload');
    await performUpload(p.file as Blob, String(p.storagePath));
  }
  const { data, error } = await supabase.rpc(call.fn, call.args);
  if (error) throw new Error(error.message);
  // red_upload_media opretter ALTID rækken som upload_status='kladde'; først når bytes reelt ligger
  // i Storage (lige udført ovenfor) er det sandt at bekræfte 'klar' — derfor et separat RPC-kald.
  if (c.art === 'uploadMedia') {
    const { error: bekraeftError } = await supabase.rpc('red_bekraeft_media_upload', { p_media_id: data });
    if (bekraeftError) throw new Error(bekraeftError.message);
    // Billedstørrelser Slice B2: thumb+medium er selvstændige størrelsestrin (media_variant),
    // ikke en del af red_upload_media selv — hver uploades og registreres uafhængigt af de andre.
    const varianter = (c.payload?.varianter ?? []) as Array<{
      tier: string; file: Blob; storagePath: string; mimeType: string; byteSize: number; bredde: number; hoejde: number;
    }>;
    await Promise.all(varianter.map(async (v) => {
      await performUpload(v.file, v.storagePath);
      const { error: variantError } = await supabase.rpc('red_registrer_media_variant', {
        p_media_id: data, p_tier: v.tier, p_storage_path: v.storagePath,
        p_mime: v.mimeType, p_byte_size: v.byteSize, p_bredde: v.bredde, p_hoejde: v.hoejde,
      });
      if (variantError) throw new Error(variantError.message);
    }));
  }
  return { dryRun: false as const, call, direkte, result: data };
}

// PostgREST/Postgres-fejl → dansk UI-tekst (spec §9). Fald tilbage til rå besked.
export function oversaetFejl(message: string): string {
  if (/kun redaktion/i.test(message)) return 'Kræver redaktør-rettigheder.';
  if (/duplicate key|unique/i.test(message)) return 'Findes allerede.';
  if (/not configured|ikke konfigureret/i.test(message)) return 'Ingen forbindelse til basen.';
  return message;
}
