import { supabase } from '../lib/supabase';
import { getMediaAuthEpoch, isMediaAuthEpochCurrent, signPaths } from '../lib/media';
import type { ResizedVariant } from '../lib/mediaUpload';

export type MediaDedupTarget = {
  maalType: 'person' | 'estate' | 'coat_of_arms' | 'lineage';
  maalId: string;
};

export type MediaDedupHit = {
  id: string;
  titel: string | null;
  uploadStatus: string;
  storagePath: string | null;
  thumbUrl: string | null;
};

type LookupError = { message: string } | null;
type RawMediaHit = { id: number | string; titel: string | null; upload_status: string; storage_path: string | null };
type RelationLookup = (filters: Record<string, string>) => Promise<{ data: { id: unknown } | null; error: LookupError }>;
type MediaLookup = (sha: string) => Promise<{ data: RawMediaHit | null; error: LookupError }>;
type ThumbPathLookup = (mediaId: string) => Promise<string | null>;
type MediaShaQueryClient = {
  from: (table: string) => {
    select: (columns: string) => {
      eq: (column: string, value: string) => {
        maybeSingle: () => Promise<{ data: RawMediaHit | null; error: LookupError }>;
      };
    };
  };
};

export function deriveMediaDedupTarget(uploadTarget: Record<string, unknown>): MediaDedupTarget | null {
  if (uploadTarget.afbildetPersonId != null) {
    return { maalType: 'person', maalId: String(uploadTarget.afbildetPersonId) };
  }
  const maalType = uploadTarget.objektType;
  const maalId = uploadTarget.objektId;
  if ((maalType === 'estate' || maalType === 'coat_of_arms' || maalType === 'lineage') && maalId != null) {
    return { maalType, maalId: String(maalId) };
  }
  return null;
}

export function relationFiltersForTarget(mediaId: string, target: MediaDedupTarget): Record<string, string> {
  if (target.maalType === 'person') {
    return {
      subjekt_type: 'person', subjekt_id: target.maalId,
      objekt_type: 'media', objekt_id: mediaId, rolle: 'afbildet',
    };
  }
  return {
    subjekt_type: 'media', subjekt_id: mediaId,
    objekt_type: target.maalType, objekt_id: target.maalId, rolle: 'afbildet',
  };
}

const defaultRelationLookup: RelationLookup = async (filters) => {
  if (!supabase) return { data: null, error: { message: 'Supabase ikke konfigureret' } };
  let query = supabase.from('relation').select('id');
  for (const [column, value] of Object.entries(filters)) query = query.eq(column, value);
  const { data, error } = await query.limit(1).maybeSingle();
  return { data, error };
};

export async function fetchMediaLinked(
  mediaId: string,
  target: MediaDedupTarget,
  lookup: RelationLookup = defaultRelationLookup,
): Promise<boolean> {
  const { data, error } = await lookup(relationFiltersForTarget(mediaId, target));
  if (error) throw new Error(`Kunne ikke kontrollere eksisterende medietilknytning: ${error.message}`);
  return data != null;
}

const MEDIA_DEDUP_SELECT = 'id::text,titel,upload_status,storage_path';

export async function queryMediaBySha(
  sha: string,
  client?: MediaShaQueryClient,
): ReturnType<MediaLookup> {
  if (client) return client.from('media').select(MEDIA_DEDUP_SELECT).eq('sha256', sha).maybeSingle();
  if (!supabase) return { data: null, error: { message: 'Supabase ikke konfigureret' } };
  const { data, error } = await supabase.from('media')
    .select(MEDIA_DEDUP_SELECT)
    .eq('sha256', sha)
    .maybeSingle();
  return { data: data as unknown as RawMediaHit | null, error };
}

const defaultThumbPathLookup: ThumbPathLookup = async (mediaId) => {
  if (!supabase) throw new Error('Supabase ikke konfigureret');
  const { data, error } = await supabase.from('media_variant')
    .select('storage_path')
    .eq('media_id', mediaId)
    .eq('tier', 'thumb')
    .maybeSingle();
  if (error) throw new Error(`Kunne ikke hente eksisterende miniature: ${error.message}`);
  return data?.storage_path ?? null;
};

export async function fetchExistingMediaBySha(
  sha: string,
  deps: {
    mediaLookup?: MediaLookup;
    thumbPath?: ThumbPathLookup;
    sign?: typeof signPaths;
    epoch?: number;
  } = {},
): Promise<MediaDedupHit | null> {
  const { data, error } = await (deps.mediaLookup ?? queryMediaBySha)(sha);
  if (error) throw new Error(`Kunne ikke kontrollere mediebiblioteket: ${error.message}`);
  if (!data) return null;
  const id = String(data.id);
  const thumbPath = await (deps.thumbPath ?? defaultThumbPathLookup)(id);
  const paths = [data.storage_path, thumbPath].filter((path): path is string => Boolean(path));
  const epoch = deps.epoch ?? getMediaAuthEpoch();
  const signed = await (deps.sign ?? signPaths)(paths, epoch);
  if (!isMediaAuthEpochCurrent(epoch)) return null;
  const fallbackUrl = data.storage_path ? signed.get(data.storage_path) ?? null : null;
  const thumbUrl = thumbPath ? signed.get(thumbPath) : undefined;
  return {
    id,
    titel: data.titel,
    uploadStatus: data.upload_status,
    storagePath: data.storage_path,
    thumbUrl: thumbUrl ?? fallbackUrl,
  };
}

export function mediaDetailRoute(mediaId: string): string {
  return `/redaktion/entitet/medie/${mediaId}`;
}

export type MediaDedupDecision =
  | { kind: 'klar-link'; alreadyLinked: boolean }
  | { kind: 'fjernet'; route: string }
  | { kind: 'kladde'; alreadyLinked: boolean }
  | { kind: 'unsupported' };

export function decideMediaDedup(
  hit: Pick<MediaDedupHit, 'id' | 'uploadStatus'>,
  alreadyLinked: boolean,
): MediaDedupDecision {
  if (hit.uploadStatus === 'klar') return { kind: 'klar-link', alreadyLinked };
  if (hit.uploadStatus === 'fjernet') return { kind: 'fjernet', route: mediaDetailRoute(hit.id) };
  if (hit.uploadStatus === 'kladde') return { kind: 'kladde', alreadyLinked };
  return { kind: 'unsupported' };
}

type LinkDeps = {
  link: (mediaId: string, target: MediaDedupTarget) => Promise<void>;
  refresh: () => Promise<void>;
};

export async function ensureExistingMediaLinked(
  args: { mediaId: string; target: MediaDedupTarget; alreadyLinked: boolean },
  deps: LinkDeps,
): Promise<void> {
  try {
    // Preflight er kun et øjebliksbillede. Forsøg altid RPC'en, så postconditionen holder,
    // også hvis relationen ændres mellem opslag og handling.
    await deps.link(args.mediaId, args.target);
  } catch (error) {
    const message = String((error as Error)?.message ?? error);
    if (!/allerede tilknyttet dette subjekt/i.test(message)) throw error;
  }
  await deps.refresh();
}

export type ResumeMediaUploadStep =
  | { kind: 'upload'; uri: string; storagePath: string; mimeType: string }
  | { kind: 'rpc'; fn: 'red_bekraeft_media_upload' | 'red_registrer_media_variant'; args: Record<string, unknown> };

function parsePostgresBigintId(value: string): number | string | null {
  const raw = value.trim();
  if (!/^[1-9][0-9]*$/.test(raw) || raw.length > 19 || (raw.length === 19 && raw > '9223372036854775807')) return null;
  const id = Number(raw);
  return Number.isSafeInteger(id) ? id : raw;
}

export function buildResumeMediaUploadPlan(
  mediaId: string,
  large: ResizedVariant,
  variants: ResizedVariant[],
): ResumeMediaUploadStep[] {
  const parsedMediaId = parsePostgresBigintId(mediaId);
  if (parsedMediaId == null) throw new Error('Ugyldigt media-id ved genoptagelse.');
  return [
    { kind: 'upload', uri: large.uri, storagePath: large.storagePath, mimeType: large.mimeType },
    ...variants.flatMap((variant): ResumeMediaUploadStep[] => [
      { kind: 'upload', uri: variant.uri, storagePath: variant.storagePath, mimeType: variant.mimeType },
      { kind: 'rpc', fn: 'red_registrer_media_variant', args: {
        p_media_id: parsedMediaId, p_tier: variant.tier, p_storage_path: variant.storagePath,
        p_mime: variant.mimeType, p_byte_size: variant.byteSize,
        p_bredde: variant.bredde, p_hoejde: variant.hoejde,
      } },
    ]),
    { kind: 'rpc', fn: 'red_bekraeft_media_upload', args: { p_media_id: parsedMediaId } },
  ];
}

export async function executeMediaDedupResume(
  args: {
    dryRun: boolean;
    mediaId: string;
    alreadyLinked: boolean;
    target: MediaDedupTarget;
    large: ResizedVariant;
    variants: ResizedVariant[];
  },
  deps: LinkDeps & {
    upload?: (uri: string, storagePath: string, mimeType: string) => Promise<void>;
    rpc?: (fn: 'red_bekraeft_media_upload' | 'red_registrer_media_variant', args: Record<string, unknown>) => Promise<void>;
  },
): Promise<{ kind: 'dry-run' | 'completed' }> {
  if (args.dryRun) return { kind: 'dry-run' };
  for (const step of buildResumeMediaUploadPlan(args.mediaId, args.large, args.variants)) {
    if (step.kind === 'upload') {
      if (deps.upload) await deps.upload(step.uri, step.storagePath, step.mimeType);
      else {
        const { performUpload } = await import('../lib/mediaUpload');
        await performUpload(step.uri, step.storagePath, step.mimeType);
      }
    } else if (deps.rpc) await deps.rpc(step.fn, step.args);
    else {
      if (!supabase) throw new Error('Supabase ikke konfigureret');
      const { error } = await supabase.rpc(step.fn, step.args);
      if (error) throw new Error(error.message);
    }
  }
  await ensureExistingMediaLinked(args, deps);
  return { kind: 'completed' };
}
