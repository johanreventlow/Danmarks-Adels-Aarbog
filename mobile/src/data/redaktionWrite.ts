// Oversætter en UI-redigering ("change") til ét RPC-kald mod skrive-laget (Task 3–6).
// Ren build-funktion (buildRpcCall) er netværksfri og unit-testes; submitChange udfører.
import { supabase } from '../lib/supabase';

// felt → fact.faktatype. koen er BEVIDST udeladt: arbejdsværdi på person, ikke et fact.
export const FELT_FAKTATYPE: Record<string, string> = {
  navn: 'navn', foedt: 'fødsel', doed: 'død', titel: 'titel',
};
const DATE_FELT = new Set(['foedt', 'doed']);

export type Change = {
  art: 'fakta' | 'narrativ' | 'relation' | 'gods' | 'hverv';
  subjektType: string;
  subjektId: string;
  felt?: string;
  vaerdi?: string;
  kildeFritekst?: string;
  payload?: Record<string, unknown>;
};

export type RpcCall = { fn: string; args: Record<string, unknown> };

export function buildRpcCall(c: Change): RpcCall | null {
  const sid = Number(c.subjektId);
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
