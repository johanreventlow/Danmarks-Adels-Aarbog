import { supabase } from '../supabase';
import { fetchThumbPathByMediaId, signPaths } from './media';
import type { ResizedVariant } from './mediaUpload';

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
type RelationLookup = (filters: Record<string, string>) => Promise<{ data: { id: unknown } | null; error: LookupError }>;
type RawMediaHit = { id: number | string; titel: string | null; upload_status: string; storage_path: string | null };
type MediaLookup = (sha: string) => Promise<{ data: RawMediaHit | null; error: LookupError }>;

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

const defaultMediaLookup: MediaLookup = async (sha) => {
  const { data, error } = await supabase.from('media')
    .select('id,titel,upload_status,storage_path')
    .eq('sha256', sha)
    .maybeSingle();
  return { data, error };
};

export async function fetchExistingMediaBySha(
  sha: string,
  deps: {
    mediaLookup?: MediaLookup;
    thumbPaths?: typeof fetchThumbPathByMediaId;
    sign?: typeof signPaths;
  } = {},
): Promise<MediaDedupHit | null> {
  const { data, error } = await (deps.mediaLookup ?? defaultMediaLookup)(sha);
  if (error) throw new Error(`Kunne ikke kontrollere mediebiblioteket: ${error.message}`);
  if (!data) return null;
  const id = String(data.id);
  const thumbPaths = await (deps.thumbPaths ?? fetchThumbPathByMediaId)([data.id]);
  const thumbPath = thumbPaths.get(id) ?? null;
  const paths = [data.storage_path, thumbPath].filter((path): path is string => Boolean(path));
  const signed = await (deps.sign ?? signPaths)(paths);
  const fallbackUrl = data.storage_path ? signed.get(data.storage_path) ?? null : null;
  return {
    id, titel: data.titel, uploadStatus: data.upload_status, storagePath: data.storage_path,
    thumbUrl: (thumbPath ? signed.get(thumbPath) ?? null : null) ?? fallbackUrl,
  };
}

export function mediaDetailRoute(mediaId: string): string {
  return `/redaktion/media/${mediaId}`;
}

export type MediaDedupDecision =
  | { kind: 'klar-link' }
  | { kind: 'klar-linked' }
  | { kind: 'fjernet'; route: string }
  | { kind: 'kladde'; alreadyLinked: boolean }
  | { kind: 'unsupported' };

export function decideMediaDedup(
  hit: Pick<MediaDedupHit, 'id' | 'uploadStatus'>,
  alreadyLinked: boolean,
): MediaDedupDecision {
  if (hit.uploadStatus === 'klar') return { kind: alreadyLinked ? 'klar-linked' : 'klar-link' };
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
  if (!args.alreadyLinked) {
    try {
      await deps.link(args.mediaId, args.target);
    } catch (error) {
      const message = String((error as Error)?.message ?? error);
      if (!/allerede tilknyttet dette subjekt/i.test(message)) throw error;
    }
  }
  await deps.refresh();
}

export async function executeMediaDedupResume(
  args: {
    dryRun: boolean; mediaId: string; alreadyLinked: boolean; target: MediaDedupTarget;
    large: ResizedVariant; variants: ResizedVariant[];
  },
  deps: LinkDeps & {
    resume: (mediaId: string, large: ResizedVariant, variants: ResizedVariant[]) => Promise<void>;
  },
): Promise<{ kind: 'dry-run' | 'completed' }> {
  if (args.dryRun) return { kind: 'dry-run' };
  await deps.resume(args.mediaId, args.large, args.variants);
  await ensureExistingMediaLinked(args, deps);
  return { kind: 'completed' };
}
