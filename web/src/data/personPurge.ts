import { supabase } from '../supabase';
import type { Change } from './redaktionWrite';

export type PurgeFil = { bucket: string; sti: string; oprettet?: string };
export type PurgeSted = { tabel: string; pk: Record<string, unknown>; handling: string; grund: string };
export type PurgePreview = {
  person_id: number | string; navn: string | null; sha256: string;
  steder: Record<string, PurgeSted[]>;
  familier_slettes: (number | string)[]; familier_bevares: (number | string)[];
  // Review 37 P1+P2. Valgfri: et preview fra en database uden ændringen har dem ikke (web deployes før prod-DDL).
  vielser_staar?: (number | string)[]; vielser_slettes?: (number | string)[];
  medier_skjules?: (number | string)[];
  blokeringer: { art: string; [key: string]: unknown }[];
  advarsler: { art: string; [key: string]: unknown }[];
  til_kontrol: { sted: string; tabel: string; pk: Record<string, unknown>; grund: string }[];
  levende_bruger: boolean;
};
type SubmitFn = (c: Change, o: { dryRun: boolean; role?: string }) => Promise<{ dryRun: boolean; result?: unknown }>;
type RemoveResult = { data: { name: string }[] | null; error: { message: string } | null };
export type PurgeStorageDeps = {
  submit: SubmitFn;
  listOutbox: () => Promise<PurgeFil[]>;
  removeObjects: (bucket: string, stier: string[]) => Promise<RemoveResult>;
  // Kun et vellykket opslag eller en eksplicit 404 kan bekræfte fravær efter en mistet kvittering.
  objectAbsent: (bucket: string, sti: string) => Promise<boolean>;
};
export type PurgeResult = { kind: 'dry-run' | 'completed'; storageAdvarsel?: string };

export async function fetchPurgePreview(personId: string): Promise<PurgePreview> {
  const { data, error } = await supabase.rpc('red_slet_person_helt_preview', { p_person_id: personId });
  if (error) throw error;
  return data as PurgePreview;
}
export async function fetchPurgeUdbakke(): Promise<PurgeFil[]> {
  const { data, error } = await supabase.rpc('red_person_purge_udbakke');
  if (error) throw error;
  return (data ?? []) as PurgeFil[];
}
export const purgeStorage = {
  listOutbox: fetchPurgeUdbakke,
  removeObjects: async (bucket: string, paths: string[]) => supabase.storage.from(bucket).remove(paths),
  objectAbsent: async (bucket: string, sti: string) => {
    // Den eksisterende SELECT-policy giver redaktion fuldt indblik i media-bucketen.
    // En 404 i andre buckets kan skyldes manglende indblik og er ikke bevis på fravær.
    if (bucket !== 'media') return false;
    const { data, error } = await supabase.storage.from(bucket).exists(sti);
    return (!error && data === false) || (error != null && 'status' in error && error.status === 404);
  },
};

function rawError(e: unknown): string {
  if (e && typeof e === 'object') {
    const { code, message } = e as { code?: string; message?: string };
    if (code || message) return [code, message].filter(Boolean).join(': ');
  }
  return String(e);
}
export function purgeFejl(e: unknown): { kind: 'retry' | 'blocked' | 'raw'; tekst: string } {
  const raw = rawError(e);
  // 57014 = authenticated-rollens statement_timeout (8 s i prod). Hele kaldet rulles tilbage; første kald
  // i en kold prod-base kan ramme den (målt 18/11), et nyt forsøg er varmt.
  if (/\b57014\b/.test(raw)) {
    return { kind: 'retry', tekst: 'Det tog for lang tid — intet er slettet. Prøv igen.' };
  }
  if (/\b(PURGE_PREVIEW_AENDRET|PURGE_LOCKSET_DRIFT|PURGE_REST)\b|\b(40P01|55P03)\b/.test(raw)) {
    return { kind: 'retry', tekst: 'Noget ændrede sig undervejs — intet er slettet. Prøv igen.' };
  }
  if (/\bPURGE_BLOKERET:/.test(raw)) return { kind: 'blocked', tekst: `Blokering: ${raw}` };
  return { kind: 'raw', tekst: raw };
}

// RPC'en filtrerer stier med levende media-/variantreferencer. Restvindue: en upload kan
// genbruge en sti efter listOutbox og før Storage.remove; DB og Storage deler ingen transaktion.
// Samme klasse som executeUdrens; triggerne kan ikke tilbagekalde en allerede hentet liste.
// Udbakken er autoritativ EFTER commit. Samme oprydning bruges ved sletning og ved genforsøg.
// Fejl efter DB-sletning er advarsler, også når Storage, læsning eller kvittering kaster.
export async function executePurgeOprydning(
  opts: { dryRun: boolean; role?: string }, deps: PurgeStorageDeps,
): Promise<PurgeResult> {
  if (opts.role !== 'redaktion') throw new Error('Kun redaktion');
  if (opts.dryRun) return { kind: 'dry-run' };
  const fejl: string[] = [];
  try {
    const byBucket = new Map<string, Set<string>>();
    for (const { bucket, sti } of await deps.listOutbox()) {
      if (!byBucket.has(bucket)) byBucket.set(bucket, new Set());
      byBucket.get(bucket)!.add(sti);
    }
    for (const [bucket, paths] of byBucket) {
      try {
        const { data, error } = await deps.removeObjects(bucket, [...paths]);
        if (error) { fejl.push(`${bucket}: ${error.message}`); continue; }
        const confirmed = new Set((data ?? []).map((f) => f.name));
        for (const sti of paths) {
          try {
            if (!confirmed.has(sti) && !await deps.objectAbsent(bucket, sti)) {
              fejl.push(`${bucket}/${sti}: sletning ikke bekræftet`); continue;
            }
            const ack = await deps.submit({ art: 'kvitterPersonPurgeFil', subjektType: 'storage', subjektId: '',
              payload: { bucket, sti } }, { dryRun: opts.dryRun, role: opts.role });
            if (ack.dryRun) fejl.push(`${bucket}/${sti}: kvittering ikke udført`);
          } catch (e) { fejl.push(`${bucket}/${sti}: ${rawError(e)}`); }
        }
      } catch (e) { fejl.push(`${bucket}: ${rawError(e)}`); }
    }
  } catch (e) { fejl.push(rawError(e)); }
  return fejl.length ? { kind: 'completed', storageAdvarsel:
    `Filer venter stadig på sletning eller kvittering (${fejl.join('; ')}). Prøv oprydningen igen i »Filer der venter på sletning«.` }
    : { kind: 'completed' };
}

export async function executeSletHelt(
  opts: { personId: string; previewSha256: string; dryRun: boolean; role?: string }, deps: PurgeStorageDeps,
): Promise<PurgeResult> {
  if (opts.role !== 'redaktion') throw new Error('Kun redaktion');
  const res = await deps.submit({ art: 'sletPersonHelt', subjektType: 'person', subjektId: opts.personId,
    payload: { previewSha256: opts.previewSha256 } }, { dryRun: opts.dryRun, role: opts.role });
  if (res.dryRun) return { kind: 'dry-run' };
  return executePurgeOprydning(opts, deps);
}
