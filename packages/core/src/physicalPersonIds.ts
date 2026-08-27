import type { Provenance } from './types';

/**
 * Returnerer alle fysiske personrækker bag en kanonisk same_som-person.
 * Den kanoniske id er altid først; aliaser er unikke og stabilt sorterede.
 */
export function physicalPersonIds(
  canonicalId: string,
  mergedFrom?: ReadonlyArray<Pick<Provenance, 'personId'>>,
): string[] {
  const aliases = new Set(
    (mergedFrom ?? [])
      .map(({ personId }) => personId)
      .filter((personId) => personId !== '' && personId !== canonicalId),
  );
  return [canonicalId, ...[...aliases].sort()];
}
