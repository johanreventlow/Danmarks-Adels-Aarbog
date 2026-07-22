// Fase 4 (M11): klient-orkestrering af udrensning — DB-først, Storage bagefter (spec §4.2).
// Ren funktion med injicerede deps, så dryRun-gaten OG "advarsel, ikke fejl"-kontrakten er
// vitest-dækket (dryRun-threading-regressionstesten er obligatorisk pr. ny skrivevej, PR #72).
import type { Change } from './redaktionWrite';

type SubmitFn = (c: Change, o: { dryRun: boolean; role?: string }) => Promise<{ dryRun: boolean; result?: unknown }>;
type RemoveFn = (bucket: string, stier: string[]) => Promise<{ error: { message: string } | null }>;

export async function executeUdrens(
  opts: { mediaId: string; dryRun: boolean; role?: string },
  deps: { submit: SubmitFn; removeObjects: RemoveFn },
): Promise<{ kind: 'dry-run' | 'completed'; storageAdvarsel?: string }> {
  const res = await deps.submit(
    { art: 'udrensMedia', subjektType: 'media', subjektId: opts.mediaId, mediaId: opts.mediaId },
    { dryRun: opts.dryRun, role: opts.role },
  );
  if (res.dryRun) return { kind: 'dry-run' };
  const stier = ((res.result as { stier?: { bucket: string; sti: string }[] } | null)?.stier ?? []);
  const byBucket = new Map<string, string[]>();
  for (const s of stier) byBucket.set(s.bucket, [...(byBucket.get(s.bucket) ?? []), s.sti]);
  const fejl: string[] = [];
  for (const [bucket, paths] of byBucket) {
    const { error } = await deps.removeObjects(bucket, paths);
    if (error) fejl.push(`${bucket}: ${error.message}`);
  }
  return fejl.length
    ? { kind: 'completed', storageAdvarsel: `Rækken er slettet, men ${fejl.length} Storage-kald fejlede (${fejl.join('; ')}) — de forladte bytes er usynlige og ryddes af janitoren.` }
    : { kind: 'completed' };
}
