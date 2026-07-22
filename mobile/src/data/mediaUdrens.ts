type UdrensResult = {
  stier?: { bucket: string; sti: string }[];
};

type RemoveObjects = (
  bucket: string,
  stier: string[],
) => Promise<{ error: { message: string } | null }>;

export async function cleanupUdrensStorage(
  result: unknown,
  removeObjects: RemoveObjects,
): Promise<string | null> {
  const stier = ((result as UdrensResult | null)?.stier ?? []);
  const perBucket = new Map<string, string[]>();
  for (const { bucket, sti } of stier) {
    perBucket.set(bucket, [...(perBucket.get(bucket) ?? []), sti]);
  }

  const fejl: string[] = [];
  for (const [bucket, paths] of perBucket) {
    try {
      const { error } = await removeObjects(bucket, paths);
      if (error) fejl.push(`${bucket}: ${error.message}`);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      fejl.push(`${bucket}: ${message}`);
    }
  }

  return fejl.length
    ? `Rækken er slettet, men ${fejl.length} Storage-kald fejlede (${fejl.join('; ')}) — de forladte bytes er usynlige og ryddes af janitoren.`
    : null;
}
